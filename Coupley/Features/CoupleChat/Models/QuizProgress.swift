//
//  QuizProgress.swift
//  Coupley
//
//  Which questions a couple has already been asked, and which they finished.
//
//  This deliberately does not come from `ChatViewModel.quizzes`: that listener
//  caps at the newest 20 documents, so anything older looks unasked. The quiz
//  picker and the suggestion logic both need the whole history — otherwise a
//  couple starts seeing questions they answered months ago presented as new.
//

import Foundation

struct QuizProgress: Equatable {

    /// Questions both partners finished.
    let answered: Set<String>
    /// Questions posted but not finished by both yet.
    let pending: Set<String>

    /// How many finished quizzes the viewer made a prediction on, and how
    /// many of those predictions were right.
    var guessesMade: Int = 0
    var guessesCorrect: Int = 0

    static let empty = QuizProgress(answered: [], pending: [])

    /// "How well do you know them", 0–100.
    ///
    /// Withheld below a handful of guesses: one lucky hit reading as 100%
    /// is worse than showing nothing, and the number is meant to be
    /// something a couple watches move over months.
    var knowledgeScore: Int? {
        guard guessesMade >= 3 else { return nil }
        return Int((Double(guessesCorrect) / Double(guessesMade) * 100).rounded())
    }

    func isAnswered(_ questionId: String) -> Bool { answered.contains(questionId) }
    func isPending(_ questionId: String) -> Bool { pending.contains(questionId) }

    /// Asked at all, in either state — what the suggester should skip.
    func isUsed(_ questionId: String) -> Bool {
        isAnswered(questionId) || isPending(questionId)
    }

    // MARK: - Per topic

    func answeredCount(in topic: QuizTopic) -> Int {
        ChatQuizBank.byTopic(topic).reduce(0) {
            $0 + (answered.contains($1.questionId) ? 1 : 0)
        }
    }

    func total(in topic: QuizTopic) -> Int {
        ChatQuizBank.byTopic(topic).count
    }

    /// 0...1. Used to float the least-explored topics to the top of the
    /// picker and to steer the suggester toward thin ground.
    func completion(in topic: QuizTopic) -> Double {
        let total = total(in: topic)
        guard total > 0 else { return 1 }
        return Double(answeredCount(in: topic)) / Double(total)
    }

    func isFullyAnswered(_ topic: QuizTopic) -> Bool {
        total(in: topic) > 0 && answeredCount(in: topic) == total(in: topic)
    }
}
