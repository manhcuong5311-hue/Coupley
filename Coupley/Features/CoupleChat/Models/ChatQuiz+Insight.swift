//
//  ChatQuiz+Insight.swift
//  Coupley
//
//  The curated bank carries an `optionHints` paragraph for every option of
//  every question — roughly 360 of them, explaining what a given choice says
//  about the person who made it.
//
//  Until now that writing was only ever shown to the person doing the
//  choosing, in the answer sheet, at the moment they tapped. The partner
//  never saw it: when a quiz completed, each side got the other's bare option
//  string. That is the moment the whole blind-answer mechanic builds toward,
//  and it was the flattest screen in the flow.
//
//  This resolves the insight for any participant so the completed-quiz views
//  can show it. Custom (user-authored) quizzes have no bank entry and
//  correctly return nil.
//

import Foundation

extension ChatQuiz {

    /// What the option this user picked says about them, from the curated
    /// bank. `nil` for custom quizzes, unanswered users, or free-text answers.
    func insight(for userId: String) -> String? {
        guard let pick = answers[userId]?.options.first,
              let template = ChatQuizBank.byId(questionId)
        else { return nil }
        return template.optionHints[pick]
    }

}
