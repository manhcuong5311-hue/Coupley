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

    /// Display only (the quiz header). A `String` because it is shown next
    /// to the category emoji.
    var label: String {
        switch self {
        case .food: return String(localized: "Food", comment: "Partner quiz category")
        case .drink: return String(localized: "Drinks", comment: "Partner quiz category")
        case .music: return String(localized: "Music", comment: "Partner quiz category")
        case .activities: return String(localized: "Activities", comment: "Partner quiz category")
        case .color: return String(localized: "Colors", comment: "Partner quiz category")
        case .loveLanguage: return String(localized: "Love Language", comment: "Partner quiz category")
        case .stressBehavior: return String(localized: "Stress", comment: "Partner quiz category: how the partner handles stress")
        case .communicationStyle: return String(localized: "Communication", comment: "Partner quiz category")
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
    case multipleChoice(options: [QuizOption])
}

// MARK: - Quiz Option

/// One multiple-choice answer.
///
/// `value` is the English base text. It is DATA: it is what the answer stores
/// (the profile's preferences and likes, which are sent to the AI) and what
/// `LocalProfileService` matches against, so it never follows the user's
/// language. `label` is what the chip shows.
struct QuizOption: Hashable {
    let value: String
    let label: String

    /// A content-bank option: English base text, shown through ContentL10n.
    static func content(_ base: String) -> QuizOption {
        QuizOption(value: base, label: ContentL10n.text(base))
    }
}

// MARK: - Quiz Question

/// `question`, `subtitle` and the free-text placeholder are display only
/// (never stored or compared), so they are localized where the bank builds
/// them.
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
    /// The chosen options' English base text (`QuizOption.value`).
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

    // Content-bank options: English base text, shown through ContentL10n.
    // Never translate these literals; see `QuizOption`.

    static let musicOptions = [
        "Pop", "R&B", "Lo-fi", "Hip-Hop",
        "Rock", "Acoustic", "Jazz", "K-Pop",
        "Classical", "EDM", "Country", "Indie"
    ]

    static let activityOptions = [
        "Hiking", "Movie marathon", "Cooking together",
        "Gaming", "Reading", "Shopping",
        "Trying new restaurants", "Beach day",
        "Staying in bed", "Road trip",
        "Working out", "Art / Museum"
    ]

    static let colorOptions = [
        "Red", "Blue", "Green", "Purple",
        "Pink", "Black", "White", "Yellow",
        "Orange", "Sage green", "Navy", "Lavender"
    ]

    /// Each question that names the partner has a second whole sentence for
    /// when no name was entered, so translators control the grammar of both
    /// instead of receiving "your partner" spliced into a frame.
    static func allQuestions(partnerName name: String) -> [QuizQuestion] {
        let named = !name.isEmpty

        return [
            QuizQuestion(
                question: named
                    ? String(localized: "What does \(name) love to eat?", comment: "Partner quiz question; the partner's name")
                    : String(localized: "What does your partner love to eat?", comment: "Partner quiz question"),
                subtitle: String(localized: "Their go-to comfort food, favorite cuisine, guilty pleasures..."),
                category: .food,
                inputType: .freeText(placeholder: String(localized: "e.g. Sushi, Tacos, Chocolate cake",
                                                         comment: "Placeholder of a free-text quiz answer; examples of foods")),
                allowsMultiple: true
            ),
            QuizQuestion(
                question: named
                    ? String(localized: "What's \(name)'s favorite drink?", comment: "Partner quiz question; the partner's name")
                    : String(localized: "What's your partner's favorite drink?", comment: "Partner quiz question"),
                subtitle: String(localized: "Morning coffee? Boba obsession? Smoothie person?"),
                category: .drink,
                inputType: .freeText(placeholder: String(localized: "e.g. Matcha latte, Iced tea",
                                                         comment: "Placeholder of a free-text quiz answer; examples of drinks")),
                allowsMultiple: true
            ),
            QuizQuestion(
                question: named
                    ? String(localized: "What music makes \(name) happy?", comment: "Partner quiz question; the partner's name")
                    : String(localized: "What music makes your partner happy?", comment: "Partner quiz question"),
                subtitle: String(localized: "Genres, artists, vibes — anything goes!"),
                category: .music,
                inputType: .multipleChoice(options: musicOptions.map { QuizOption.content($0) }),
                allowsMultiple: true
            ),
            QuizQuestion(
                question: named
                    ? String(localized: "Pick \(name)'s ideal weekend activities", comment: "Partner quiz question; the partner's name")
                    : String(localized: "Pick your partner's ideal weekend activities", comment: "Partner quiz question"),
                subtitle: String(localized: "What would they do with a totally free day?"),
                category: .activities,
                inputType: .multipleChoice(options: activityOptions.map { QuizOption.content($0) }),
                allowsMultiple: true
            ),
            QuizQuestion(
                question: named
                    ? String(localized: "What's \(name)'s favorite color?", comment: "Partner quiz question; the partner's name")
                    : String(localized: "What's your partner's favorite color?", comment: "Partner quiz question"),
                subtitle: String(localized: "The one they gravitate toward for clothes, decor, everything"),
                category: .color,
                inputType: .multipleChoice(options: colorOptions.map { QuizOption.content($0) })
            ),
            QuizQuestion(
                question: named
                    ? String(localized: "How does \(name) feel most loved?", comment: "Partner quiz question; the partner's name")
                    : String(localized: "How does your partner feel most loved?", comment: "Partner quiz question"),
                subtitle: String(localized: "Everyone has a primary love language"),
                category: .loveLanguage,
                inputType: .multipleChoice(options: LoveLanguage.allCases.map {
                    QuizOption(value: "\($0.emoji) \($0.label)", label: "\($0.emoji) \($0.displayLabel)")
                })
            ),
            QuizQuestion(
                question: named
                    ? String(localized: "When \(name) is stressed, they usually...", comment: "Partner quiz question; the partner's name")
                    : String(localized: "When your partner is stressed, they usually...", comment: "Partner quiz question"),
                subtitle: String(localized: "Knowing this helps us suggest the right support"),
                category: .stressBehavior,
                inputType: .multipleChoice(options: StressResponse.allCases.map {
                    QuizOption(value: "\($0.emoji) \($0.label)", label: "\($0.emoji) \($0.displayLabel)")
                })
            ),
            QuizQuestion(
                question: named
                    ? String(localized: "How does \(name) prefer to communicate?", comment: "Partner quiz question; the partner's name")
                    : String(localized: "How does your partner prefer to communicate?", comment: "Partner quiz question"),
                subtitle: String(localized: "Their natural style when things get real"),
                category: .communicationStyle,
                inputType: .multipleChoice(options: CommunicationStyle.allCases.map {
                    QuizOption(value: "\($0.emoji) \($0.label)", label: "\($0.emoji) \($0.displayLabel)")
                })
            ),
        ]
    }
}

#if DEBUG
extension QuizBank {
    /// Every base string the UI shows through ContentL10n (to build the Content catalog).
    static var l10nContentStrings: [String] {
        musicOptions + activityOptions + colorOptions
    }
}
#endif
