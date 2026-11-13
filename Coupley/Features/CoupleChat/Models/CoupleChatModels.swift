//
//  CoupleChatModels.swift
//  Coupley
//
//  Firestore-backed data model for the Couple Quiz Chat feature.
//  Messages, quizzes, answers, and the aggregated couple insight profile.
//

import Foundation
import FirebaseFirestore

// MARK: - Firestore paths (extend the existing enum)

extension FirestorePath {
    static func messages(coupleId: String) -> String {
        "\(couples)/\(coupleId)/messages"
    }
    static func chatQuizzes(coupleId: String) -> String {
        "\(couples)/\(coupleId)/quizzes"
    }
    static func coupleProfile(coupleId: String) -> String {
        "\(couples)/\(coupleId)/coupleProfile"
    }
    static func coupleProfileCurrent(coupleId: String) -> String {
        "\(coupleProfile(coupleId: coupleId))/current"
    }
}

// MARK: - Quiz Topic

/// Broad life buckets. Used both to classify questions and to aggregate profile.
enum QuizTopic: String, Codable, CaseIterable, Identifiable {
    case loveLanguage
    case communication
    case finance
    case lifestyle
    case conflict
    case intimacy
    case music
    case sport
    case travel
    case food
    case family
    case career

    var id: String { rawValue }

    /// What to draw. Identical to `baseLabel` until there is a string
    /// catalog; then this becomes the lookup and `baseLabel` stays put.
    var label: String { baseLabel }

    /// BASE-LANGUAGE name. Interpolated into strings that get written to
    /// Firestore — the mismatch verdict and the "New quiz" system line — and
    /// read back by a device in another language, so it must not move.
    var baseLabel: String {
        switch self {
        case .loveLanguage:  return "Love & Emotion"
        case .communication: return "Communication"
        case .finance:       return "Finance"
        case .lifestyle:     return "Lifestyle"
        case .conflict:      return "Conflict"
        case .intimacy:      return "Intimacy"
        case .music:         return "Music"
        case .sport:         return "Sport"
        case .travel:        return "Travel"
        case .food:          return "Food"
        case .family:        return "Family"
        case .career:        return "Career"
        }
    }

    var emoji: String {
        switch self {
        case .loveLanguage:  return "❤️"
        case .communication: return "💬"
        case .finance:       return "💰"
        case .lifestyle:     return "🎯"
        case .conflict:      return "🕊"
        case .intimacy:      return "🔥"
        case .music:         return "🎵"
        case .sport:         return "🏃"
        case .travel:        return "✈️"
        case .food:          return "🍜"
        case .family:        return "👨‍👩‍👧"
        case .career:        return "💼"
        }
    }
}

// MARK: - Chat Message

enum ChatMessageKind: String, Codable {
    case text           // free-form user message
    case system         // app-generated neutral message ("New quiz: …")
    case quiz           // references a quiz doc (renders a card)
    case result         // renders the comparison result card
    case photo          // image sent between partners
}

struct ChatMessage: Identifiable, Codable, Equatable {
    @DocumentID var firestoreId: String?
    let id: String
    let kind: ChatMessageKind
    let senderId: String?           // nil for system/result
    let createdAt: Date
    var readBy: [String]

    // kind-specific payload (only one of these is set)
    let text: String?
    let quizId: String?
    /// The finished sentence, in the language of whichever device answered
    /// second. Legacy — draw `renderedResultSentence` first.
    let resultSummary: String?
    let resultEmoji: String?
    let resultMatch: Bool?
    let imageURL: String?       // only set for .photo messages

    /// The verdict, repeated from the quiz document so a result card can be
    /// rendered in the reader's language even when its quiz is no longer
    /// loaded — which is routine, because the quiz listener is capped at 20
    /// while messages page back without limit.
    ///
    /// `QuizResultKind` raw value.
    var resultKind: String? = nil
    /// `questionId.optionId`, not a bare option id.
    ///
    /// Option ids are scoped to their template, and a message carries no
    /// `questionId` — only the quiz's document id — so a bare slug here would
    /// be unresolvable and this whole path would still render base language.
    var resultOptionRef: String? = nil
    /// Base-language label for the shared option, for when the reader's own
    /// bank cannot resolve the ref (a custom quiz, or an option since
    /// removed).
    var resultOptionLabel: String? = nil
    /// `QuizTopic` raw value, needed by the mismatch frame.
    var resultTopic: String? = nil

    static func text(_ body: String, senderId: String) -> ChatMessage {
        ChatMessage(id: UUID().uuidString, kind: .text, senderId: senderId,
                    createdAt: Date(), readBy: [senderId],
                    text: body, quizId: nil,
                    resultSummary: nil, resultEmoji: nil, resultMatch: nil,
                    imageURL: nil)
    }

    static func system(_ body: String) -> ChatMessage {
        ChatMessage(id: UUID().uuidString, kind: .system, senderId: nil,
                    createdAt: Date(), readBy: [],
                    text: body, quizId: nil,
                    resultSummary: nil, resultEmoji: nil, resultMatch: nil,
                    imageURL: nil)
    }

    static func quizCard(quizId: String) -> ChatMessage {
        ChatMessage(id: UUID().uuidString, kind: .quiz, senderId: nil,
                    createdAt: Date(), readBy: [],
                    text: nil, quizId: quizId,
                    resultSummary: nil, resultEmoji: nil, resultMatch: nil,
                    imageURL: nil)
    }

    static func resultCard(quiz: ChatQuiz, result: ChatQuizResult) -> ChatMessage {
        // Takes the whole quiz and the whole result rather than a few of their
        // fields. The previous signature spelled out summary/emoji/match, so
        // when the verdict was added to `ChatQuizResult` it simply never
        // reached the message, and nothing failed to compile.
        ChatMessage(id: UUID().uuidString, kind: .result, senderId: nil,
                    createdAt: Date(), readBy: [],
                    text: nil, quizId: quiz.id,
                    resultSummary: result.summary,
                    resultEmoji: result.emoji,
                    resultMatch: result.match,
                    imageURL: nil,
                    resultKind: result.kind?.rawValue,
                    resultOptionRef: result.sharedOptionId.map {
                        QuizOptionRef.make(questionId: quiz.questionId, optionId: $0)
                    },
                    resultOptionLabel: result.sharedOptionLabel,
                    resultTopic: quiz.topic.rawValue)
    }

    static func photo(_ url: String, senderId: String) -> ChatMessage {
        ChatMessage(id: UUID().uuidString, kind: .photo, senderId: senderId,
                    createdAt: Date(), readBy: [senderId],
                    text: nil, quizId: nil,
                    resultSummary: nil, resultEmoji: nil, resultMatch: nil,
                    imageURL: url)
    }
}

// MARK: - Chat Quiz

enum ChatQuizStatus: String, Codable {
    case pending       // no one has answered
    case partial       // one partner answered
    case complete      // both answered, result posted
}

struct ChatQuizAnswer: Codable, Equatable {
    /// Display text of the picked option(s), in the language the writing
    /// device happened to be running. Kept because documents written before
    /// `optionIds` existed carry only this, and because a build already on
    /// the App Store still reads it.
    ///
    /// Never compare this field. Two partners on different locales store
    /// different strings for the same choice. Go through
    /// `ChatQuiz.stableIds(for:)`.
    let options: [String]

    /// Stable, language-independent ids for the same picks.
    ///
    /// Optional, and it has to stay optional: every document written before
    /// this field existed lacks it, and all of this app's Firestore reads are
    /// `try? doc.data(as:)`, which turns a decode failure into a silently
    /// missing quiz rather than an error anyone would notice.
    var optionIds: [String]? = nil

    let text: String?
    let answeredAt: Date

    /// What this user predicted their partner would pick, as display text.
    /// Optional because free-text questions cannot be guessed against, because
    /// the guess step is skippable, and because answers written before it
    /// existed have none. Legacy counterpart of `guessIds`; do not compare it.
    var guess: [String]? = nil

    /// Stable ids for the prediction. Same optionality reasoning as
    /// `optionIds`.
    var guessIds: [String]? = nil
}

/// Why a quiz exists. Absent (nil) for every quiz posted from the Chat tab —
/// curated, AI-suggested, or custom — so existing documents keep decoding.
enum ChatQuizKind: String, Codable {
    /// Generated once per day per couple and surfaced on the Home tab.
    case questionOfTheDay = "qotd"
}

/// A quiz instance posted into the chat. The question body itself comes from
/// the curated bank (or AI) and is identified by `questionId`.
///
/// `authorId` is non-nil only for user-authored *custom* quizzes — the renderer
/// uses its presence to switch on a "Custom from {name}" badge. Curated /
/// AI-suggested quizzes leave it nil.
///
/// `customNote` is the optional romantic note attached to a custom quiz. It's
/// rendered on the quiz card above the question, and again at the top of the
/// answer sheet, so the recipient sees the personal touch before the question.
struct ChatQuiz: Identifiable, Codable, Equatable {
    @DocumentID var firestoreId: String?
    let id: String
    let questionId: String
    let topic: QuizTopic
    let question: String            // denormalized for fast render
    let subtitle: String
    let options: [String]           // multiple-choice options, [] for free text
    /// Stable ids parallel to `options`, same order. Lets a reader resolve an
    /// answer even when its own bank wording has moved on, and lets the
    /// labels be translated without changing what was stored. Optional for
    /// documents written before it existed.
    var optionIds: [String]? = nil
    let allowsMultiple: Bool
    let createdAt: Date
    var status: ChatQuizStatus
    var answers: [String: ChatQuizAnswer]    // keyed by userId

    // Populated once both answered
    var result: ChatQuizResult?

    // Custom quiz fields — both nil for curated/AI quizzes.
    /// Author of this quiz (only set for user-authored custom quizzes).
    var authorId: String?
    /// Author's "correct" answer (their own pick). When the partner picks
    /// matching options, the result card celebrates a match.
    var authorAnswer: [String]?
    /// Optional romantic note attached to a custom quiz.
    var customNote: String?

    // Question of the Day fields — both nil for chat quizzes.
    /// Non-nil only for the automatically generated daily question. Lets the
    /// Home card query for it and lets the server push distinguish it from a
    /// quiz a partner deliberately sent.
    var kind: ChatQuizKind? = nil
    /// The user whose client materialised this QotD. *Not* an author — the
    /// question comes from the curated bank, this is just whoever opened the
    /// app first today. The server uses it to push the *other* partner.
    var triggeredBy: String? = nil

    /// How each partner reacted to the finished result, keyed by userId and
    /// holding a `ReactionKind` raw value. Stored on the quiz rather than in
    /// a subcollection: there are at most two, the existing quiz listener
    /// already streams this document, and the quiz rules already let couple
    /// members update it.
    var reactions: [String: String]? = nil

    var isCustom: Bool { authorId != nil }

    func reaction(of userId: String) -> ReactionKind? {
        guard let raw = reactions?[userId] else { return nil }
        return ReactionKind(rawValue: raw)
    }

    /// Also recognised by its document id: a partner on 1.1 who answers the
    /// daily question from chat rewrites the document without `kind`.
    var isQuestionOfTheDay: Bool { kind == .questionOfTheDay || id.hasPrefix("qotd-") }

    func answer(for userId: String) -> ChatQuizAnswer? {
        answers[userId]
    }

    func hasAnswered(_ userId: String) -> Bool {
        answers[userId] != nil
    }

    func bothAnswered(userIds: [String]) -> Bool {
        userIds.allSatisfy { answers[$0] != nil }
    }
}

/// Which sentence the result card should say. Storing the *shape* of the
/// verdict instead of the finished sentence is what lets each partner read it
/// in their own language: the writer still decides the verdict, but the
/// reader renders it.
enum QuizResultKind: String, Codable {
    /// Both landed on the same option, and `sharedOptionId` names it.
    case matchShared
    /// They agreed, but on free text, so there is no option to name.
    case matchGeneric
    /// They differed.
    case mismatch
}

struct ChatQuizResult: Codable, Equatable {
    let match: Bool                 // did the answers align?

    /// The finished sentence, in the language of whichever device happened to
    /// answer second. Legacy: written for builds that cannot render `kind`,
    /// and the only thing documents from before `kind` existed contain.
    let summary: String             // "You both value quality time ❤️"

    let emoji: String

    /// Write-only since it was added: nothing in the app, the widget or the
    /// Cloud Functions reads it. Its keys are the literals "userA"/"userB",
    /// bound to viewer-and-partner at the call site, so the same key means a
    /// different person depending on which device won the write — which is
    /// why it is unusable as stored. Kept so existing documents decode.
    let traits: [String: String]

    /// Both stamped by the service inside the transaction. `var`, not `let`,
    /// on purpose: the service used to re-construct the whole struct through
    /// the memberwise initializer just to set these two, which silently
    /// dropped every field added afterwards — the defaulted parameters meant
    /// the compiler had nothing to complain about. Mutating in place makes
    /// that class of omission impossible.
    var postedAt: Date
    var postedByClientId: String    // arbitration token (tx-safe idempotency)

    /// The verdict's shape. Optional for documents written before it existed;
    /// when nil, readers fall back to `summary`.
    var kind: QuizResultKind? = nil

    /// For `.matchShared` on a bank-backed quiz: the stable id of the option
    /// they shared, so the reader can name it in their own language.
    var sharedOptionId: String? = nil

    /// For `.matchShared`: the shared option's BASE-LANGUAGE label, written
    /// for every quiz and not just custom ones.
    ///
    /// Two jobs. For a custom quiz it is the author's own words, which are
    /// never translated and so are the right thing to store. For a bank quiz
    /// it is the fallback a reader uses when it cannot resolve
    /// `sharedOptionId` — an option the bank has since dropped, or a build
    /// whose bank is older than the writer's.
    var sharedOptionLabel: String? = nil
}

// MARK: - Couple Insight Profile

/// A single aggregated view of everything the couple has revealed via quizzes.
/// Used for the Couple Profile screen and as input to AI.
struct CoupleInsightProfile: Codable, Equatable {
    var updatedAt: Date
    var confidenceScore: Int                       // 0–100
    var topics: [String: TopicInsight]             // keyed by QuizTopic.rawValue

    static let empty = CoupleInsightProfile(
        updatedAt: Date(),
        confidenceScore: 0,
        topics: [:]
    )

    struct TopicInsight: Codable, Equatable {
        var answeredCount: Int                     // number of quizzes answered in topic
        var userA: PartnerTrait?
        var userB: PartnerTrait?

        /// Legacy display text, accumulated by union across every quiz in the
        /// topic. This field is the reason the profile document needed fixing
        /// rather than just the renderer: it is written with `union`, so once
        /// an option's wording changed, both spellings of the same concept
        /// stayed in here forever and no later code change could tell them
        /// apart. Still written so an older build has something to draw.
        var sharedTraits: [String]
        var differences: [String]

        /// `questionId.optionId` references for the same two sets. Option ids
        /// are scoped to their template, so an aggregate spanning many
        /// quizzes has to carry both halves to stay resolvable.
        ///
        /// Optional for documents written before they existed.
        var sharedTraitRefs: [String]? = nil
        var differenceRefs: [String]? = nil

        var lastUpdatedAt: Date

        static let empty = TopicInsight(
            answeredCount: 0, userA: nil, userB: nil,
            sharedTraits: [], differences: [], lastUpdatedAt: Date()
        )
    }

    struct PartnerTrait: Codable, Equatable {
        let userId: String
        /// Legacy joined display text. Kept for older builds and for profiles
        /// written before `summaryRefs`.
        var summary: String           // "Prefers quality time"
        var confidence: Int           // 0–100
        var sampleQuizIds: [String]
        /// `questionId.optionId` references behind `summary`, so the line can
        /// be rendered in the reader's language. Nil for free-text answers,
        /// where `summary` is the user's own words and is correct as stored.
        var summaryRefs: [String]? = nil
    }
}

// MARK: - Quiz option references

/// A `questionId.optionId` pair, flattened to one string so it can live in a
/// Firestore array.
///
/// Option ids are only unique inside their own template, so anything that
/// aggregates picks across different questions — the couple insight profile —
/// has to keep the question with the option or it cannot resolve a label
/// later.
enum QuizOptionRef {

    static func make(questionId: String, optionId: String) -> String {
        "\(questionId).\(optionId)"
    }

    /// Splits on the FIRST dot only: a custom quiz uses the author's own text
    /// as its option id, and that text may well contain a full stop.
    static func split(_ ref: String) -> (questionId: String, optionId: String)? {
        let parts = ref.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return (String(parts[0]), String(parts[1]))
    }

    /// The label to DRAW for a ref: the bank's, in the reader's language, or
    /// the option id itself when there is no bank entry — which is the right
    /// answer for a custom quiz, where the id *is* the author's wording.
    static func label(_ ref: String) -> String? {
        guard let (questionId, optionId) = split(ref) else { return nil }
        if let template = ChatQuizBank.byId(questionId) {
            return template.option(id: optionId)?.displayLabel ?? optionId
        }
        return optionId
    }

    /// The base-language label, for deduping against stored text written by
    /// another device or an older build.
    static func baseLabel(_ ref: String) -> String? {
        guard let (questionId, optionId) = split(ref) else { return nil }
        if let template = ChatQuizBank.byId(questionId) {
            return template.option(id: optionId)?.label ?? optionId
        }
        return optionId
    }
}
