//
//  PremiumModels.swift
//  Coupley
//

import Foundation

// MARK: - Premium Plan

enum PremiumPlan: String, CaseIterable, Identifiable, Codable {
    case monthly
    case yearly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .monthly: return "Monthly"
        case .yearly:  return "Yearly"
        }
    }

    var priceLabel: String {
        switch self {
        case .monthly: return "$3.99 / month"
        case .yearly:  return "$29.99 / year"
        }
    }

    var perMonthLabel: String {
        switch self {
        case .monthly: return "$3.99 / mo"
        case .yearly:  return "~$2.50 / mo for two"
        }
    }

    var savingsBadge: String? {
        switch self {
        case .monthly: return nil
        case .yearly:  return "Best Value"
        }
    }

    /// StoreKit product identifier (configure in App Store Connect + StoreKit file)
    var productID: String {
        switch self {
        case .monthly: return "com.coupley.premium.monthly"
        case .yearly:  return "com.coupley.premium.yearly"
        }
    }
}

// MARK: - Premium Source

/// Indicates *why* this user has premium — via their own purchase or inherited
/// from a paired partner.
enum PremiumSource: String, Codable {
    case none
    case self_   = "self"
    case partner
}

// MARK: - Premium Feature

/// Features gated behind premium. Use `PremiumStore.hasAccess(to:)` at call sites.
enum PremiumFeature: String, CaseIterable {
    case customAvatar          // Upload custom photo as avatar (free: preset only)
    case anniversaryPhoto      // Upload cover photo for anniversaries (free: none)
    case allThemes             // All theme styles (free: default only)
    case fullQuizAccess        // All quiz topics (free: first half of topics)
    case dateIdeas             // Date ideas access (free: locked, premium: 25/day)
    case aiMoodSuggestions     // AI mood suggestions (free: 1/day, premium: 50/day)

    var label: String {
        switch self {
        case .customAvatar:       return "Custom avatar photo"
        case .anniversaryPhoto:   return "Anniversary cover photos"
        case .allThemes:          return "All themes & styles"
        case .fullQuizAccess:     return "Full quiz library"
        case .dateIdeas:          return "Date ideas (25/day)"
        case .aiMoodSuggestions:  return "AI mood suggestions (50/day)"
        }
    }

    var freeLabel: String {
        switch self {
        case .customAvatar:       return "Preset avatars only"
        case .anniversaryPhoto:   return "No cover photos"
        case .allThemes:          return "Default theme only"
        case .fullQuizAccess:     return "Half the quiz library"
        case .dateIdeas:          return "Locked"
        case .aiMoodSuggestions:  return "1 per day"
        }
    }

    var icon: String {
        switch self {
        case .customAvatar:       return "person.crop.circle.fill"
        case .anniversaryPhoto:   return "photo.fill"
        case .allThemes:          return "paintpalette.fill"
        case .fullQuizAccess:     return "questionmark.bubble.fill"
        case .dateIdeas:          return "map.fill"
        case .aiMoodSuggestions:  return "sparkles"
        }
    }

    /// Daily limit for free users (nil = binary access, not daily-limited)
    var freeDailyLimit: Int? {
        switch self {
        case .aiMoodSuggestions: return 1
        case .dateIdeas:         return 0  // locked
        default:                 return nil
        }
    }

    /// Daily limit for premium users (nil = unlimited)
    var premiumDailyLimit: Int? {
        switch self {
        case .aiMoodSuggestions: return 50
        case .dateIdeas:         return 25
        default:                 return nil
        }
    }
}

// MARK: - Premium Entitlement

struct PremiumEntitlement: Codable, Equatable {
    let active: Bool
    let plan: PremiumPlan?
    let source: PremiumSource
    let expiresAt: Date?

    static let inactive = PremiumEntitlement(
        active: false, plan: nil, source: .none, expiresAt: nil
    )

    var isActive: Bool {
        guard active else { return false }
        if let expiresAt { return expiresAt > Date() }
        return true
    }
}
