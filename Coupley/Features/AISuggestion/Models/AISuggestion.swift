//
//  AISuggestion.swift
//  Coupley
//
//  Created by Sam Manh Cuong on 1/4/26.
//

import Foundation

// MARK: - Message Suggestion

struct MessageSuggestion: Identifiable, Equatable {
    let id: UUID
    let text: String
    let tone: MessageTone

    init(id: UUID = UUID(), text: String, tone: MessageTone) {
        self.id = id
        self.text = text
        self.tone = tone
    }
}

// MARK: - Message Tone

enum MessageTone: String, Codable {
    case warm
    case playful
    case supportive

    var label: String {
        rawValue.capitalized
    }

    var icon: String {
        switch self {
        case .warm: return "heart.fill"
        case .playful: return "face.smiling.fill"
        case .supportive: return "hand.raised.fill"
        }
    }
}

// MARK: - Action Suggestion

struct ActionSuggestion: Identifiable, Equatable {
    let id: UUID
    let title: String
    let description: String
    let icon: String
    var isCompleted: Bool

    init(
        id: UUID = UUID(),
        title: String,
        description: String,
        icon: String = "sparkles",
        isCompleted: Bool = false
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.icon = icon
        self.isCompleted = isCompleted
    }
}

// MARK: - AI Suggestion Result

struct AISuggestionResult: Equatable {
    let messages: [MessageSuggestion]
    let action: ActionSuggestion
    let generatedAt: Date

    init(
        messages: [MessageSuggestion],
        action: ActionSuggestion,
        generatedAt: Date = Date()
    ) {
        self.messages = messages
        self.action = action
        self.generatedAt = generatedAt
    }
}
