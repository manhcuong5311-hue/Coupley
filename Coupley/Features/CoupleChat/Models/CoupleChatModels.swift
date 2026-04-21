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

    static func text(_ body: String, senderId: String) -> ChatMessage {
        ChatMessage(id: UUID().uuidString, kind: .text, senderId: senderId,
                    createdAt: Date(), readBy: [senderId],
                    text: body, quizId: nil,
                    resultSummary: nil, resultEmoji: nil, resultMatch: nil)
    }

    static func system(_ body: String) -> ChatMessage {
        ChatMessage(id: UUID().uuidString, kind: .system, senderId: nil,
                    createdAt: Date(), readBy: [],
                    text: body, quizId: nil,
                    resultSummary: nil, resultEmoji: nil, resultMatch: nil)
    }

    static func quizCard(quizId: String) -> ChatMessage {
        ChatMessage(id: UUID().uuidString, kind: .quiz, senderId: nil,
                    createdAt: Date(), readBy: [],
                    text: nil, quizId: quizId,
                    resultSummary: nil, resultEmoji: nil, resultMatch: nil)
    }

    static func resultCard(quizId: String, summary: String, emoji: String, match: Bool) -> ChatMessage {
        ChatMessage(id: UUID().uuidString, kind: .result, senderId: nil,
                    createdAt: Date(), readBy: [],
                    text: nil, quizId: quizId,
                    resultSummary: summary, resultEmoji: emoji, resultMatch: match)
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
