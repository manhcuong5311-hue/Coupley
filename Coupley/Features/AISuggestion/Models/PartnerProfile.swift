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

    /// English name. The partner quiz stores options built from it and
    /// `LocalProfileService` matches answers against it, so it must not
    /// follow the user's language. The UI uses `displayLabel`.
    var label: String {
        switch self {
        case .introvert:  return "Introvert"
        case .expressive: return "Expressive"
        case .avoidant:   return "Avoidant"
        }
    }

    /// The name shown in the UI, in the user's language.
    var displayLabel: String {
        switch self {
        case .introvert:  return String(localized: "Introvert", comment: "Communication style")
        case .expressive: return String(localized: "Expressive", comment: "Communication style")
        case .avoidant:   return String(localized: "Avoidant", comment: "Communication style")
        }
    }

    var emoji: String {
        switch self {
        case .introvert: return "🤫"
        case .expressive: return "🗣️"
        case .avoidant: return "🚶"
        }
    }

    /// Display only.
    var description: LocalizedStringResource {
        switch self {
        case .introvert: return LocalizedStringResource("Prefers quiet, thoughtful exchanges", comment: "Description of the 'Introvert' communication style")
        case .expressive: return LocalizedStringResource("Values open, enthusiastic communication", comment: "Description of the 'Expressive' communication style")
        case .avoidant: return LocalizedStringResource("Needs space and gentle approaches", comment: "Description of the 'Avoidant' communication style")
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

    /// English name. The partner quiz stores options built from it and
    /// `LocalProfileService` matches answers against it, so it must not
    /// follow the user's language. The UI uses `displayLabel`.
    var label: String {
        switch self {
        case .talksItOut: return "Talks it out"
        case .needsSpace: return "Needs space"
        case .wantsDistraction: return "Wants distraction"
        case .seeksComfort: return "Seeks comfort"
        }
    }

    /// The name shown in the UI, in the user's language.
    var displayLabel: String {
        switch self {
        case .talksItOut:       return String(localized: "Talks it out", comment: "How a partner responds to stress")
        case .needsSpace:       return String(localized: "Needs space", comment: "How a partner responds to stress")
        case .wantsDistraction: return String(localized: "Wants distraction", comment: "How a partner responds to stress")
        case .seeksComfort:     return String(localized: "Seeks comfort", comment: "How a partner responds to stress")
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

    /// English name. The partner quiz stores options built from it,
    /// `LocalProfileService` matches answers against it, and the English-only
    /// MockAICoachService splices it into its sentences, so it must not follow
    /// the user's language. The UI uses `displayLabel`.
    var label: String {
        switch self {
        case .wordsOfAffirmation: return "Words of Affirmation"
        case .actsOfService: return "Acts of Service"
        case .receivingGifts: return "Receiving Gifts"
        case .qualityTime: return "Quality Time"
        case .physicalTouch: return "Physical Touch"
        }
    }

    /// The name shown in the UI, in the user's language.
    var displayLabel: String {
        switch self {
        case .wordsOfAffirmation: return String(localized: "Words of Affirmation", comment: "Love language")
        case .actsOfService:      return String(localized: "Acts of Service", comment: "Love language")
        case .receivingGifts:     return String(localized: "Receiving Gifts", comment: "Love language")
        case .qualityTime:        return String(localized: "Quality Time", comment: "Love language")
        case .physicalTouch:      return String(localized: "Physical Touch", comment: "Love language")
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

    /// Fallback profile for the suggestion sheet. Its likes and dislikes are
    /// sent to the AI as data, so they stay English.
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
