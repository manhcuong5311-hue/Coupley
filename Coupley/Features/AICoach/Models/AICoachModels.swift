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

    /// English name. MockAICoachService (the English-only offline fallback)
    /// splices it into its own sentences, so it must not follow the user's
    /// language. The UI uses `displayLabel`.
    var label: String {
        switch self {
        case .secure:          return "Secure"
        case .anxious:         return "Anxious"
        case .avoidant:        return "Avoidant"
        case .fearfulAvoidant: return "Fearful Avoidant"
        }
    }

    /// The name shown in the UI, in the user's language.
    var displayLabel: LocalizedStringResource {
        switch self {
        case .secure:          return LocalizedStringResource("Secure", comment: "Attachment style name")
        case .anxious:         return LocalizedStringResource("Anxious", comment: "Attachment style name")
        case .avoidant:        return LocalizedStringResource("Avoidant", comment: "Attachment style name")
        case .fearfulAvoidant: return LocalizedStringResource("Fearful Avoidant", comment: "Attachment style name")
        }
    }

    var shortDescription: LocalizedStringResource {
        switch self {
        case .secure:          return LocalizedStringResource("Comfortable with closeness and independence", comment: "Description of the 'Secure' attachment style")
        case .anxious:         return LocalizedStringResource("Needs reassurance, fears distance", comment: "Description of the 'Anxious' attachment style")
        case .avoidant:        return LocalizedStringResource("Values independence, needs space under pressure", comment: "Description of the 'Avoidant' attachment style")
        case .fearfulAvoidant: return LocalizedStringResource("Wants closeness but fears being hurt", comment: "Description of the 'Fearful Avoidant' attachment style")
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

    /// Display only: the backend receives `rawValue`.
    var label: LocalizedStringResource {
        switch self {
        case .overthinker:           return LocalizedStringResource("Overthinker", comment: "Personality pattern")
        case .emotionallyExpressive: return LocalizedStringResource("Emotionally expressive", comment: "Personality pattern")
        case .shutsDown:             return LocalizedStringResource("Shuts down during conflict", comment: "Personality pattern")
        case .highlySensitive:       return LocalizedStringResource("Highly sensitive", comment: "Personality pattern")
        case .needsReassurance:      return LocalizedStringResource("Needs reassurance", comment: "Personality pattern")
        case .avoidsConfrontation:   return LocalizedStringResource("Avoids confrontation", comment: "Personality pattern")
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

    /// English title. It is DATA: `AICoachViewModel.runGuidedFlow` stores it
    /// as the text of the `.systemPrompt` message that opens a guided flow,
    /// which is persisted in UserDefaults and sent to the coach backend with
    /// the transcript. It must stay English and unchanged; the UI shows
    /// `displayTitle`, and `matching(storedTitle:)` maps a stored message back.
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

    /// The title shown in the UI, in the user's language.
    var displayTitle: LocalizedStringResource {
        switch self {
        case .fight:         return LocalizedStringResource("We had a fight", comment: "Coach issue the user picks, in their own voice")
        case .distance:      return LocalizedStringResource("My partner feels distant", comment: "Coach issue the user picks, in their own voice")
        case .apology:       return LocalizedStringResource("I need help apologizing", comment: "Coach issue the user picks, in their own voice")
        case .reconnect:     return LocalizedStringResource("I want to reconnect", comment: "Coach issue the user picks, in their own voice")
        case .stress:        return LocalizedStringResource("Stress & emotional support", comment: "Coach issue the user picks")
        case .trust:         return LocalizedStringResource("Trust issues", comment: "Coach issue the user picks")
        case .communication: return LocalizedStringResource("Communication problems", comment: "Coach issue the user picks")
        case .custom:        return LocalizedStringResource("Custom situation", comment: "Coach issue the user picks: describe your own situation")
        }
    }

    /// The issue whose English `title` is `storedTitle`, so a persisted
    /// `.systemPrompt` message can be shown in the user's language.
    static func matching(storedTitle: String) -> CoachIssueType? {
        allCases.first { $0.title == storedTitle }
    }

    var subtitle: LocalizedStringResource {
        switch self {
        case .fight:         return LocalizedStringResource("Work through an argument", comment: "Subtitle of a coach issue card")
        case .distance:      return LocalizedStringResource("Rebuild closeness", comment: "Subtitle of a coach issue card")
        case .apology:       return LocalizedStringResource("Say it the right way", comment: "Subtitle of a coach issue card")
        case .reconnect:     return LocalizedStringResource("Feel close again", comment: "Subtitle of a coach issue card")
        case .stress:        return LocalizedStringResource("Show up when it's hard", comment: "Subtitle of a coach issue card")
        case .trust:         return LocalizedStringResource("Repair after a breach", comment: "Subtitle of a coach issue card: rebuild trust after it was broken")
        case .communication: return LocalizedStringResource("Be heard, understand each other", comment: "Subtitle of a coach issue card")
        case .custom:        return LocalizedStringResource("Describe what's going on", comment: "Subtitle of a coach issue card")
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

    /// Smart context questions the coach asks on entry. Display only.
    var contextQuestions: [LocalizedStringResource] {
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

    /// The placeholder names are sent to the coach backend (and used by the
    /// English mock) as data, so they stay English.
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

        var label: LocalizedStringResource {
            switch self {
            case .soft:   return LocalizedStringResource("Softer", comment: "Rewrite tone: a kinder, less defensive version of the message")
            case .honest: return LocalizedStringResource("Honest", comment: "Rewrite tone: a direct but warm version of the message")
            case .repair: return LocalizedStringResource("Repair", comment: "Rewrite tone (noun): a version that owns your part and makes amends")
            }
        }

        var description: LocalizedStringResource {
            switch self {
            case .soft:   return LocalizedStringResource("Kinder, less defensive", comment: "Description of the 'Softer' rewrite tone")
            case .honest: return LocalizedStringResource("Direct but warm", comment: "Description of the 'Honest' rewrite tone")
            case .repair: return LocalizedStringResource("Owning your part", comment: "Description of the 'Repair' rewrite tone: taking responsibility for your share")
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

        var label: LocalizedStringResource {
            switch self {
            case .trust:             return LocalizedStringResource("Trust", comment: "Relationship health pillar")
            case .communication:     return LocalizedStringResource("Communication", comment: "Relationship health pillar")
            case .emotionalIntimacy: return LocalizedStringResource("Emotional Intimacy", comment: "Relationship health pillar")
            case .support:           return LocalizedStringResource("Support", comment: "Relationship health pillar (noun): supporting each other")
            case .consistency:       return LocalizedStringResource("Consistency", comment: "Relationship health pillar")
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
        var label: LocalizedStringResource {
            switch self {
            case .threeDay: return LocalizedStringResource("3-day plan", comment: "Recovery plan length option")
            case .sevenDay: return LocalizedStringResource("7-day plan", comment: "Recovery plan length option")
            }
        }
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
