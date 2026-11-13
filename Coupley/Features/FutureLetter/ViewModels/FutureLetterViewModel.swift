//
//  FutureLetterViewModel.swift
//  Coupley
//
//  Owned by ContentView (the Home tab badge counts ready letters) and handed
//  to the dashboard. Follows the DailyPhotoViewModel lifecycle: built with
//  whatever session ContentView has, `rebind(session:)` on change, `start()`
//  on appear and on foreground, both idempotent.
//

import Foundation
import SwiftUI
import Combine
import FirebaseFirestore

// MARK: - Draft

/// Compose state lives apart from the view model. The view model is observed
/// by ContentView and all of Home, so a @Published draft there would re-render
/// Home on every keystroke.
@MainActor
final class FutureLetterDraftStore: ObservableObject {
    @Published var text: String
    @Published var opensAt: Date
    @Published var tellInChat: Bool

    /// The default this store last assigned. While `opensAt` still equals
    /// it, the user has not picked a moment, so it may follow the clock.
    private var assignedDefault: Date

    /// A moment a caller preset (Journey's "Letter for that day"), not one
    /// the user picked. It belongs to that entry point only.
    private var presetMoment: Date?

    init() {
        let initial = FutureLetterSchedule.defaultOpensAt(now: Date())
        text = ""
        opensAt = initial
        tellInChat = true
        assignedDefault = initial
    }

    func reset() {
        text = ""
        tellInChat = true
        presetMoment = nil
        assignDefault(now: Date())
    }

    func applyPreset(_ moment: Date) {
        opensAt = moment
        presetMoment = moment
    }

    /// Compose opened from an entry point with no moment of its own. A
    /// preset left over from closing "Letter for that day" without writing
    /// anything goes back to the default, so a plain "Write a letter" never
    /// opens weeks later than it says by default. Once words are written,
    /// the draft keeps its moment.
    func dropUnusedPreset(now: Date = Date()) {
        guard let preset = presetMoment else { return }
        presetMoment = nil
        guard opensAt == preset,
              text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        assignDefault(now: now)
    }

    /// Called when compose appears. An untouched default is recomputed, so
    /// "tomorrow at 9:00 AM" set last night does not quietly become "today";
    /// a picked moment is kept unless it is now too soon.
    func refreshIfStale(now: Date = Date()) {
        if opensAt == assignedDefault || opensAt < FutureLetterSchedule.earliest(now: now) {
            assignDefault(now: now)
        }
    }

    private func assignDefault(now: Date) {
        let value = FutureLetterSchedule.defaultOpensAt(now: now)
        assignedDefault = value
        opensAt = value
    }
}

// MARK: - View model

@MainActor
final class FutureLetterViewModel: ObservableObject {

    /// What the letters sheet shows. ContentView presents it with
    /// `.sheet(item:)`, so any tab can open it, and it survives the hero card
    /// leaving the hero slot the moment `openedAt` is stamped.
    enum Route: Identifiable, Equatable {
        case hub
        case compose
        case read(FutureLetter)

        var id: String {
            switch self {
            case .hub: return "hub"
            case .compose: return "compose"
            case .read(let letter): return "read-\(letter.id)"
            }
        }
    }

    /// Posted to the chat as the sender's own message. Stored in ENGLISH
    /// (`ChatSystemLine.futureLetterNote`): the server pushes a chat message's
    /// text to the partner as the notification body, notifications stay
    /// English, and the partner's phone may run another language. Chat
    /// bubbles redraw it in the reader's language; the compose view shows
    /// `ChatSystemLine.futureLetterNoteDisplay`.
    static var chatNote: String { ChatSystemLine.futureLetterNote }

    /// Sorted by `opensAt`, earliest first.
    @Published private(set) var letters: [FutureLetter] = []
    @Published private(set) var pendingIds: Set<String> = []
    @Published private(set) var hasLoaded = false
    @Published private(set) var listenError: String?
    /// The clock every phase is computed against. It moves at boundaries (a
    /// letter opening, a receipt expiring), on foreground and on snapshots —
    /// never every second, so Home does not re-render on a timer.
    @Published private(set) var now = Date()
    @Published private(set) var isSending = false
    @Published private(set) var sendError: String?
    @Published var route: Route?

    let draft = FutureLetterDraftStore()

    private var session: UserSession
    private let service: FutureLetterServicing
    private let scheduler: FutureLetterNotificationScheduling
    private let chatService: CoupleChatServicing
    private var listener: ListenerRegistration?
    private var flipTask: Task<Void, Never>?
    private var notificationTask: Task<Void, Never>?
    /// Reminders are only reconciled against server data: a cache-only
    /// snapshot at launch could drop reminders for letters it has not seen.
    private var hasServerSnapshot = false
    /// Letters seen sealed for me at the last refresh, to feel the flip.
    private var sealedForMeIds: Set<String> = []
    /// Quick re-listens after a failed listen (e.g. the joiner's first listen
    /// racing the pairing commit). Reset by a healthy snapshot.
    private var listenRetries = 0
    private var listenRetryTask: Task<Void, Never>?
    /// Clears the draft once a sealed letter's sheet has slid away. Cancelled
    /// by `compose(...)`, so a quick reopen can't wipe freshly seeded words.
    private var draftResetTask: Task<Void, Never>?

    init(
        session: UserSession,
        service: FutureLetterServicing? = nil,
        scheduler: FutureLetterNotificationScheduling? = nil,
        chatService: CoupleChatServicing? = nil
    ) {
        self.session = session
        self.service = service ?? FirestoreFutureLetterService()
        self.scheduler = scheduler ?? FutureLetterNotificationScheduler()
        self.chatService = chatService ?? FirestoreCoupleChatService()
    }

    deinit {
        listener?.remove()
        flipTask?.cancel()
        listenRetryTask?.cancel()
    }

    // MARK: - Derived

    /// `UserSession.demo` reports `isPaired` with a placeholder couple id;
    /// listening on it would be denied by the rules.
    var isAvailable: Bool {
        session.isPaired && session.coupleId != UserSession.demo.coupleId
    }

    func phase(of letter: FutureLetter) -> FutureLetterPhase {
        letter.phase(viewer: session.userId, now: now)
    }

    func isPending(_ letter: FutureLetter) -> Bool { pendingIds.contains(letter.id) }

    func letter(id: String) -> FutureLetter? { letters.first { $0.id == id } }

    var readyForMe: [FutureLetter] { letters.filter { phase(of: $0) == .readyForMe } }
    /// The earliest letter that has reached its moment and is still unopened.
    var heroLetter: FutureLetter? { readyForMe.first }
    var readyForMeCount: Int { readyForMe.count }

    /// Home's pinned row when a ready letter is the hero.
    var pinnedLetters: [FutureLetter] { pinnedLetters(includingReady: false) }

    /// Home's pinned row shows `.first`, with "+N" for the rest. A letter that
    /// is ready for me is normally not pinned, because it is the hero; when
    /// something else holds the hero (both partners here right now), it is
    /// pinned first instead, so it is never out of sight.
    ///
    /// Rank: ready for me (when included), sealed for me (soonest first), then
    /// "opened your letter" receipts under 24 h (newest first), then sealed by
    /// me (soonest first), then mine that are ready but unopened.
    func pinnedLetters(includingReady: Bool) -> [FutureLetter] {
        func rank(_ letter: FutureLetter) -> Int? {
            switch phase(of: letter) {
            case .readyForMe:
                return includingReady ? -1 : nil
            case .sealedForMe:
                return 0
            case .openedByPartner:
                guard let openedAt = letter.openedAt,
                      now.timeIntervalSince(openedAt) < FutureLetterSchedule.receiptWindow else { return nil }
                return 1
            case .sealedByMe:
                return 2
            case .waitingForPartner:
                return 3
            case .openedByMe:
                return nil
            }
        }
        return letters
            .compactMap { letter in rank(letter).map { (letter, $0) } }
            .sorted { a, b in
                if a.1 != b.1 { return a.1 < b.1 }
                if a.1 == 1 { return (a.0.openedAt ?? .distantPast) > (b.0.openedAt ?? .distantPast) }
                return a.0.opensAt < b.0.opensAt
            }
            .map(\.0)
    }

    /// Ready, then sealed (both soonest first), then opened (latest first).
    var lettersForMe: [FutureLetter] {
        ordered(letters.filter { $0.toUserId == session.userId },
                open: [.readyForMe, .sealedForMe],
                done: .openedByMe)
    }

    /// Waiting for my partner, then sealed (both soonest first), then opened.
    var lettersFromMe: [FutureLetter] {
        ordered(letters.filter { $0.fromUserId == session.userId },
                open: [.waitingForPartner, .sealedByMe],
                done: .openedByPartner)
    }

    private func ordered(_ list: [FutureLetter], open: [FutureLetterPhase], done: FutureLetterPhase) -> [FutureLetter] {
        var result: [FutureLetter] = []
        for group in open {
            result += list.filter { phase(of: $0) == group }.sorted { $0.opensAt < $1.opensAt }
        }
        result += list
            .filter { phase(of: $0) == done }
            .sorted { ($0.openedAt ?? .distantPast) > ($1.openedAt ?? .distantPast) }
        return result
    }

    // MARK: - Lifecycle

    func rebind(session newSession: UserSession) {
        guard newSession.coupleId != session.coupleId || newSession.userId != session.userId else { return }
        let hadRealSession = isAvailable
        stop()
        session = newSession
        letters = []
        pendingIds = []
        hasLoaded = false
        hasServerSnapshot = false
        listenError = nil
        listenRetries = 0
        route = nil
        sealedForMeIds = []
        draft.reset()
        // Reminders for the previous couple must not fire for this one.
        if hadRealSession { enqueueNotificationWork { await $0.cancelAll() } }
        start()
    }

    /// Idempotent. Called on appear, on foreground and after `rebind`.
    func start() {
        guard isAvailable else {
            hasLoaded = true
            return
        }
        // Firestore ends a listener for good once it reports an error, so a
        // failed one is replaced rather than kept.
        if listenError != nil {
            listener?.remove()
            listener = nil
        }
        if listener == nil {
            listener = service.observeLetters(
                coupleId: session.coupleId,
                onUpdate: { [weak self] letters, pending, fromCache in
                    Task { @MainActor in self?.handle(letters, pending: pending, fromCache: fromCache) }
                },
                onError: { [weak self] error in
                    Task { @MainActor in
                        self?.listenError = error.localizedDescription
                        self?.hasLoaded = true
                        self?.retryListenSoon()
                    }
                }
            )
        }
        refreshClock()
    }

    /// A couple of quick re-listens after a failure, before falling back to
    /// the next foreground or Try again.
    private func retryListenSoon() {
        guard listenRetries < 3, listenRetryTask == nil else { return }
        listenRetries += 1
        let delay = Double(listenRetries * 3)
        listenRetryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.listenRetryTask = nil
            if self?.listenError != nil { self?.start() }
        }
    }

    func stop() {
        listener?.remove()
        listener = nil
        flipTask?.cancel()
        flipTask = nil
        listenRetryTask?.cancel()
        listenRetryTask = nil
    }

    /// Moves `now`, plays the unsealing haptic, re-arms the one-shot timer and
    /// reconciles reminders. Runs on foreground, on significant time changes
    /// and on every snapshot.
    func refreshClock() {
        now = Date()
        let readyIds = Set(readyForMe.map(\.id))
        if !readyIds.isDisjoint(with: sealedForMeIds),
           UIApplication.shared.applicationState == .active {
            // Seen sealed a moment ago, ready now: the letter just opened.
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        sealedForMeIds = Set(letters.filter { phase(of: $0) == .sealedForMe }.map(\.id))
        scheduleFlip()
        if hasServerSnapshot { reconcileNotifications() }
    }

    private func handle(_ incoming: [FutureLetter], pending: Set<String>, fromCache: Bool) {
        let me = session.userId
        letters = incoming
            .filter { $0.fromUserId == me || $0.toUserId == me }
            .sorted { $0.opensAt < $1.opensAt }
        pendingIds = pending
        hasLoaded = true
        listenError = nil
        listenRetries = 0
        if !fromCache { hasServerSnapshot = true }
        refreshClock()
    }

    /// One timer, aimed at the next boundary: the soonest `opensAt` of an
    /// unopened letter, or the end of a 24 h receipt.
    private func scheduleFlip() {
        flipTask?.cancel()
        flipTask = nil
        let current = Date()
        let opens = letters.filter { $0.openedAt == nil && $0.opensAt > current }.map(\.opensAt)
        let receipts = letters
            .compactMap { $0.openedAt?.addingTimeInterval(FutureLetterSchedule.receiptWindow) }
            .filter { $0 > current }
        guard let next = (opens + receipts).min() else { return }
        let delay = next.timeIntervalSince(current) + 0.25
        flipTask = Task { [weak self] in
            // ContinuousClock: after a suspension it fires as soon as it can.
            // An explicit tolerance: the default leeway is 10% of the delay,
            // up to a minute late for a letter opening an hour from now.
            try? await Task.sleep(for: .seconds(delay), tolerance: .milliseconds(50))
            guard !Task.isCancelled else { return }
            self?.refreshClock()
        }
    }

    private func reconcileNotifications() {
        let mine = letters.filter { $0.toUserId == session.userId }
        enqueueNotificationWork { await $0.reconcile(mine) }
    }

    /// Serialises scheduler work so a cancel and a reconcile never interleave.
    private func enqueueNotificationWork(_ work: @escaping (FutureLetterNotificationScheduling) async -> Void) {
        let previous = notificationTask
        let scheduler = self.scheduler
        notificationTask = Task {
            await previous?.value
            await work(scheduler)
        }
    }

    // MARK: - Navigation

    func openHub() { route = .hub }

    /// Compose as the sheet's root, from anywhere: Home's masthead, a chat
    /// message turned into a letter, an anniversary on Journey. `seed` is
    /// appended to any unsent draft, never replacing it; `opensAt` is used
    /// only when it is a valid moment (otherwise the draft's own stays).
    func compose(seed: String? = nil, opensAt: Date? = nil) {
        draftResetTask?.cancel()
        draftResetTask = nil
        // Before seeding: whether the draft was still empty decides it.
        if opensAt == nil { draft.dropUnusedPreset() }
        if let seed = seed?.trimmingCharacters(in: .whitespacesAndNewlines), !seed.isEmpty {
            let current = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
            draft.text = current.isEmpty ? seed : current + "\n\n" + seed
        }
        if let opensAt {
            let moment = FutureLetterSchedule.normalized(opensAt)
            if FutureLetterSchedule.isValid(moment, now: Date()) { draft.applyPreset(moment) }
        }
        route = .compose
    }

    func show(_ letter: FutureLetter) { route = .read(letter) }

    // MARK: - Seal

    /// Returns true once the letter is sealed (acknowledged, or queued
    /// offline). On failure the draft is kept and `sendError` is set.
    func seal() async -> Bool {
        guard isAvailable, !isSending else { return false }
        let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let opensAt = FutureLetterSchedule.normalized(draft.opensAt)
        guard !text.isEmpty,
              text.count <= FutureLetterSchedule.maxCharacters,
              FutureLetterSchedule.isValid(opensAt, now: Date()) else { return false }

        isSending = true
        sendError = nil
        defer { isSending = false }

        do {
            try await service.seal(text: text,
                                   opensAt: opensAt,
                                   coupleId: session.coupleId,
                                   fromUserId: session.userId,
                                   toUserId: session.partnerId)
        } catch {
            sendError = error.localizedDescription
            return false
        }

        // Only after the batch is acknowledged or queued: a chat note about a
        // letter the server refused would be a lie.
        if draft.tellInChat {
            let chat = chatService
            let current = session
            Task {
                try? await chat.sendText(Self.chatNote, coupleId: current.coupleId, senderId: current.userId)
            }
        }
        route = nil                       // Home now shows the pin
        // Cleared once the sheet has slid away, not under it.
        let sealedDraft = draft
        draftResetTask?.cancel()
        draftResetTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            sealedDraft.reset()
        }
        AdsManager.shared.recordAction()  // a saved thing, like a memory; opening never counts
        return true
    }

    func dismissSendError() { sendError = nil }

    // MARK: - Read

    func fetchBody(for letter: FutureLetter) async -> Result<FutureLetterBody, FutureLetterOpenError> {
        let firstOpen = letter.toUserId == session.userId && letter.openedAt == nil
        do {
            // The first open asks the server, never the cache: the answer is
            // the server clock's decision.
            let body = try await service.fetchBody(coupleId: session.coupleId,
                                                   letterId: letter.id,
                                                   source: firstOpen ? .server : .default)
            return .success(body)
        } catch {
            // Gone from the listener: unsent or purged.
            if hasLoaded && self.letter(id: letter.id) == nil { return .failure(.unavailable) }
            let ns = error as NSError
            // Not a Firestore error: the document decoded to no body.
            guard ns.domain == FirestoreErrorDomain else { return .failure(.unavailable) }
            switch ns.code {
            case FirestoreErrorCode.permissionDenied.rawValue:
                return .failure(firstOpen ? .notYet : .other)
            case FirestoreErrorCode.unavailable.rawValue, FirestoreErrorCode.deadlineExceeded.rawValue:
                return .failure(.offline)
            case FirestoreErrorCode.notFound.rawValue:
                return .failure(.unavailable)
            default:
                return .failure(.other)
            }
        }
    }

    /// The recipient's one-time receipt. The reader calls it once the words
    /// are on screen, never on a fetch the user closed before seeing.
    func markOpened(_ letter: FutureLetter) {
        guard letter.toUserId == session.userId, letter.openedAt == nil else { return }
        service.markOpened(coupleId: session.coupleId, letterId: letter.id)
        scheduler.clearDelivered(letterId: letter.id)
    }

    // MARK: - Unsend

    func unsend(_ letter: FutureLetter) async -> Bool {
        guard isAvailable, letter.fromUserId == session.userId else { return false }
        do {
            try await service.unsend(coupleId: session.coupleId, letterId: letter.id)
            return true
        } catch {
            return false
        }
    }
}
