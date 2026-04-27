//
//  TogetherViewModel.swift
//  Coupley
//
//  Owns the entire Together tab. Three live Firestore listeners (goals,
//  challenges, dreams) feed in, the local `TogetherCoachEngine` derives
//  insights, and the view reads everything through `@Published` state.
//
//  Premium gating is *not* enforced here — the view layer owns it via
//  `PremiumStore.hasAccess`. The viewmodel's job is to surface the data
//  truthfully; the view decides how much to reveal. This separation keeps
//  the model layer free of UI concerns.
//
//  Listeners attach on `startListening` and detach on `stopListening`. We
//  also bind a 5-minute tick timer so insights re-evaluate naturally — a
//  user who pulled to refresh in the morning will get fresh "checked in
//  today?" guidance after lunch without leaving the tab.
//

import Foundation
import FirebaseFirestore
import Combine

// MARK: - View Model

@MainActor
final class TogetherViewModel: ObservableObject {

    // MARK: - Published State

    @Published private(set) var goals: [TogetherGoal] = []
    @Published private(set) var challenges: [CoupleChallenge] = []
    @Published private(set) var dreams: [Dream] = []
    @Published private(set) var insights: [TogetherInsight] = []
    @Published private(set) var stats: TogetherStats = .empty
    @Published private(set) var isListening: Bool = false
    @Published var errorMessage: String?

    /// Mirrors the tick clock used in TimeTreeViewModel so countdowns and
    /// "checked in today?" detection stay accurate while the tab is open.
    @Published private(set) var now: Date = Date()

    /// One-shot pulse the view watches to fire the streak-celebration overlay.
    @Published var pendingStreakCelebration: CoupleChallenge?

    // MARK: - Dependencies

    private let session: UserSession
    private let goalsService: TogetherGoalsService
    private let challengesService: CoupleChallengeService
    private let dreamsService: DreamBoardService
    private let notificationScheduler: TogetherNotificationScheduling

    nonisolated(unsafe) private var goalsListener: ListenerRegistration?
    nonisolated(unsafe) private var challengesListener: ListenerRegistration?
    nonisolated(unsafe) private var dreamsListener: ListenerRegistration?
    private var tickTimer: Timer?

    /// Highest streak we've seen for each challenge — used to debounce the
    /// celebration overlay so it only fires when current actually exceeds
    /// the previous high water mark on this device.
    private var highestSeenStreak: [String: Int] = [:]

    // MARK: - Init

    init(
        session: UserSession,
        goalsService: TogetherGoalsService? = nil,
        challengesService: CoupleChallengeService? = nil,
        dreamsService: DreamBoardService? = nil,
        notificationScheduler: TogetherNotificationScheduling? = nil
    ) {
        self.session = session
        self.goalsService          = goalsService          ?? FirestoreTogetherGoalsService()
        self.challengesService     = challengesService     ?? FirestoreCoupleChallengeService()
        self.dreamsService         = dreamsService         ?? FirestoreDreamBoardService()
        self.notificationScheduler = notificationScheduler ?? TogetherNotificationScheduler()
    }

    deinit {
        goalsListener?.remove()
        challengesListener?.remove()
        dreamsListener?.remove()
        tickTimer?.invalidate()
    }

    // MARK: - Lifecycle

    func startListening() {
        guard goalsListener == nil, session.isPaired else { return }
        isListening = true

        goalsListener = goalsService.observe(
            coupleId: session.coupleId,
            onUpdate: { [weak self] items in
                Task { @MainActor in
                    self?.goals = items
                    self?.recompute()
                }
            },
            onError: { [weak self] error in
                Task { @MainActor in self?.errorMessage = error.localizedDescription }
            }
        )

        challengesListener = challengesService.observe(
            coupleId: session.coupleId,
            onUpdate: { [weak self] items in
                Task { @MainActor in
                    self?.handleChallengeUpdate(items)
                }
            },
            onError: { [weak self] error in
                Task { @MainActor in self?.errorMessage = error.localizedDescription }
            }
        )

        dreamsListener = dreamsService.observe(
            coupleId: session.coupleId,
            onUpdate: { [weak self] items in
                Task { @MainActor in
                    self?.dreams = items
                    self?.recompute()
                }
            },
            onError: { [weak self] error in
                Task { @MainActor in self?.errorMessage = error.localizedDescription }
            }
        )

        startTicking()
    }

    func stopListening() {
        goalsListener?.remove();      goalsListener = nil
        challengesListener?.remove(); challengesListener = nil
        dreamsListener?.remove();     dreamsListener = nil
        tickTimer?.invalidate();      tickTimer = nil
        isListening = false
    }

    func refresh() {
        now = Date()
        recompute()
    }

    // MARK: - Goals

    /// Returns true if the goal could be created (or false when blocked by the
    /// free-tier limit). The premium check lives in the view; the viewmodel
    /// just enforces it as a guard so a stale `.hasAccess()` result can't
    /// sneak past us.
    @discardableResult
    func createGoal(
        title: String,
        category: GoalCategory,
        colorway: TogetherColorway,
        trackingMode: GoalTrackingMode,
        target: Double,
        currencyCode: String,
        dueDate: Date?,
        note: String?,
        canExceedFreeLimit: Bool
    ) async -> Bool {
        guard session.isPaired else { return false }

        // Free users: 2 active goals max.
        let activeCount = goals.filter { !$0.isComplete }.count
        if !canExceedFreeLimit && activeCount >= 2 { return false }

        let goal = TogetherGoal(
            id: UUID().uuidString,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category,
            colorway: colorway,
            trackingMode: trackingMode,
            target: target,
            currencyCode: currencyCode,
            contribution: .empty,
            dueDate: dueDate,
            note: note?.nilIfEmpty,
            createdBy: session.userId,
            createdAt: Date(),
            updatedAt: Date(),
            completedAt: nil
        )

        do {
            try await goalsService.create(coupleId: session.coupleId, goal: goal)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func updateGoal(_ goal: TogetherGoal) async {
        do {
            try await goalsService.update(coupleId: session.coupleId, goal: goal)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func contributeToGoal(_ goal: TogetherGoal, delta: Double) async {
        do {
            try await goalsService.recordContribution(
                coupleId: session.coupleId,
                goalId: goal.id,
                userId: session.userId,
                delta: delta
            )

            // Auto-complete after the contribution lands.
            if goal.contribution.total + delta >= goal.target {
                try await goalsService.markComplete(
                    coupleId: session.coupleId,
                    goalId: goal.id
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteGoal(_ goal: TogetherGoal) async {
        do {
            try await goalsService.delete(coupleId: session.coupleId, id: goal.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Challenges

    @discardableResult
    func createChallenge(
        title: String,
        category: ChallengeCategory,
        colorway: TogetherColorway,
        cadence: ChallengeCadence,
        targetCount: Int,
        startDate: Date,
        canExceedFreeLimit: Bool
    ) async -> Bool {
        guard session.isPaired else { return false }

        let activeCount = challenges.filter { !$0.isComplete }.count
        if !canExceedFreeLimit && activeCount >= 1 { return false }

        let challenge = CoupleChallenge(
            id: UUID().uuidString,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category,
            colorway: colorway,
            cadence: cadence,
            targetCount: targetCount,
            contribution: .empty,
            checkInLog: [],
            streak: .zero,
            startDate: startDate,
            createdBy: session.userId,
            createdAt: Date(),
            updatedAt: Date(),
            completedAt: nil
        )

        do {
            try await challengesService.create(coupleId: session.coupleId, challenge: challenge)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func checkInToChallenge(_ challenge: CoupleChallenge) async {
        do {
            _ = try await challengesService.recordCheckIn(
                coupleId: session.coupleId,
                challengeId: challenge.id,
                userId: session.userId,
                date: Date()
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteChallenge(_ challenge: CoupleChallenge) async {
        do {
            try await challengesService.delete(coupleId: session.coupleId, id: challenge.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Dreams

    @discardableResult
    func createDream(
        title: String,
        category: DreamCategory,
        colorway: TogetherColorway,
        horizon: DreamHorizon,
        note: String?,
        inspiration: String?,
        firstStep: String?
    ) async -> Bool {
        guard session.isPaired else { return false }

        let dream = Dream(
            id: UUID().uuidString,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category,
            colorway: colorway,
            horizon: horizon,
            photoURL: nil,
            note: note?.nilIfEmpty,
            inspiration: inspiration?.nilIfEmpty,
            firstStep: firstStep?.nilIfEmpty,
            createdBy: session.userId,
            createdAt: Date(),
            updatedAt: Date()
        )

        do {
            try await dreamsService.create(coupleId: session.coupleId, dream: dream)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func updateDream(_ dream: Dream) async {
        do {
            try await dreamsService.update(coupleId: session.coupleId, dream: dream)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteDream(_ dream: Dream) async {
        do {
            try await dreamsService.delete(coupleId: session.coupleId, id: dream.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Streak Celebration

    func acknowledgeStreakCelebration() {
        if let challenge = pendingStreakCelebration {
            highestSeenStreak[challenge.id] = challenge.streak.current
        }
        pendingStreakCelebration = nil
    }

    // MARK: - Derived

    var activeGoals: [TogetherGoal] {
        goals.filter { !$0.isComplete }.sorted { $0.progress > $1.progress }
    }

    var completedGoals: [TogetherGoal] {
        goals.filter { $0.isComplete }
    }

    var activeChallenges: [CoupleChallenge] {
        challenges.filter { !$0.isComplete }
    }

    var headlineInsight: TogetherInsight? {
        insights.first
    }

    /// True only when the user has a real partner. Surface in the view via
    /// the not-paired empty state.
    var isPaired: Bool { session.isPaired }

    var sessionUserId: String { session.userId }

    // MARK: - Private

    private func handleChallengeUpdate(_ items: [CoupleChallenge]) {
        // Detect freshly-crossed 7-day streak boundaries to fire the
        // celebration overlay. We only celebrate transitions UP, and only
        // for streaks that are an exact multiple of 7 (one a week is
        // plenty of celebration).
        for challenge in items {
            let currentStreak = challenge.streak.current
            let previous = highestSeenStreak[challenge.id] ?? 0
            highestSeenStreak[challenge.id] = max(previous, currentStreak)

            let didCrossNew7Day =
                currentStreak > previous &&
                currentStreak >= 7 &&
                currentStreak % 7 == 0

            if didCrossNew7Day && pendingStreakCelebration == nil {
                pendingStreakCelebration = challenge
            }
        }

        challenges = items
        recompute()
    }

    private func recompute() {
        stats = TogetherCoachEngine.computeStats(
            goals: goals,
            challenges: challenges,
            dreams: dreams,
            now: now
        )
        insights = TogetherCoachEngine.generate(
            goals: goals,
            challenges: challenges,
            dreams: dreams,
            userId: session.userId,
            now: now
        )

        // Reconcile local notifications off the latest snapshot. Cheap to
        // re-run because the scheduler wipes its own old requests.
        let snapshotGoals = goals
        let snapshotChallenges = challenges
        let snapshotDreams = dreams
        Task {
            await notificationScheduler.reconcile(
                goals: snapshotGoals,
                challenges: snapshotChallenges,
                dreams: snapshotDreams
            )
        }
    }

    private func startTicking() {
        tickTimer?.invalidate()
        // 5-minute cadence is enough to catch midnight rollovers and the
        // "still hasn't checked in today" signal without burning battery.
        tickTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.now = Date()
                self?.recompute()
            }
        }
    }
}

// MARK: - String helper

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
