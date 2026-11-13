//
//  ChatQuiz+ResultSentence.swift
//  Coupley
//
//  Renders the result verdict on the reading device instead of printing the
//  sentence the writing device happened to compose.
//
//  The old shape stored finished prose in TWO documents — the quiz's
//  `result.summary` and the result chat message's `resultSummary` — written by
//  whichever partner answered second. Both partners then read that one string,
//  so the language of the result was decided by who was slower to answer.
//
//  Fixing only the quiz document was not enough, and the reason is worth
//  keeping: the quiz listener is capped at 20 (CoupleChatService.listenToQuizzes),
//  while messages page back without bound. Scroll past the twentieth quiz and
//  the result card has no quiz to render from, so it falls through to the
//  message's own copy. The verdict therefore has to be on the message too, or
//  every older card is frozen in one language for good — nothing deletes these
//  documents and no backfill is possible.
//
//  There are exactly three frames. When the catalog lands these are the three
//  strings to translate.
//

import Foundation

/// The three sentences a finished quiz can produce.
enum QuizResultCopy {

    /// `optionLabel` is a runtime parameter, not a key: for a custom quiz it
    /// is the author's own words.
    ///
    /// The `.lowercased()` below is correct for the English base copy and will
    /// not be for every language — German does not lowercase its nouns, and
    /// Turkish needs the locale-aware overload. It stays here only until these
    /// frames become catalog entries, at which point each translation owns its
    /// own casing and this call goes away.
    static func sentence(kind: QuizResultKind,
                         optionLabel: String?,
                         emoji: String,
                         topicLabel: String) -> String {
        switch kind {
        case .matchShared:
            guard let optionLabel else {
                return "You're on the same page here \(emoji)"
            }
            return "You both value \(optionLabel.lowercased()) \(emoji)"
        case .matchGeneric:
            return "You're on the same page here \(emoji)"
        case .mismatch:
            return "You see \(topicLabel.lowercased()) a little differently — might be worth a chat."
        }
    }
}

extension ChatQuiz {

    /// The result sentence for whoever is reading, or nil if there is no
    /// result yet.
    var resultSentence: String? {
        guard let result else { return nil }

        if let kind = result.kind {
            // `label(forOptionId:)` never returns nil — it falls back to the
            // id — so asking it first and coalescing to `sharedOptionLabel`
            // would make that fallback unreachable and print a raw slug. Try
            // to resolve properly, and only then use the label the writer
            // stored.
            let resolved = result.sharedOptionId.flatMap { id in
                resolvedOptions.first { $0.id == id }?.label
                    ?? template?.option(id: id)?.displayLabel
            }
            return QuizResultCopy.sentence(kind: kind,
                                           optionLabel: resolved ?? result.sharedOptionLabel,
                                           emoji: result.emoji,
                                           topicLabel: topic.label)
        }

        // No stored verdict — a document written before `kind` existed, which
        // is every result currently in Firestore. The prose cannot be
        // translated, but the verdict can be rebuilt: both answers are still
        // on this document, and `match` was already arbitrated by whichever
        // device wrote it, so only the named option needs recomputing.
        if let rebuilt = rebuiltVerdict() {
            return QuizResultCopy.sentence(kind: rebuilt.kind,
                                           optionLabel: rebuilt.optionLabel,
                                           emoji: result.emoji,
                                           topicLabel: topic.label)
        }

        return result.summary
    }

    /// Rebuilds the verdict for a document written before `kind` existed —
    /// but only where the rebuild cannot change what the result MEANS.
    ///
    /// `match` is taken from the document, never recomputed: it was arbitrated
    /// by whichever device wrote it, and both partners have been reading it.
    /// The named option is only rebuilt when the two picks overlap on exactly
    /// one option. With several overlapping — which the seven multi-select
    /// templates allow — the original sentence named one of them by `Set`
    /// order, and there is no way to know which; renaming it would quietly
    /// rewrite a result the couple has already read, to say something else
    /// that happens to also be true. In that case the frozen prose stands.
    private func rebuiltVerdict() -> (kind: QuizResultKind, optionLabel: String?)? {
        guard let result, answers.count >= 2 else { return nil }
        let ids = answers.keys.sorted()

        guard result.match else { return (.mismatch, nil) }

        let shared = sharedOptionIds(ids[0], ids[1])
        if shared.isEmpty {
            // Matched on equal free text, so there is no option to name.
            return (.matchGeneric, nil)
        }
        guard shared.count == 1 else { return nil }
        return (.matchShared, label(forOptionId: shared[0]))
    }
}

extension ChatMessage {

    /// The result sentence from the message's own stored verdict, for the
    /// cards whose quiz is no longer loaded. Nil when the message predates the
    /// verdict fields, in which case the caller falls back to `resultSummary`.
    var renderedResultSentence: String? {
        guard let raw = resultKind,
              let kind = QuizResultKind(rawValue: raw)
        else { return nil }

        // A mismatch sentence needs the topic. Without it the frame would read
        // "You see  a little differently", so hand back nil and let the caller
        // fall through to the complete, if English, prose.
        let topicLabel = resultTopic.flatMap { QuizTopic(rawValue: $0) }?.label
        if kind == .mismatch, topicLabel == nil { return nil }

        // The ref carries its questionId, which is what makes the option
        // resolvable from a message that has no quiz attached.
        let option = resultOptionRef.flatMap { QuizOptionRef.label($0) }
            ?? resultOptionLabel

        return QuizResultCopy.sentence(kind: kind,
                                       optionLabel: option,
                                       emoji: resultEmoji ?? "",
                                       topicLabel: topicLabel ?? "")
    }
}
