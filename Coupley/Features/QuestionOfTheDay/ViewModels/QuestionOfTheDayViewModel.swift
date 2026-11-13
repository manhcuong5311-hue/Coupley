//
//  QuestionOfTheDayViewModel.swift
//  Coupley
//
//  Drives the Home card. Answer submission deliberately reuses
//  `CoupleChatServicing.submitAnswer` rather than reimplementing it: that
//  method already owns the double-answer transaction, posts the result card,
//  and is idempotent if the same user submits twice. The daily question is a
//  quiz like any other — only its origin differs.
//

import Foundation
import Combine
import FirebaseFirestore

@MainActor
final class QuestionOfTheDayViewModel: ObservableObject {

    // MARK: - Published

    @Published private(set) var quiz: ChatQuiz?
    @Published private(set) var isLoading = true
    @Published private(set) var isSubmitting = false
    @Published private(set) var errorMessage: String?
    /// Only for a failed answer submission. Kept apart from `errorMessage`,
    /// which the snapshot listeners also write: sharing it made a listener
    /// hiccup appear as "Couldn't send your answer".
    @Published private(set) var submitError: String?

    /// Non-nil while the answer sheet is up.
    @Published var quizBeingAnswered: ChatQuiz?

    // MARK: - Dependencies

    private var session: UserSession
    private let service: QuestionOfTheDayServicing
    private let chatService: CoupleChatServicing
    private let insightGen: InsightGenerating
    private let aggregator: CoupleInsightAggregating

    private var listener: ListenerRegistration?
    private var lastEnsureAttempt: Date?

    /// How long to wait before asking the service again whether a question is
    /// due. Without this the check would only ever run once per launch, and an
    /// app left open overnight would never pick up the next day's question.
    private static let ensureRetryInterval: TimeInterval = 3600

    // MARK: - Init

    init(
        session: UserSession,
        service: QuestionOfTheDayServicing? = nil,
        chatService: CoupleChatServicing? = nil,
        insightGen: InsightGenerating? = nil,
        aggregator: CoupleInsightAggregating? = nil
    ) {
        self.session     = session
        self.service     = service     ?? FirestoreQuestionOfTheDayService()
        self.chatService = chatService ?? FirestoreCoupleChatService()
        self.insightGen  = insightGen  ?? DefaultInsightGenerator()
        self.aggregator  = aggregator  ?? FirestoreCoupleInsightAggregator()
    }

    deinit { listener?.remove() }

    // MARK: - Derived state

    enum CardState: Equatable {
        /// Not paired, or the bank produced nothing — card hides itself.
        case hidden
        case loading
        /// Waiting for this user to answer.
        case awaitingMe(ChatQuiz)
        /// This user answered; the partner hasn't.
        case awaitingPartner(ChatQuiz)
        /// Both answered — result is in.
        case complete(ChatQuiz)
    }

    var state: CardState {
        guard hasRealSession else { return .hidden }
        guard let quiz else { return isLoading ? .loading : .hidden }

        if !quiz.hasAnswered(session.userId)      { return .awaitingMe(quiz) }
        if !quiz.hasAnswered(session.partnerId)   { return .awaitingPartner(quiz) }
        return .complete(quiz)
    }

    var myUserId: String { session.userId }
    var partnerUserId: String { session.partnerId }

    /// What the partner's pick says about them. The payoff of answering
    /// blind — available only once both have answered.
    var partnerAnswerInsight: String? {
        guard let quiz, quiz.hasAnswered(session.userId) else { return nil }
        return quiz.insight(for: session.partnerId)
    }


    /// The hint attached to the option this user picked. Gives the card
    /// something to say after answering, instead of a bare "waiting".
    ///
    /// Was its own copy of the hint lookup, keyed by the stored display
    /// string; it is now the same id-based resolution the chat card uses.
    var myAnswerHint: String? {
        quiz?.insight(for: session.userId)
    }

    /// The option this user picked, labelled for them.
    var myAnswerLabel: String? {
        quiz?.optionLabels(ofUser: session.userId).first
    }

    /// The option the partner picked, labelled for this reader. Titles the
    /// insight card.
    var partnerAnswerLabel: String? {
        quiz?.optionLabels(ofUser: session.partnerId).first
    }

    // MARK: - Lifecycle

    /// Rebind after pairing completes — the session captured at init is a
    /// stale snapshot while the user is still solo.
    func rebind(session: UserSession) {
        guard session.coupleId != self.session.coupleId
                || session.userId != self.session.userId else { return }
        self.session = session
        lastEnsureAttempt = nil
        stop()
        start()
    }

    /// `UserSession.demo` reports `isPaired == true` (it carries a fake
    /// couple id), and the view holds it until `rebind` supplies the real
    /// session. Listening on it would query a couple this user isn't a
    /// member of and get denied by the security rules.
    private var hasRealSession: Bool {
        session.isPaired && session.coupleId != UserSession.demo.coupleId
    }

    /// Safe to call on every appearance of the Home tab: the listener is
    /// attached once, and the due-check throttles itself.
    func start() {
        guard hasRealSession else {
            isLoading = false
            return
        }

        if listener == nil {
            listener = service.observeCurrent(
                coupleId: session.coupleId,
                onUpdate: { [weak self] quiz in
                    Task { @MainActor in
                        self?.quiz = quiz
                        self?.isLoading = false
                    }
                },
                onError: { [weak self] error in
                    Task { @MainActor in
                        self?.errorMessage = error.localizedDescription
                        self?.isLoading = false
                    }
                }
            )
        }

        ensureQuestionExists()
    }

    func stop() {
        listener?.remove()
        listener = nil
    }

    /// Creates today's question when one is due. The service is a safe no-op
    /// otherwise, but this is still throttled so returning to the Home tab
    /// doesn't fire a transaction every time.
    private func ensureQuestionExists() {
        guard hasRealSession else { return }
        if let last = lastEnsureAttempt,
           Date().timeIntervalSince(last) < Self.ensureRetryInterval {
            return
        }
        lastEnsureAttempt = Date()

        Task { [weak self, service, session] in
            do {
                try await service.ensureCurrentQuestion(
                    coupleId: session.coupleId,
                    userId: session.userId
                )
            } catch {
                // A failure here is not worth surfacing: the listener still
                // shows yesterday's question. But it must not count as an
                // attempt — the stamp above is taken before the call, so one
                // offline launch used to block every retry for an hour.
                print("[QotD] ensureCurrentQuestion failed: \(error.localizedDescription)")
                self?.lastEnsureAttempt = nil
            }
        }
    }

    // MARK: - Answering

    /// Called when the failure alert is dismissed.
    func dismissError() {
        submitError = nil
    }

    func beginAnswering() {
        guard let quiz, !quiz.hasAnswered(session.userId) else { return }
        submitError = nil
        quizBeingAnswered = quiz
    }

    func submit(answer: ChatQuizAnswer, for quiz: ChatQuiz) {
        guard !isSubmitting else { return }
        isSubmitting = true
        submitError = nil

        Task {
            defer { isSubmitting = false }
            do {
                let updated = try await chatService.submitAnswer(
                    answer,
                    quizId: quiz.id,
                    coupleId: session.coupleId,
                    userId: session.userId,
                    otherUserId: session.partnerId
                ) { [insightGen, session] built in
                    insightGen.buildResult(
                        for: built,
                        userAId: session.userId,
                        userBId: session.partnerId
                    )
                }

                quizBeingAnswered = nil

                if updated.status == .complete {
                    // Best effort: the answer is already saved by this point,
                    // so a failure here must not read as "couldn't send".
                    try? await aggregator.aggregate(
                        updated,
                        coupleId: session.coupleId,
                        userAId: session.userId,
                        userBId: session.partnerId
                    )
                }

                // Same qualifying-action contract as a mood check-in or a
                // saved memory (see AdsConfig.interstitialEveryNActions).
                AdsManager.shared.recordAction()
            } catch {
                submitError = error.localizedDescription
            }
        }
    }
}
