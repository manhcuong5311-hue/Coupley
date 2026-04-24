//
//  AICoachModels.swift
//  Coupley
//
//  Data models for the AI Relationship Coach feature.
//

import Foundation

// MARK: - Attachment Style

enum AttachmentStyle: String, CaseIterable, Identifiable, Codable {
    case secure
    case anxious
    case avoidant
    case fearfulAvoidant

    var id: String { rawValue }

    var label: String {
        switch self {
        case .secure:          return "Secure"
        case .anxious:         return "Anxious"
        case .avoidant:        return "Avoidant"
        case .fearfulAvoidant: return "Fearful Avoidant"
        }
    }

    var shortDescription: String {
        switch self {
        case .secure:          return "Comfortable with closeness and independence"
        case .anxious:         return "Needs reassurance, fears distance"
        case .avoidant:        return "Values independence, needs space under pressure"
        case .fearfulAvoidant: return "Wants closeness but fears being hurt"
        }
    }

    var emoji: String {
        switch self {
        case .secure:          return "🌿"
        case .anxious:         return "💭"
        case .avoidant:        return "🏔"
        case .fearfulAvoidant: return "🌊"
        }
    }
}

// MARK: - Personality Pattern

enum PersonalityPattern: String, CaseIterable, Identifiable, Codable {
    case overthinker
    case emotionallyExpressive
    case shutsDown
    case highlySensitive
    case needsReassurance
    case avoidsConfrontation

    var id: String { rawValue }

    var label: String {
        switch self {
        case .overthinker:           return "Overthinker"
        case .emotionallyExpressive: return "Emotionally expressive"
        case .shutsDown:             return "Shuts down during conflict"
        case .highlySensitive:       return "Highly sensitive"
        case .needsReassurance:      return "Needs reassurance"
        case .avoidsConfrontation:   return "Avoids confrontation"
        }
    }
}

// MARK: - Coach Issue Type

enum CoachIssueType: String, CaseIterable, Identifiable, Codable {
    case fight
    case distance
    case apology
    case reconnect
    case stress
    case trust
    case communication
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fight:         return "We had a fight"
        case .distance:      return "My partner feels distant"
        case .apology:       return "I need help apologizing"
        case .reconnect:     return "I want to reconnect"
        case .stress:        return "Stress & emotional support"
        case .trust:         return "Trust issues"
        case .communication: return "Communication problems"
        case .custom:        return "Custom situation"
        }
    }

    var subtitle: String {
        switch self {
        case .fight:         return "Work through an argument"
        case .distance:      return "Rebuild closeness"
        case .apology:       return "Say it the right way"
        case .reconnect:     return "Feel close again"
        case .stress:        return "Show up when it's hard"
        case .trust:         return "Repair after a breach"
        case .communication: return "Be heard, understand each other"
        case .custom:        return "Describe what's going on"
        }
    }

    var icon: String {
        switch self {
        case .fight:         return "flame.fill"
        case .distance:      return "moon.stars.fill"
        case .apology:       return "heart.text.square.fill"
        case .reconnect:     return "link.circle.fill"
        case .stress:        return "leaf.fill"
        case .trust:         return "lock.shield.fill"
        case .communication: return "bubble.left.and.bubble.right.fill"
        case .custom:        return "sparkles"
        }
    }

    var tint: CoachTint {
        switch self {
        case .fight:         return .warm
        case .distance:      return .cool
        case .apology:       return .rose
        case .reconnect:     return .rose
        case .stress:        return .sage
        case .trust:         return .indigo
        case .communication: return .cool
        case .custom:        return .neutral
        }
    }

    /// Smart context questions the coach asks on entry.
    var contextQuestions: [String] {
        switch self {
        case .fight:
            return [
                "What happened?",
                "How did your partner react?",
                "Is this a repeated issue?"
            ]
        case .distance:
            return [
                "When did you first notice the distance?",
                "What was happening in their life then?",
                "How have you tried to reach out?"
            ]
        case .apology:
            return [
                "What do you want to apologize for?",
                "How did they say they felt?",
                "What outcome would feel right for both of you?"
            ]
        case .reconnect:
            return [
                "When did you last feel truly close?",
                "What changed between then and now?",
                "What do you miss most right now?"
            ]
        case .stress:
            return [
                "What's weighing on your partner?",
                "How do they usually want support — space, talk, or action?",
                "What have you tried so far?"
            ]
        case .trust:
            return [
                "What happened that hurt the trust?",
                "Has this pattern shown up before?",
                "What would repair look like for you?"
            ]
        case .communication:
            return [
                "What do you wish they understood?",
                "Where do conversations usually break down?",
                "What do you need from them right now?"
            ]
        case .custom:
            return [
                "Tell me what's going on — in your own words.",
                "How are you feeling about it right now?",
                "What do you hope comes out of this conversation?"
            ]
        }
    }
}

// MARK: - Coach Tint

enum CoachTint: String, Codable {
    case warm, cool, rose, sage, indigo, neutral
}

// MARK: - Coach Context

/// Everything we know about the user + couple, fed into the model to
/// personalize every response. Derived from profile, mood history, and
/// any context the user has explicitly shared.
struct CoachContext: Codable, Equatable {
    var myName: String
    var partnerName: String
    var attachmentStyle: AttachmentStyle?
    var partnerAttachmentStyle: AttachmentStyle?
    var loveLanguage: LoveLanguage?
    var partnerLoveLanguage: LoveLanguage?
    var communicationStyle: CommunicationStyle?
    var partnerCommunicationStyle: CommunicationStyle?
    var personalityPatterns: [PersonalityPattern]
    var partnerPersonalityPatterns: [PersonalityPattern]
    var recentMoodNote: String?
    var recurringThemes: [String]

    static let empty = CoachContext(
        myName: "You",
        partnerName: "Partner",
        attachmentStyle: nil,
        partnerAttachmentStyle: nil,
        loveLanguage: nil,
        partnerLoveLanguage: nil,
        communicationStyle: nil,
        partnerCommunicationStyle: nil,
        personalityPatterns: [],
        partnerPersonalityPatterns: [],
        recentMoodNote: nil,
        recurringThemes: []
    )
}

// MARK: - Chat Message

struct CoachChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let role: Role
    let text: String
    let guided: GuidedResponse?
    let sentAt: Date

    enum Role: String, Codable {
        case user
        case coach
        case systemPrompt
    }

    init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        guided: GuidedResponse? = nil,
        sentAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.guided = guided
        self.sentAt = sentAt
    }
}

// MARK: - Guided Response (Structured Coaching Output)

/// Structured reply produced at the end of a guided coaching flow.
/// Rendered as a rich card in the chat transcript.
struct GuidedResponse: Codable, Equatable {
    let situationAnalysis: String
    let partnerPerspective: String
    let bestNextAction: String
    let whatNotToDo: String
    let suggestedMessage: String
    let longTermAdvice: String
    let issue: CoachIssueType
}

// MARK: - Chat Session (persisted in UserDefaults)

struct CoachChatSession: Codable, Equatable {
    var messages: [CoachChatMessage]
    var activeIssue: CoachIssueType?
    var updatedAt: Date

    static let empty = CoachChatSession(
        messages: [],
        activeIssue: nil,
        updatedAt: .distantPast
    )
}

// MARK: - Message Rewrite

struct MessageRewrite: Identifiable, Codable, Equatable {
    let id: UUID
    let original: String
    let rewritten: String
    let tone: Tone

    enum Tone: String, CaseIterable, Codable, Identifiable {
        case soft, honest, repair

        var id: String { rawValue }

        var label: String {
            switch self {
            case .soft:   return "Softer"
            case .honest: return "Honest"
            case .repair: return "Repair"
            }
        }

        var description: String {
            switch self {
            case .soft:   return "Kinder, less defensive"
            case .honest: return "Direct but warm"
            case .repair: return "Owning your part"
            }
        }

        var icon: String {
            switch self {
            case .soft:   return "leaf.fill"
            case .honest: return "bubble.left.fill"
            case .repair: return "heart.circle.fill"
            }
        }
    }

    init(id: UUID = UUID(), original: String, rewritten: String, tone: Tone) {
        self.id = id
        self.original = original
        self.rewritten = rewritten
        self.tone = tone
    }
}

// MARK: - Relationship Health

struct RelationshipHealth: Codable, Equatable {
    let trust: Int
    let communication: Int
    let emotionalIntimacy: Int
    let support: Int
    let consistency: Int
    let summary: String
    let redFlags: [String]
    let generatedAt: Date

    var overall: Int {
        (trust + communication + emotionalIntimacy + support + consistency) / 5
    }

    static let placeholder = RelationshipHealth(
        trust: 0,
        communication: 0,
        emotionalIntimacy: 0,
        support: 0,
        consistency: 0,
        summary: "",
        redFlags: [],
        generatedAt: .distantPast
    )
}

extension RelationshipHealth {

    enum Pillar: CaseIterable {
        case trust, communication, emotionalIntimacy, support, consistency

        var label: String {
            switch self {
            case .trust:             return "Trust"
            case .communication:     return "Communication"
            case .emotionalIntimacy: return "Emotional Intimacy"
            case .support:           return "Support"
            case .consistency:       return "Consistency"
            }
        }

        var icon: String {
            switch self {
            case .trust:             return "lock.shield.fill"
            case .communication:     return "bubble.left.and.bubble.right.fill"
            case .emotionalIntimacy: return "heart.fill"
            case .support:           return "hands.sparkles.fill"
            case .consistency:       return "arrow.triangle.2.circlepath"
            }
        }
    }

    func score(for pillar: Pillar) -> Int {
        switch pillar {
        case .trust:             return trust
        case .communication:     return communication
        case .emotionalIntimacy: return emotionalIntimacy
        case .support:           return support
        case .consistency:       return consistency
        }
    }
}

// MARK: - Recovery Plan

struct RecoveryPlan: Codable, Equatable, Identifiable {
    var id: UUID
    let length: Length
    let title: String
    let intro: String
    let days: [Day]
    let generatedAt: Date

    enum Length: String, CaseIterable, Codable, Identifiable {
        case threeDay, sevenDay

        var id: String { rawValue }
        var dayCount: Int { self == .threeDay ? 3 : 7 }
        var label: String { self == .threeDay ? "3-day plan" : "7-day plan" }
    }

    struct Day: Codable, Equatable, Identifiable {
        let id: UUID
        let dayNumber: Int
        let theme: String
        let actions: [String]
        let message: String

        init(id: UUID = UUID(), dayNumber: Int, theme: String, actions: [String], message: String) {
            self.id = id
            self.dayNumber = dayNumber
            self.theme = theme
            self.actions = actions
            self.message = message
        }
    }

    init(
        id: UUID = UUID(),
        length: Length,
        title: String,
        intro: String,
        days: [Day],
        generatedAt: Date = Date()
    ) {
        self.id = id
        self.length = length
        self.title = title
        self.intro = intro
        self.days = days
        self.generatedAt = generatedAt
    }
}
