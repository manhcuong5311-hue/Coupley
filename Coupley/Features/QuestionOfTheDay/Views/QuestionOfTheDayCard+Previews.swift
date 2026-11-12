//
//  QuestionOfTheDayCard+Previews.swift
//  Coupley
//
//  Preview-only scaffolding, kept out of the card file so the production view
//  does not pull in a Firestore dependency it otherwise has no use for.
//
//  The card's four states are only reachable in the real app with a
//  signed-in, paired couple and a question already created for the day, which
//  makes them awkward to eyeball. These stubs reproduce each one directly.
//

#if DEBUG

import SwiftUI
import FirebaseFirestore

// MARK: - Previews


/// Emits a fixed quiz and never touches Firestore, so the card can be
/// inspected in every state without a signed-in, paired account.
private final class StubQotDService: QuestionOfTheDayServicing {

    private final class NoopRegistration: NSObject, ListenerRegistration {
        func remove() {}
    }

    let quiz: ChatQuiz?
    init(quiz: ChatQuiz?) { self.quiz = quiz }

    func observeCurrent(
        coupleId: String,
        onUpdate: @escaping (ChatQuiz?) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        onUpdate(quiz)
        return NoopRegistration()
    }

    func ensureCurrentQuestion(coupleId: String, userId: String) async throws -> Bool { false }
}

private enum QotDPreview {

    static let me      = "me_001"
    static let partner = "partner_002"

    /// A real session shape — `UserSession.demo` is deliberately rejected by
    /// the view model, so the preview needs its own couple id.
    static let session = UserSession(userId: me, coupleId: "preview_couple", partnerId: partner)

    static func quiz(
        myAnswer: String? = nil,
        partnerAnswer: String? = nil,
        result: ChatQuizResult? = nil
    ) -> ChatQuiz {
        var answers: [String: ChatQuizAnswer] = [:]
        if let myAnswer {
            answers[me] = ChatQuizAnswer(options: [myAnswer], text: nil, answeredAt: Date())
        }
        if let partnerAnswer {
            answers[partner] = ChatQuizAnswer(options: [partnerAnswer], text: nil, answeredAt: Date())
        }
        return ChatQuiz(
            id: "qotd-preview",
            questionId: "ll_primary",
            topic: .loveLanguage,
            question: "Which makes you feel most loved?",
            subtitle: "This is how you receive love best — your partner needs to know this.",
            options: ["Words of affirmation", "Quality time", "Acts of service",
                      "Physical touch", "Gifts"],
            allowsMultiple: false,
            createdAt: Date(),
            status: result == nil ? (answers.isEmpty ? .pending : .partial) : .complete,
            answers: answers,
            result: result,
            kind: .questionOfTheDay,
            triggeredBy: partner
        )
    }

    @MainActor
    static func card(_ quiz: ChatQuiz?) -> some View {
        let vm = QuestionOfTheDayViewModel(session: session, service: StubQotDService(quiz: quiz))
        vm.start()
        return ZStack {
            Brand.bgGradient.ignoresSafeArea()
            QuestionOfTheDayCard(viewModel: vm, partnerName: "Linh")
                .padding(20)
        }
    }
}

#Preview("1 · Chưa ai trả lời") {
    QotDPreview.card(QotDPreview.quiz())
}

#Preview("2 · Người kia đã trả lời trước") {
    QotDPreview.card(QotDPreview.quiz(partnerAnswer: "Quality time"))
}

#Preview("3 · Mình trả lời rồi, đang chờ") {
    QotDPreview.card(QotDPreview.quiz(myAnswer: "Acts of service"))
}

#Preview("4 · Cả hai xong · chọn khác nhau") {
    QotDPreview.card(QotDPreview.quiz(
        myAnswer: "Acts of service",
        partnerAnswer: "Words of affirmation",
        result: ChatQuizResult(
            match: false,
            summary: "You give in deeds, Linh hears in words",
            emoji: "🔀",
            traits: [:],
            postedAt: Date(),
            postedByClientId: "preview"
        )
    ))
}

#Preview("5 · Cả hai xong · trùng nhau") {
    QotDPreview.card(QotDPreview.quiz(
        myAnswer: "Quality time",
        partnerAnswer: "Quality time",
        result: ChatQuizResult(
            match: true,
            summary: "You both chose Quality time ❤️",
            emoji: "🎯",
            traits: [:],
            postedAt: Date(),
            postedByClientId: "preview"
        )
    ))
}

#endif
