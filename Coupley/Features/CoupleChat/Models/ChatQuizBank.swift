//
//  ChatQuizBank.swift
//  Coupley
//
//  Curated question bank for Couple Quiz Chat.
//  The orchestrator picks from this bank when AI is unavailable or disabled.
//

import Foundation

struct ChatQuizTemplate {
    let questionId: String
    let topic: QuizTopic
    let question: String
    let subtitle: String
    let options: [String]            // [] for free text
    let allowsMultiple: Bool
}

enum ChatQuizBank {

    /// All bundled templates. Grouped by topic; easy to extend.
    static let all: [ChatQuizTemplate] = [

        // MARK: Love & Emotion
        .init(questionId: "ll_primary",
              topic: .loveLanguage,
              question: "Which makes you feel most loved?",
              subtitle: "Pick the one that lands deepest.",
              options: ["Words of affirmation", "Quality time", "Acts of service",
                        "Physical touch", "Gifts"],
              allowsMultiple: false),

        .init(questionId: "ll_reset",
              topic: .loveLanguage,
              question: "After a hard day, what helps you reset with your partner?",
              subtitle: "",
              options: ["A hug and silence", "A long conversation",
                        "Cooking or eating together", "Going for a walk",
                        "Space for a bit, then reconnect"],
              allowsMultiple: false),

        // MARK: Communication
        .init(questionId: "com_style",
              topic: .communication,
              question: "When something bothers you, how do you bring it up?",
              subtitle: "",
              options: ["Direct, right away", "After I've thought about it",
                        "I drop hints first", "I wait until it's big"],
              allowsMultiple: false),

        .init(questionId: "com_listen",
              topic: .communication,
              question: "When your partner is upset, what helps most?",
              subtitle: "",
              options: ["Just listen", "Offer a solution", "Give them space",
                        "A physical hug"],
              allowsMultiple: false),

        // MARK: Conflict
        .init(questionId: "conflict_style",
              topic: .conflict,
              question: "In a disagreement, which sounds most like you?",
              subtitle: "",
              options: ["I want to talk it out now", "I need time to cool down",
                        "I try to find the middle", "I tend to avoid"],
              allowsMultiple: false),

        // MARK: Finance
        .init(questionId: "fin_style",
              topic: .finance,
              question: "How would you describe your spending?",
              subtitle: "",
              options: ["Conservative", "Balanced", "Generous with experiences",
                        "Spontaneous"],
              allowsMultiple: false),

        .init(questionId: "fin_goal",
              topic: .finance,
              question: "What's a money goal you'd actually enjoy?",
              subtitle: "Pick one.",
              options: ["Save for a trip", "Buy a home", "Invest for the future",
                        "Build an emergency fund", "Splurge on something together"],
              allowsMultiple: false),

        // MARK: Lifestyle
        .init(questionId: "life_weekend",
              topic: .lifestyle,
              question: "Perfect Sunday looks like…",
              subtitle: "",
              options: ["Slow morning at home", "Out exploring", "Seeing friends",
                        "Working on a project", "Doing nothing together"],
              allowsMultiple: false),

        .init(questionId: "life_energy",
              topic: .lifestyle,
              question: "When do you feel most alive?",
              subtitle: "",
              options: ["Early morning", "Late night", "Middle of the day",
                        "It depends"],
              allowsMultiple: false),

        // MARK: Intimacy
        .init(questionId: "intimacy_checkin",
              topic: .intimacy,
              question: "What makes you feel closest to your partner?",
              subtitle: "",
              options: ["Eye contact", "Deep conversation", "Shared silence",
                        "Physical closeness", "Being silly together"],
              allowsMultiple: false),

        // MARK: Music
        .init(questionId: "music_mood",
              topic: .music,
              question: "What music matches your current mood?",
              subtitle: "Genre or an artist works.",
              options: [],
              allowsMultiple: false),

        .init(questionId: "music_shared",
              topic: .music,
              question: "Pick a genre you could listen to together forever",
              subtitle: "",
              options: ["Indie / alternative", "Pop", "R&B / soul",
                        "Hip-hop", "Classical / instrumental", "Lo-fi / chill",
                        "Rock", "Electronic"],
              allowsMultiple: true),

        // MARK: Sport
        .init(questionId: "sport_together",
              topic: .sport,
              question: "Something active we could try together?",
              subtitle: "",
              options: ["Hiking", "Running", "Yoga", "Swimming", "Cycling",
                        "Tennis / badminton", "Gym", "Dance"],
              allowsMultiple: true),

        // MARK: Travel
        .init(questionId: "travel_style",
              topic: .travel,
              question: "Your ideal trip leans…",
              subtitle: "",
              options: ["Relaxed beach / nature", "City and culture",
                        "Adventure / outdoors", "Food-focused", "Roadtrip"],
              allowsMultiple: false),

        // MARK: Food
        .init(questionId: "food_comfort",
              topic: .food,
              question: "Your go-to comfort food right now?",
              subtitle: "",
              options: [],
              allowsMultiple: false),

        // MARK: Family
        .init(questionId: "family_kids",
              topic: .family,
              question: "How do you feel about kids in the future?",
              subtitle: "Honest answers only — no wrong choice.",
              options: ["Yes, definitely", "Open to it", "Not sure yet",
                        "Probably not", "No"],
              allowsMultiple: false),

        // MARK: Career
        .init(questionId: "career_balance",
              topic: .career,
              question: "How do you want work to fit into your life?",
              subtitle: "",
              options: ["Work hard, play hard", "Steady 9–5, life outside it",
                        "Passion project + income", "Flexible / remote life"],
              allowsMultiple: false),
    ]

    static func byId(_ id: String) -> ChatQuizTemplate? {
        all.first { $0.questionId == id }
    }

    static func byTopic(_ topic: QuizTopic) -> [ChatQuizTemplate] {
        all.filter { $0.topic == topic }
    }
}
