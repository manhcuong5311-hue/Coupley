//
//  ChatViewModel.swift
//  Coupley
//
//  @MainActor store for ChatView. Owns:
//    - messages feed listener
//    - active quiz listener (for card state)
//    - draft text + sending state
//    - answer submission flow
//    - opportunistic quiz suggestion
//

import Foundation
import FirebaseFirestore
import Combine

@MainActor
final class ChatViewModel: ObservableObject {

    // MARK: - Published state

    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var quizzes:  [ChatQuiz]    = []
    @Published private(set) var pendingMessageIds: Set<String> = []
    @Published var draftText: String = ""
    @Published private(set) var isSending = false
    @Published private(set) var errorMessage: String?

    // Pagination
    @Published private(set) var isLoadingOlder = false
    @Published private(set) var hasMoreOlder: Bool = true

    // Quiz answer flow (view presents a sheet when this is non-nil)
    @Published var activeQuizForAnswering: ChatQuiz?

    // Internal store: message id → message. The listener covers the newest
    // `liveWindowSize` messages; older pages are merged in here too.
    private var messagesById: [String: ChatMessage] = [:]
    // The set of ids currently inside the listener's window, so we know
    // which entries to refresh vs preserve when the listener fires.
    private var liveWindowIds: Set<String> = []

    private let liveWindowSize = 50
    private let pageSize       = 50

    // MARK: - Dependencies

    private let session: UserSession
    private let chatService:   CoupleChatServicing
    private let orchestrator:  QuizOrchestrating
    private let insightGen:    InsightGenerating
    private let aggregator:    CoupleInsightAggregating

    private var messageListener: ListenerRegistration?
    private var quizListener:    ListenerRegistration?

    // MARK: - Init

    init(session: UserSession,
         chatService:   CoupleChatServicing? = nil,
         orchestrator:  QuizOrchestrating? = nil,
         insightGen:    InsightGenerating? = nil,
         aggregator:    CoupleInsightAggregating? = nil) {
        self.session = session
        self.chatService  = chatService  ?? FirestoreCoupleChatService()
        self.orchestrator = orchestrator ?? DefaultQuizOrchestrator()
        self.insightGen   = insightGen   ?? DefaultInsightGenerator()
        self.aggregator   = aggregator   ?? FirestoreCoupleInsightAggregator()
    }

    deinit {
        messageListener?.remove()
        quizListener?.remove()
    }

    // MARK: - Lifecycle

    func start() {
        guard session.isPaired else { return }
        listen()
        Task { await maybeSuggestQuiz() }
    }

    func stop() {
        messageListener?.remove(); messageListener = nil
        quizListener?.remove();    quizListener    = nil
    }

    private func listen() {
        messageListener = chatService.listenToMessages(
            coupleId: session.coupleId,
            limit: liveWindowSize,
            onUpdate: { [weak self] newMessages, pendingIds in
                Task { @MainActor in
                    guard let self else { return }
                    self.mergeLiveWindow(newMessages, pendingIds: pendingIds)
                    self.markUnreadAsRead()
                }
            },
            onError: { [weak self] err in
                Task { @MainActor in self?.errorMessage = err.localizedDescription }
            }
        )

        quizListener = chatService.listenToQuizzes(
            coupleId: session.coupleId,
            onUpdate: { [weak self] quizzes in
                Task { @MainActor in self?.quizzes = quizzes }
            },
            onError: { [weak self] err in
                Task { @MainActor in self?.errorMessage = err.localizedDescription }
            }
        )
    }

    // MARK: - Store merge + pagination

    /// Incorporate the newest-N window emitted by the listener. Any ids
    /// that used to be in the window but aren't anymore are preserved
    /// (they may have fallen out because older messages are still loaded
    /// above them — they're historical and shouldn't be removed).
    private func mergeLiveWindow(_ window: [ChatMessage], pendingIds: Set<String>) {
        // Messages that fall out of the live window (pushed out by a newer
        // arrival) are intentionally kept in the dict so history stays
        // contiguous under infinite scroll.
        for msg in window {
            messagesById[msg.id] = msg
        }
        liveWindowIds = Set(window.map(\.id))
        pendingMessageIds = pendingIds
        rebuildMessageList()
    }

    private func rebuildMessageList() {
        messages = messagesById.values.sorted { $0.createdAt < $1.createdAt }
    }

    func loadOlder() {
        guard !isLoadingOlder, hasMoreOlder else { return }
        guard let oldest = messages.first else { return }
        isLoadingOlder = true
        Task {
            defer { Task { @MainActor in self.isLoadingOlder = false } }
            do {
                let older = try await chatService.loadOlderMessages(
                    coupleId: session.coupleId,
                    before: oldest.createdAt,
                    limit: pageSize
                )
                await MainActor.run {
                    if older.isEmpty {
                        self.hasMoreOlder = false
                        return
                    }
                    for msg in older {
                        self.messagesById[msg.id] = msg
                    }
                    if older.count < self.pageSize {
                        self.hasMoreOlder = false
                    }
                    self.rebuildMessageList()
                }
            } catch {
                await MainActor.run { self.errorMessage = error.localizedDescription }
            }
        }
    }

    // MARK: - Sending text

    func sendDraft() {
        let body = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !isSending else { return }
        draftText = ""
        isSending = true

        Task {
            defer { Task { @MainActor in self.isSending = false } }
            do {
                try await chatService.sendText(body,
                                               coupleId: session.coupleId,
                                               senderId: session.userId)
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.draftText = body      // restore so the user doesn't lose it
                }
            }
        }
    }

    // MARK: - Photo sending

    @Published private(set) var isUploadingPhoto = false

    private let photoStorage = ChatPhotoStorageService()

    func sendPhoto(_ image: UIImage) {
        guard session.isPaired, !isUploadingPhoto else { return }
        isUploadingPhoto = true
        let messageId = UUID().uuidString
        Task {
            defer { Task { @MainActor in self.isUploadingPhoto = false } }
            do {
                let url = try await photoStorage.upload(image, coupleId: session.coupleId, messageId: messageId)
                if let parsed = URL(string: url) {
                    ImageCache.shared.store(image, for: parsed)
                }
                try await chatService.sendPhoto(url, coupleId: session.coupleId, senderId: session.userId)
            } catch {
                await MainActor.run { self.errorMessage = error.localizedDescription }
            }
        }
    }

    // MARK: - Quiz answering

    func presentQuizForAnswering(quizId: String) {
        guard let quiz = quizzes.first(where: { $0.id == quizId }) else { return }
        guard !quiz.hasAnswered(session.userId) else { return }
        activeQuizForAnswering = quiz
    }

    func submit(answer: ChatQuizAnswer, for quiz: ChatQuiz) {
        Task {
            do {
                let updated = try await chatService.submitAnswer(
                    answer,
                    quizId: quiz.id,
                    coupleId: session.coupleId,
                    userId: session.userId,
                    otherUserId: session.partnerId
                ) { [insightGen, session] builtFromQuiz in
                    insightGen.buildResult(for: builtFromQuiz,
                                           userAId: session.userId,
                                           userBId: session.partnerId)
                }

                await MainActor.run { self.activeQuizForAnswering = nil }

                // If we were the second answerer, aggregate into the profile.
                if updated.status == .complete {
                    try await aggregator.aggregate(updated,
                                                   coupleId: session.coupleId,
                                                   userAId: session.userId,
                                                   userBId: session.partnerId)
                }
            } catch {
                await MainActor.run { self.errorMessage = error.localizedDescription }
            }
        }
    }

    // MARK: - Helpers

    func quiz(for message: ChatMessage) -> ChatQuiz? {
        guard let id = message.quizId else { return nil }
        return quizzes.first { $0.id == id }
    }

    func hasAnswered(_ quiz: ChatQuiz) -> Bool {
        quiz.hasAnswered(session.userId)
    }

    func partnerAnswered(_ quiz: ChatQuiz) -> Bool {
        quiz.hasAnswered(session.partnerId)
    }

    var myUserId: String { session.userId }
    var partnerUserId: String { session.partnerId }

    // MARK: - Status helpers

    /// Status for the current user's outgoing message: pending (not yet
    /// acknowledged by Firestore), seen (partner read it), or sent.
    enum OutgoingStatus { case pending, sent, seen }

    func outgoingStatus(for message: ChatMessage) -> OutgoingStatus? {
        guard message.senderId == session.userId, message.kind == .text else { return nil }
        if pendingMessageIds.contains(message.id) { return .pending }
        if message.readBy.contains(session.partnerId) { return .seen }
        return .sent
    }

    // MARK: - Quiz picker (user-initiated)

    /// Post a quiz the user picked from the bank. Writes a system "New quiz"
    /// line, the quiz doc, and the card in one shot.
    func sendQuiz(template: ChatQuizTemplate) {
        Task {
            let quiz = ChatQuiz(
                id: UUID().uuidString,
                questionId: template.questionId,
                topic: template.topic,
                question: template.question,
                subtitle: template.subtitle,
                options: template.options,
                allowsMultiple: template.allowsMultiple,
                createdAt: Date(),
                status: .pending,
                answers: [:],
                result: nil,
                authorId: nil,
                authorAnswer: nil,
                customNote: nil
            )
            do {
                try await chatService.postSystemMessage(
                    "New quiz: \(quiz.topic.emoji) \(quiz.topic.label)",
                    coupleId: session.coupleId
                )
                try await chatService.postQuiz(quiz, coupleId: session.coupleId)
            } catch {
                await MainActor.run { self.errorMessage = error.localizedDescription }
            }
        }
    }

    // MARK: - Custom quiz (user-authored)

    /// Post a custom quiz authored by the current user. Pre-records the
    /// author's own answer (so the result-card match logic has the correct
    /// answer to compare against on the partner's side).
    ///
    /// - Parameters:
    ///   - title: optional human title (e.g. "Just for you ❤️"). Stored in
    ///     `subtitle` so the existing card layout renders it without changes.
    ///   - question: required body text.
    ///   - options: 2-6 answer choices.
    ///   - authorAnswer: which option(s) the author picked as "correct."
    ///   - allowsMultiple: whether the partner can pick more than one option.
    ///   - note: optional romantic note shown above the question.
    func sendCustomQuiz(
        title: String?,
        question: String,
        options: [String],
        authorAnswer: [String],
        allowsMultiple: Bool,
        note: String?
    ) {
        Task {
            let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let now = Date()

            // Pre-record the author's answer so the partner sees a match
            // calculation right after they answer (no need for the author to
            // tap "answer" on their own card).
            var prefilledAnswers: [String: ChatQuizAnswer] = [:]
            if !authorAnswer.isEmpty {
                prefilledAnswers[session.userId] = ChatQuizAnswer(
                    options: authorAnswer,
                    text: nil,
                    answeredAt: now
                )
            }

            let quiz = ChatQuiz(
                id: UUID().uuidString,
                questionId: "custom_\(UUID().uuidString)",
                topic: .loveLanguage,    // custom quizzes default to the love bucket — author's note carries the real flavor
                question: question.trimmingCharacters(in: .whitespacesAndNewlines),
                subtitle: trimmedTitle?.isEmpty == false ? trimmedTitle! : "From your partner ❤️",
                options: options,
                allowsMultiple: allowsMultiple,
                createdAt: now,
                status: prefilledAnswers.isEmpty ? .pending : .partial,
                answers: prefilledAnswers,
                result: nil,
                authorId: session.userId,
                authorAnswer: authorAnswer.isEmpty ? nil : authorAnswer,
                customNote: trimmedNote?.isEmpty == false ? trimmedNote : nil
            )

            do {
                try await chatService.postSystemMessage(
                    "Custom quiz from \(authorDisplayLabel())",
                    coupleId: session.coupleId
                )
                try await chatService.postQuiz(quiz, coupleId: session.coupleId)
            } catch {
                await MainActor.run { self.errorMessage = error.localizedDescription }
            }
        }
    }

    /// Short label for the system-line attribution. Falls back to "your
    /// partner" when we don't have a stored display name — the chat view
    /// model intentionally doesn't depend on the profile view model so this
    /// is a deliberate, lightweight phrasing.
    private func authorDisplayLabel() -> String {
        "your partner ❤️"
    }

    // MARK: - Read receipts

    /// Called from ChatView when the partner photo popup is dismissed.
    static func markMessageRead(messageId: String, coupleId: String, userId: String) async throws {
        try await FirestoreCoupleChatService().markAsRead(coupleId: coupleId, userId: userId, messageIds: [messageId])
    }

    private func markUnreadAsRead() {
        let unread = messages
            .filter { $0.senderId != session.userId }
            .filter { !$0.readBy.contains(session.userId) }
            .compactMap { $0.firestoreId ?? ($0.id.isEmpty ? nil : $0.id) }

        guard !unread.isEmpty else { return }
        Task {
            try? await chatService.markAsRead(coupleId: session.coupleId,
                                              userId: session.userId,
                                              messageIds: unread)
        }
    }

    // MARK: - Quiz suggestion (opportunistic, local host)

    /// Only the user with the lexicographically smaller uid posts the
    /// suggestion — cheap way to avoid both clients racing to write the same
    /// quiz. The service's `lastQuizSuggestedAt` gate and the transaction are
    /// additional safety.
    private var isSuggestionHost: Bool {
        session.userId < session.partnerId
    }

    private func maybeSuggestQuiz() async {
        guard isSuggestionHost else { return }

        // Read lastQuizSuggestedAt from the couple doc.
        let db = Firestore.firestore()
        let doc = try? await db.collection(FirestorePath.couples)
            .document(session.coupleId).getDocument()
        let lastSuggested = (doc?.data()?["lastQuizSuggestedAt"] as? Timestamp)?.dateValue()

        // Read current profile (for prioritisation) — cheap one-shot.
        let profileSnap = try? await db
            .document(FirestorePath.coupleProfileCurrent(coupleId: session.coupleId))
            .getDocument()
        let profile: CoupleInsightProfile
        if let snap = profileSnap, snap.exists,
           let loaded = try? snap.data(as: CoupleInsightProfile.self) {
            profile = loaded
        } else {
            profile = .empty
        }

        guard let quiz = await orchestrator.nextQuiz(
            coupleId: session.coupleId,
            profile: profile,
            recentQuizzes: quizzes,
            lastSuggestedAt: lastSuggested
        ) else { return }

        do {
            try await chatService.postSystemMessage(
                "New quiz: \(quiz.topic.emoji) \(quiz.topic.label)",
                coupleId: session.coupleId
            )
            try await chatService.postQuiz(quiz, coupleId: session.coupleId)
        } catch {
            await MainActor.run { self.errorMessage = error.localizedDescription }
        }
    }
}
