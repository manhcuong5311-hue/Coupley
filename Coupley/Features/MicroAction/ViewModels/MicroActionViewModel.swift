//
//  MicroActionViewModel.swift
//  Coupley
//

import Foundation
import Combine

// MARK: - View Model

@MainActor
final class MicroActionViewModel: ObservableObject {

    // MARK: - Published

    /// Today's actions only (what the card renders).
    @Published private(set) var todaysActions: [MicroAction] = []
    @Published private(set) var isGenerating: Bool = false

    // MARK: - Dependencies

    private let session: UserSession
    private let generator: ActionGeneratorService
    private let store: MicroActionStore
    private let scheduler: MicroActionReminderScheduling
    private let profileService: ProfileService

    /// Full local history — kept in memory so the generator can dedupe. Not
    /// exposed to the view.
    private var history: [MicroAction] = []
    private var cancellables: Set<AnyCancellable> = []
    private var lastContextKey: String?

    // MARK: - Init

    init(
        session: UserSession,
        generator: ActionGeneratorService? = nil,
        store: MicroActionStore? = nil,
        scheduler: MicroActionReminderScheduling? = nil,
        profileService: ProfileService? = nil
    ) {
        self.session = session
        self.generator = generator ?? RuleBasedActionGenerator()
        self.store = store ?? UserDefaultsMicroActionStore()
        self.scheduler = scheduler ?? MicroActionReminderScheduler()
        self.profileService = profileService ?? LocalProfileService()

        loadFromDisk()
    }

    // MARK: - Wiring (MoodListener)

    /// Subscribe to a CoupleViewModel so we regenerate whenever the partner
    /// logs a new mood, goes offline, etc. Kept as a weak binding so the
    /// caller can swap in a different source later (e.g. an AI suggestion
    /// stream) without rewriting the VM.
    func bind(to couple: CoupleViewModel) {
        cancellables.removeAll()

        couple.$partnerMoodState
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak couple] _ in
                guard let self, let couple else { return }
                self.refresh(from: couple, reason: .partnerMoodChanged)
            }
            .store(in: &cancellables)

        couple.$partnerIsOnline
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak couple] _ in
                guard let self, let couple else { return }
                self.refresh(from: couple, reason: .partnerPresenceChanged)
            }
            .store(in: &cancellables)
    }

    // MARK: - Reasons

    enum GenerationReason {
        case appOpen
        case partnerMoodChanged
        case partnerPresenceChanged
        case manualRefresh
    }

    // MARK: - Refresh / generate

    func refresh(from couple: CoupleViewModel, reason: GenerationReason) {
        let context = buildContext(from: couple)

        // Skip regeneration if we already have today's actions for this
        // exact context key — prevents churn on every presence flicker.
        if reason != .manualRefresh,
           context.key == lastContextKey,
           !todaysActions.isEmpty {
            return
        }

        Task { await generate(context: context) }
    }

    private func generate(context: MicroActionContext) async {
        isGenerating = true
        defer { isGenerating = false }

        var enriched = context
        enriched.recentActionTexts = recentActionTexts(days: 7)

        let fresh = generator.generate(context: enriched)
        guard !fresh.isEmpty else { return }

        // Replace today's pending actions. Keep anything the user has
        // already acted on today (done/skipped) so completion state
        // doesn't disappear when partner mood changes.
        let keptFromToday = history.filter {
            $0.isToday && $0.status != .pending
        }
        let others = history.filter { !$0.isToday }

        history = others + keptFromToday + fresh
        lastContextKey = context.key
        persist()
    }

    // MARK: - User actions

    func markDone(_ action: MicroAction) {
        mutate(action.id) { item in
            item.status = .done
            item.doneAt = Date()
        }
        Task { await scheduler.cancelReminder(for: action.id) }
    }

    func skip(_ action: MicroAction) {
        mutate(action.id) { item in item.status = .skipped }
        Task { await scheduler.cancelReminder(for: action.id) }
    }

    /// "Remind me later" — snooze by N minutes and schedule a gentle local
    /// notification.
    func snooze(_ action: MicroAction, minutes: Int = 120) {
        let until = Date().addingTimeInterval(Double(minutes) * 60)
        mutate(action.id) { item in
            item.status = .snoozed
            item.snoozedUntil = until
        }
        Task { await scheduler.scheduleReminder(for: action, at: until) }
    }

    // MARK: - Context assembly

    private func buildContext(from couple: CoupleViewModel) -> MicroActionContext {
        let partnerMood: MicroActionContext.PartnerMood? = {
            guard let entry = couple.partnerMood else { return nil }
            return MicroActionContext.PartnerMood(
                mood: entry.moodValue,
                energy: entry.energyValue,
                loggedAt: entry.timestamp,
                note: entry.note
            )
        }()

        let recent = couple.weeklyHistory.map { $0.moodValue }

        // Best-effort: use cached profile. We don't block generation on it.
        let profile: PartnerProfile? = nil

        return MicroActionContext(
            partnerMood: partnerMood,
            recentMoods: recent,
            partnerIsActive: couple.partnerIsOnline,
            profile: profile
        )
    }

    // MARK: - Persistence plumbing

    private func loadFromDisk() {
        history = store.load(userId: session.userId)
        publishToday()
    }

    private func persist() {
        store.save(history, userId: session.userId)
        publishToday()
    }

    private func publishToday() {
        todaysActions = history
            .filter { $0.isToday }
            .sorted { lhs, rhs in
                if lhs.status != rhs.status {
                    return lhs.status.sortRank < rhs.status.sortRank
                }
                return lhs.createdAt < rhs.createdAt
            }
    }

    private func mutate(_ id: String, _ block: (inout MicroAction) -> Void) {
        guard let idx = history.firstIndex(where: { $0.id == id }) else { return }
        var copy = history[idx]
        block(&copy)
        history[idx] = copy
        persist()
    }

    private func recentActionTexts(days: Int) -> [String] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        return history.filter { $0.createdAt >= cutoff }.map(\.text)
    }
}

// MARK: - Status sort rank

private extension MicroActionStatus {
    /// Order pending first, then snoozed, then done, then skipped.
    var sortRank: Int {
        switch self {
        case .pending:  return 0
        case .snoozed:  return 1
        case .done:     return 2
        case .skipped:  return 3
        }
    }
}
