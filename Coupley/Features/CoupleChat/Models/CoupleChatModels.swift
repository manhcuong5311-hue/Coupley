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

    var label: String {
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
    let resultSummary: String?
    let resultEmoji: String?
    let resultMatch: Bool?
    let imageURL: String?       // only set for .photo messages

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

    static func resultCard(quizId: String, summary: String, emoji: String, match: Bool) -> ChatMessage {
        ChatMessage(id: UUID().uuidString, kind: .result, senderId: nil,
                    createdAt: Date(), readBy: [],
                    text: nil, quizId: quizId,
                    resultSummary: summary, resultEmoji: emoji, resultMatch: match,
                    imageURL: nil)
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
    let options: [String]
    let text: String?
    let answeredAt: Date
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

    var isCustom: Bool { authorId != nil }

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

struct ChatQuizResult: Codable, Equatable {
    let match: Bool                 // did the answers align?
    let summary: String             // "You both value quality time ❤️"
    let emoji: String
    let traits: [String: String]    // keyed to topic-specific traits
    let postedAt: Date
    let postedByClientId: String    // arbitration token (tx-safe idempotency)
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
        var sharedTraits: [String]
        var differences: [String]
        var lastUpdatedAt: Date

        static let empty = TopicInsight(
            answeredCount: 0, userA: nil, userB: nil,
            sharedTraits: [], differences: [], lastUpdatedAt: Date()
        )
    }

    struct PartnerTrait: Codable, Equatable {
        let userId: String
        var summary: String           // "Prefers quality time"
        var confidence: Int           // 0–100
        var sampleQuizIds: [String]
    }
}
