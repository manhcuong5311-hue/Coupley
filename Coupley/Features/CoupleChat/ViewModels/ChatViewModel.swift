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
    @Published var draftText: String = ""
    @Published private(set) var isSending = false
    @Published private(set) var errorMessage: String?

    // Quiz answer flow (view presents a sheet when this is non-nil)
    @Published var activeQuizForAnswering: ChatQuiz?

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
         chatService:   CoupleChatServicing   = FirestoreCoupleChatService(),
         orchestrator:  QuizOrchestrating     = DefaultQuizOrchestrator(),
         insightGen:    InsightGenerating     = DefaultInsightGenerator(),
         aggregator:    CoupleInsightAggregating = FirestoreCoupleInsightAggregator()) {
        self.session = session
        self.chatService  = chatService
        self.orchestrator = orchestrator
        self.insightGen   = insightGen
        self.aggregator   = aggregator
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
            limit: 100,
            onUpdate: { [weak self] newMessages in
                Task { @MainActor in
                    guard let self else { return }
                    self.messages = newMessages
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

    // MARK: - Read receipts

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
