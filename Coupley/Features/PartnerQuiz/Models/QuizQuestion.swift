//
//  QuizQuestion.swift
//  Coupley
//
//  Created by Sam Manh Cuong on 1/4/26.
//

import Foundation

// MARK: - Question Category

enum QuestionCategory: String, CaseIterable, Codable {
    case food
    case drink
    case music
    case activities
    case color
    case loveLanguage
    case stressBehavior
    case communicationStyle

    var label: String {
        switch self {
        case .food: return "Food"
        case .drink: return "Drinks"
        case .music: return "Music"
        case .activities: return "Activities"
        case .color: return "Colors"
        case .loveLanguage: return "Love Language"
        case .stressBehavior: return "Stress"
        case .communicationStyle: return "Communication"
        }
    }

    var emoji: String {
        switch self {
        case .food: return "🍜"
        case .drink: return "🧋"
        case .music: return "🎵"
        case .activities: return "🎯"
        case .color: return "🎨"
        case .loveLanguage: return "💕"
        case .stressBehavior: return "😮‍💨"
        case .communicationStyle: return "💬"
        }
    }
}

// MARK: - Input Type

enum QuizInputType: Equatable {
    case freeText(placeholder: String)
    case multipleChoice(options: [String])
}

// MARK: - Quiz Question

struct QuizQuestion: Identifiable {
    let id: UUID
    let question: String
    let subtitle: String
    let category: QuestionCategory
    let inputType: QuizInputType
    let allowsMultiple: Bool

    init(
        id: UUID = UUID(),
        question: String,
        subtitle: String = "",
        category: QuestionCategory,
        inputType: QuizInputType,
        allowsMultiple: Bool = false
    ) {
        self.id = id
        self.question = question
        self.subtitle = subtitle
        self.category = category
        self.inputType = inputType
        self.allowsMultiple = allowsMultiple
    }
}

// MARK: - Quiz Answer

struct QuizAnswer: Equatable {
    var textValues: [String]
    var selectedOptions: Set<String>

    static let empty = QuizAnswer(textValues: [], selectedOptions: [])

    var isEmpty: Bool {
        textValues.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
            && selectedOptions.isEmpty
    }

    var allValues: [String] {
        let text = textValues
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return text + Array(selectedOptions)
    }
}

// MARK: - Question Bank

enum QuizBank {

    static func allQuestions(partnerName: String) -> [QuizQuestion] {
        let name = partnerName.isEmpty ? "your partner" : partnerName

        return [
            QuizQuestion(
                question: "What does \(name) love to eat?",
                subtitle: "Their go-to comfort food, favorite cuisine, guilty pleasures...",
                category: .food,
                inputType: .freeText(placeholder: "e.g. Sushi, Tacos, Chocolate cake"),
                allowsMultiple: true
            ),
            QuizQuestion(
                question: "What's \(name)'s favorite drink?",
                subtitle: "Morning coffee? Boba obsession? Smoothie person?",
                category: .drink,
                inputType: .freeText(placeholder: "e.g. Matcha latte, Iced tea"),
                allowsMultiple: true
            ),
            QuizQuestion(
                question: "What music makes \(name) happy?",
                subtitle: "Genres, artists, vibes — anything goes!",
                category: .music,
                inputType: .multipleChoice(options: [
                    "Pop", "R&B", "Lo-fi", "Hip-Hop",
                    "Rock", "Acoustic", "Jazz", "K-Pop",
                    "Classical", "EDM", "Country", "Indie"
                ]),
                allowsMultiple: true
            ),
            QuizQuestion(
                question: "Pick \(name)'s ideal weekend activities",
                subtitle: "What would they do with a totally free day?",
                category: .activities,
                inputType: .multipleChoice(options: [
                    "Hiking", "Movie marathon", "Cooking together",
                    "Gaming", "Reading", "Shopping",
                    "Trying new restaurants", "Beach day",
                    "Staying in bed", "Road trip",
                    "Working out", "Art / Museum"
                ]),
                allowsMultiple: true
            ),
            QuizQuestion(
                question: "What's \(name)'s favorite color?",
                subtitle: "The one they gravitate toward for clothes, decor, everything",
                category: .color,
                inputType: .multipleChoice(options: [
                    "Red", "Blue", "Green", "Purple",
                    "Pink", "Black", "White", "Yellow",
                    "Orange", "Sage green", "Navy", "Lavender"
                ])
            ),
            QuizQuestion(
                question: "How does \(name) feel most loved?",
                subtitle: "Everyone has a primary love language",
                category: .loveLanguage,
                inputType: .multipleChoice(options:
                    LoveLanguage.allCases.map { "\($0.emoji) \($0.label)" }
                )
            ),
            QuizQuestion(
                question: "When \(name) is stressed, they usually...",
                subtitle: "Knowing this helps us suggest the right support",
                category: .stressBehavior,
                inputType: .multipleChoice(options:
                    StressResponse.allCases.map { "\($0.emoji) \($0.label)" }
                )
            ),
            QuizQuestion(
                question: "How does \(name) prefer to communicate?",
                subtitle: "Their natural style when things get real",
                category: .communicationStyle,
                inputType: .multipleChoice(options:
                    CommunicationStyle.allCases.map { "\($0.emoji) \($0.label)" }
                )
            ),
        ]
    }
}
