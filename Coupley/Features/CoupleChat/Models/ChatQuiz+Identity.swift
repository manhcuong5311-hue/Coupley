//
//  ChatQuiz+Identity.swift
//  Coupley
//
//  The one place that decides whether a stored pick is an id or a display
//  string. Everything downstream — match detection, the guess game, the
//  insight paragraph, the trait aggregator — asks here instead of touching
//  `answer.options` directly.
//
//  Three kinds of document arrive at these methods, and the rules differ:
//
//  1. CURATED / QotD / suggested, written by a build that has `optionIds`.
//     The ids are authoritative. Labels are drawn from the local bank, so
//     each partner reads the question in their own language.
//
//  2. CURATED, written before `optionIds` existed. Only English labels are
//     stored. They are mapped back to ids through the bank, which works
//     because `developmentRegion = en`: the English strings stay in source as
//     the catalog's base values, so the mapping never expires. An option the
//     bank has since reworded resolves to nothing and degrades to its stored
//     text — honest, rather than silently matching the wrong option.
//
//  3. CUSTOM (user-authored). There is no bank entry and the option text is
//     the user's own words, identical on both devices and never translated.
//     For these the label *is* the identity, which is why the methods below
//     fall through to the raw string rather than treating it as unresolvable.
//
//  Ordering is always the quiz's own option order, never `Set` iteration
//  order. The previous code took `Set.first` to name the shared option in the
//  result sentence, which for the seven multi-select templates picked a
//  different option on different runs.
//

import Foundation

/// An option resolved for use: stable identity, the text to draw, and the
/// text to store.
///
/// `label` is the bank option's `displayLabel` (the Content catalog's
/// translation) and `baseLabel` its English source; they are the same string
/// only for a custom quiz or an option the bank cannot resolve. Keeping them
/// apart is what keeps the write path correct whatever language the device
/// runs: anything written to Firestore takes `baseLabel`, anything drawn
/// takes `label`.
///
/// This matters more than it looks. The build already on the App Store
/// rewrites the whole quiz document on every answer (`setData(from:)` with no
/// merge), which deletes `optionIds` from the quiz and from BOTH partners'
/// answers. Nothing in this repo can stop that build doing it. What keeps the
/// data readable anyway is that the stored text stays English, so
/// `option(label:)` can always map it back to an id.
struct ResolvedQuizOption: Identifiable, Equatable {
    let id: String
    /// For drawing.
    let label: String
    /// For storing, and for anything another device has to match.
    let baseLabel: String
}

extension ChatQuiz {

    /// The curated template behind this quiz, or nil for a custom one.
    var template: ChatQuizTemplate? { ChatQuizBank.byId(questionId) }

    /// The options this quiz offers, preserving the set the document was
    /// written with while taking labels from the local bank where it can.
    ///
    /// A document that stores ids keeps its own option set even if the bank
    /// has since dropped one; a document that predates ids has its English
    /// labels mapped forward, which is what makes an old quiz render in a new
    /// language.
    var resolvedOptions: [ResolvedQuizOption] {
        deduped(rawResolvedOptions)
    }

    /// The question to draw: the bank's, so it reads in the reader's
    /// language, falling back to the text the document stored — which is the
    /// right answer for a custom quiz, and for anything the bank no longer
    /// has.
    ///
    /// Without this the card mixed languages: the options resolved through
    /// the bank while the question above them stayed frozen in whatever
    /// language posted the quiz.
    var displayQuestion: String { template?.displayQuestion ?? question }

    var displaySubtitle: String {
        // Only curated quizzes take the bank's subtitle. A custom quiz stores
        // the author's own title here, or, when they gave none, the English
        // default the composer writes, which is drawn in the reader's
        // language instead.
        guard isCustom else { return template?.displaySubtitle ?? subtitle }
        guard subtitle == Self.untitledCustomSubtitle else { return subtitle }
        return String(localized: "From your partner ❤️",
                      comment: "Subtitle of a custom quiz whose author gave it no title")
    }

    /// Keeps the first entry for each id.
    ///
    /// A custom quiz uses its option text as its id, and the composer that
    /// shipped does not reject two identical options — so documents with
    /// duplicate ids exist and will keep being written by that build. Left
    /// alone they reach `ForEach` as duplicate `Identifiable` ids, make both
    /// rows select together, and store the pick twice.
    private func deduped(_ options: [ResolvedQuizOption]) -> [ResolvedQuizOption] {
        var seen = Set<String>()
        return options.filter { seen.insert($0.id).inserted }
    }

    private var rawResolvedOptions: [ResolvedQuizOption] {
        let tpl = template

        if let ids = optionIds, !ids.isEmpty {
            return ids.enumerated().map { index, id in
                let stored = options.indices.contains(index) ? options[index] : nil
                guard let opt = tpl?.option(id: id) else {
                    let fallback = stored ?? id
                    return ResolvedQuizOption(id: id, label: fallback, baseLabel: fallback)
                }
                return ResolvedQuizOption(id: id,
                                          label: opt.displayLabel,
                                          baseLabel: opt.label)
            }
        }

        return options.map { stored in
            if let opt = tpl?.option(label: stored) {
                return ResolvedQuizOption(id: opt.id,
                                          label: opt.displayLabel,
                                          baseLabel: opt.label)
            }
            return ResolvedQuizOption(id: stored, label: stored, baseLabel: stored)
        }
    }

    /// Stable ids for what `answer` picked, in this quiz's option order.
    ///
    /// Comparable across devices and languages. This is the only thing any
    /// equality check should ever see.
    func stableIds(for answer: ChatQuizAnswer) -> [String] {
        ordered(resolve(answer.optionIds, legacy: answer.options))
    }

    /// Stable ids for what `answer` predicted, or nil when no guess was made.
    func stableGuessIds(for answer: ChatQuizAnswer) -> [String]? {
        if let ids = answer.guessIds, !ids.isEmpty { return ordered(ids) }
        guard let guess = answer.guess, !guess.isEmpty else { return nil }
        return ordered(resolve(nil, legacy: guess))
    }

    /// Stable ids for `userId`'s answer, or nil if they have not answered.
    func stableIds(ofUser userId: String) -> [String]? {
        answers[userId].map { stableIds(for: $0) }
    }

    /// Whether `viewer`'s prediction matched what `partner` actually chose.
    /// `nil` when no prediction was made or the partner has not answered.
    ///
    /// Replaces the old `ChatQuizAnswer.guessWasRight(against:)`, which
    /// compared display strings and so scored every cross-language couple
    /// wrong on every question.
    func guessWasRight(viewer: String, partner: String) -> Bool? {
        guard let mine = answers[viewer],
              let guess = stableGuessIds(for: mine), !guess.isEmpty,
              let actual = stableIds(ofUser: partner), !actual.isEmpty
        else { return nil }
        return Set(guess) == Set(actual)
    }

    /// Ids both partners picked, in this quiz's option order.
    func sharedOptionIds(_ userA: String, _ userB: String) -> [String] {
        guard let a = stableIds(ofUser: userA),
              let b = stableIds(ofUser: userB)
        else { return [] }
        let common = Set(a).intersection(Set(b))
        return ordered(Array(common))
    }

    /// The text to DRAW for a stable id.
    ///
    /// Never returns nil for an id that came out of `stableIds`: callers
    /// `compactMap` over this, so returning nil silently dropped the user's
    /// pick from the answer row, the guess row and the trait line rather than
    /// showing something imperfect. An id with no better answer is its own
    /// best label.
    func label(forOptionId id: String) -> String {
        resolvedOptions.first { $0.id == id }?.label
            ?? template?.option(id: id)?.displayLabel
            ?? id
    }

    /// The text to STORE for a stable id — base language, so another device
    /// and a later build can both still match it.
    func baseLabel(forOptionId id: String) -> String {
        resolvedOptions.first { $0.id == id }?.baseLabel
            ?? template?.option(id: id)?.label
            ?? id
    }

    /// The hint paragraph to DRAW for a stable id, or nil for custom quizzes
    /// and the four multi-select pickers that carry none.
    func hint(forOptionId id: String) -> String? {
        template?.option(id: id)?.displayHint
    }

    /// What `userId` picked, drawn for whoever is reading. Empty when they
    /// have not answered, or answered a free-text question.
    func optionLabels(ofUser userId: String) -> [String] {
        guard let ids = stableIds(ofUser: userId) else { return [] }
        return ids.map { label(forOptionId: $0) }
    }

    /// What `userId` picked, in base language — for anything written back to
    /// Firestore.
    func baseLabels(ofUser userId: String) -> [String] {
        guard let ids = stableIds(ofUser: userId) else { return [] }
        return ids.map { baseLabel(forOptionId: $0) }
    }

    /// What `userId` predicted, drawn for whoever is reading. Nil when no
    /// prediction was made.
    func guessLabels(ofUser userId: String) -> [String]? {
        guard let answer = answers[userId],
              let ids = stableGuessIds(for: answer), !ids.isEmpty
        else { return nil }
        return ids.map { label(forOptionId: $0) }
    }

    // MARK: - Private

    /// Prefers stored ids. Failing that, maps stored text through the quiz
    /// document's OWN `options`/`optionIds` arrays — the one pair guaranteed
    /// to correspond, because they were written together and survive the bank
    /// being reworded. Only then falls back to the bank, and finally to the
    /// text itself, which is the correct identity for a custom quiz.
    private func resolve(_ ids: [String]?, legacy: [String]) -> [String] {
        if let ids, !ids.isEmpty { return ids }
        let tpl = template
        let ownIds = optionIds
        return legacy.map { stored in
            if let own = ownIds,
               let index = options.firstIndex(of: stored),
               own.indices.contains(index) {
                return own[index]
            }
            return tpl?.optionId(forLabel: stored) ?? stored
        }
    }

    /// Sorts into this quiz's option order so callers never depend on `Set`
    /// iteration.
    ///
    /// Ids the quiz does not offer are sorted by their own value, not by where
    /// they happened to arrive: callers pass `Array(someSet)`, whose order is
    /// seeded per process, so tie-breaking on arrival position would have left
    /// exactly the run-to-run instability this method exists to remove.
    private func ordered(_ ids: [String]) -> [String] {
        let order = resolvedOptions.map(\.id)
        let rank = Dictionary(
            order.enumerated().map { ($0.element, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
        return ids.sorted { lhs, rhs in
            switch (rank[lhs], rank[rhs]) {
            case let (l?, r?):   return l < r
            case (_?, nil):      return true
            case (nil, _?):      return false
            case (nil, nil):     return lhs < rhs
            }
        }
    }
}
