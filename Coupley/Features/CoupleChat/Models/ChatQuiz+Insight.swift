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
    ///
    /// Resolved through the stable option id rather than the stored display
    /// string. The old lookup keyed the bank's hint dictionary by the text
    /// read back out of Firestore, so it depended on the writing device and
    /// the reading device spelling the option identically — which stops being
    /// true the moment either translates it, or the bank is reworded. It
    /// failed by returning nil, and the gate above it removed the card with
    /// no empty state, so the payoff screen just quietly went missing.
    func insight(for userId: String) -> String? {
        guard let answer = answers[userId],
              let id = stableIds(for: answer).first
        else { return nil }
        return hint(forOptionId: id)
    }

    /// The option this user picked, labelled for whoever is reading. Used as
    /// the insight card's title.
    func insightOptionLabel(for userId: String) -> String? {
        guard let answer = answers[userId],
              let id = stableIds(for: answer).first
        else { return nil }
        return label(forOptionId: id)
    }


}
