//
//  PartnerProfile.swift
//  Coupley
//
//  Created by Sam Manh Cuong on 1/4/26.
//

import Foundation

// MARK: - Communication Style

enum CommunicationStyle: String, CaseIterable, Identifiable, Codable {
    case introvert
    case expressive
    case avoidant

    var id: String { rawValue }

    var label: String {
        rawValue.capitalized
    }

    var emoji: String {
        switch self {
        case .introvert: return "🤫"
        case .expressive: return "🗣️"
        case .avoidant: return "🚶"
        }
    }

    var description: String {
        switch self {
        case .introvert: return "Prefers quiet, thoughtful exchanges"
        case .expressive: return "Values open, enthusiastic communication"
        case .avoidant: return "Needs space and gentle approaches"
        }
    }
}

// MARK: - Stress Response

enum StressResponse: String, CaseIterable, Identifiable, Codable {
    case talksItOut
    case needsSpace
    case wantsDistraction
    case seeksComfort

    var id: String { rawValue }

    var label: String {
        switch self {
        case .talksItOut: return "Talks it out"
        case .needsSpace: return "Needs space"
        case .wantsDistraction: return "Wants distraction"
        case .seeksComfort: return "Seeks comfort"
        }
    }

    var emoji: String {
        switch self {
        case .talksItOut: return "💬"
        case .needsSpace: return "🧘"
        case .wantsDistraction: return "🎮"
        case .seeksComfort: return "🤗"
        }
    }
}

// MARK: - Love Language

enum LoveLanguage: String, CaseIterable, Identifiable, Codable {
    case wordsOfAffirmation
    case actsOfService
    case receivingGifts
    case qualityTime
    case physicalTouch

    var id: String { rawValue }

    var label: String {
        switch self {
        case .wordsOfAffirmation: return "Words of Affirmation"
        case .actsOfService: return "Acts of Service"
        case .receivingGifts: return "Receiving Gifts"
        case .qualityTime: return "Quality Time"
        case .physicalTouch: return "Physical Touch"
        }
    }

    var emoji: String {
        switch self {
        case .wordsOfAffirmation: return "💌"
        case .actsOfService: return "🛠️"
        case .receivingGifts: return "🎁"
        case .qualityTime: return "⏰"
        case .physicalTouch: return "🫂"
        }
    }
}

// MARK: - Partner Preferences

struct PartnerPreferences: Codable, Equatable {
    var favoriteFood: [String]
    var favoriteDrink: [String]
    var favoriteMusic: [String]
    var favoriteActivities: [String]
    var favoriteColor: String

    static let empty = PartnerPreferences(
        favoriteFood: [],
        favoriteDrink: [],
        favoriteMusic: [],
        favoriteActivities: [],
        favoriteColor: ""
    )

    /// Flattened list of all preferences for AI consumption
    var allLikes: [String] {
        favoriteFood + favoriteDrink + favoriteMusic + favoriteActivities +
            (favoriteColor.isEmpty ? [] : [favoriteColor])
    }
}

// MARK: - Partner Personality

struct PartnerPersonality: Codable, Equatable {
    var communicationStyle: CommunicationStyle
    var stressResponse: StressResponse
    var loveLanguage: LoveLanguage

    static let `default` = PartnerPersonality(
        communicationStyle: .expressive,
        stressResponse: .talksItOut,
        loveLanguage: .qualityTime
    )
}

// MARK: - Favorite Things (Backward Compatibility)

struct FavoriteThings: Codable, Equatable {
    var food: String
    var drink: String
    var music: String
    var activities: [String]

    static let empty = FavoriteThings(
        food: "",
        drink: "",
        music: "",
        activities: []
    )
}

// MARK: - Partner Profile

struct PartnerProfile: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var preferences: PartnerPreferences
    var personality: PartnerPersonality
    var likes: [String]
    var dislikes: [String]

    init(
        id: UUID = UUID(),
        name: String,
        preferences: PartnerPreferences = .empty,
        personality: PartnerPersonality = .default,
        likes: [String] = [],
        dislikes: [String] = []
    ) {
        self.id = id
        self.name = name
        self.preferences = preferences
        self.personality = personality
        self.likes = likes
        self.dislikes = dislikes
    }

    // MARK: - Convenience Accessors

    /// Communication style shortcut
    var communicationStyle: CommunicationStyle {
        get { personality.communicationStyle }
        set { personality.communicationStyle = newValue }
    }

    /// Bridge to FavoriteThings for backward compat with AI suggestion service
    var favoriteThings: FavoriteThings {
        FavoriteThings(
            food: preferences.favoriteFood.first ?? "",
            drink: preferences.favoriteDrink.first ?? "",
            music: preferences.favoriteMusic.first ?? "",
            activities: preferences.favoriteActivities
        )
    }

    /// Merged likes from preferences + explicit likes for AI consumption
    var allLikes: [String] {
        Array(Set(likes + preferences.allLikes))
    }
}

// MARK: - Sample Data

extension PartnerProfile {

    static let samplePartner = PartnerProfile(
        name: "Alex",
        preferences: PartnerPreferences(
            favoriteFood: ["Sushi", "Korean BBQ", "Pasta"],
            favoriteDrink: ["Matcha latte", "Iced Americano"],
            favoriteMusic: ["Lo-fi", "Acoustic", "R&B"],
            favoriteActivities: ["Hiking", "Movie nights", "Trying new restaurants"],
            favoriteColor: "Sage green"
        ),
        personality: PartnerPersonality(
            communicationStyle: .expressive,
            stressResponse: .talksItOut,
            loveLanguage: .qualityTime
        ),
        likes: ["surprises", "long walks", "cooking together", "handwritten notes"],
        dislikes: ["being ignored", "loud arguments", "last-minute cancellations"]
    )

    static let emptyPartner = PartnerProfile(name: "")
}
