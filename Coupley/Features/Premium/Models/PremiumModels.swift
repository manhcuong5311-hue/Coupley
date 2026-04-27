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

/// Why this user has premium. Derived from the stored `purchaserId` — NOT
/// persisted separately, so there's a single source of truth:
///   - `.selfPaid`       → users/{uid}.premium.purchaserId == uid
///   - `.partnerShared`  → couples/{cid}.premium.purchaserId == partnerUid
///                          (and this user is not self-paid)
///   - `.free`           → neither doc reports an active, valid entitlement
///
/// This is the *ownership model*: only `.selfPaid` survives a disconnect.
/// Shared access evaporates the moment the couple doc is deleted or its
/// premium is cleared.
enum PremiumSource: String, Codable {
    case free = "none"           // raw values kept for backward compat with
    case selfPaid = "self"       // any previously-written Firestore snapshots
    case partnerShared = "partner"

    /// User-facing label for premium state rows (Settings, Paywall).
    var displayLabel: String {
        switch self {
        case .selfPaid:       return "Premium (Your Plan)"
        case .partnerShared:  return "Premium (via Partner)"
        case .free:           return "Free Plan"
        }
    }
}

// MARK: - Premium Feature

/// Features gated behind premium. Use `PremiumStore.hasAccess(to:)` at call sites.
enum PremiumFeature: String, CaseIterable {
    case customAvatar          // Upload custom photo as avatar (free: preset only)
    case anniversaryPhoto      // Upload cover photo for anniversaries / memories (free: none)
    case allThemes             // All theme styles (free: default only)
    case fullQuizAccess        // All quiz topics (free: first half of topics)
    case customQuizzes         // Create custom chat quizzes (free: 1/day, premium: unlimited)
    case dateIdeas             // Date ideas access (free: locked, premium: 25/day)
    case aiMoodSuggestions     // AI mood suggestions (free: 1/day, premium: 50/day)
    case aiCoach               // AI Relationship Coach (free: 2 sessions/week, premium: unlimited + deep features)
    case chatPhotos            // Send pictures in chat (free: 1/day, premium: unlimited)
    case memoryCapsule         // Time Tree memory capsules — write a memory that unlocks later (free: locked)
    case togetherGoalsUnlimited      // Together: unlimited active goals (free: 2 max)
    case togetherChallengesUnlimited // Together: unlimited challenges (free: 1 max)
    case togetherDreamBoard          // Together: full Dream Board (free: 1 dream max, no photos)
    case togetherCoach               // Together: AI Couple Coach insights (free: locked)

    var label: String {
        switch self {
        case .customAvatar:                return "Custom avatar photo"
        case .anniversaryPhoto:            return "Memory & anniversary photos"
        case .allThemes:                   return "All themes & styles"
        case .fullQuizAccess:              return "Full quiz library"
        case .customQuizzes:               return "Custom quizzes (unlimited)"
        case .dateIdeas:                   return "Date ideas (25/day)"
        case .aiMoodSuggestions:           return "AI mood suggestions (50/day)"
        case .aiCoach:                     return "AI Relationship Coach"
        case .chatPhotos:                  return "Unlimited chat photos"
        case .memoryCapsule:               return "Memory Capsules"
        case .togetherGoalsUnlimited:      return "Unlimited shared goals"
        case .togetherChallengesUnlimited: return "Unlimited couple challenges"
        case .togetherDreamBoard:          return "Full Dream Board"
        case .togetherCoach:               return "AI Couple Coach"
        }
    }

    var freeLabel: String {
        switch self {
        case .customAvatar:                return "Preset avatars only"
        case .anniversaryPhoto:            return "No memory photos"
        case .allThemes:                   return "Default theme only"
        case .fullQuizAccess:              return "Half the quiz library"
        case .customQuizzes:               return "1 per day"
        case .dateIdeas:                   return "Locked"
        case .aiMoodSuggestions:           return "1 per day"
        case .aiCoach:                     return "2 sessions per week"
        case .chatPhotos:                  return "1 photo per day"
        case .memoryCapsule:               return "Locked"
        case .togetherGoalsUnlimited:      return "2 active goals"
        case .togetherChallengesUnlimited: return "1 active challenge"
        case .togetherDreamBoard:          return "1 dream"
        case .togetherCoach:               return "Locked"
        }
    }

    var icon: String {
        switch self {
        case .customAvatar:                return "person.crop.circle.fill"
        case .anniversaryPhoto:            return "photo.fill"
        case .allThemes:                   return "paintpalette.fill"
        case .fullQuizAccess:              return "questionmark.bubble.fill"
        case .customQuizzes:               return "pencil.and.list.clipboard"
        case .dateIdeas:                   return "map.fill"
        case .aiMoodSuggestions:           return "sparkles"
        case .aiCoach:                     return "heart.text.square.fill"
        case .chatPhotos:                  return "camera.fill"
        case .memoryCapsule:               return "lock.shield.fill"
        case .togetherGoalsUnlimited:      return "target"
        case .togetherChallengesUnlimited: return "flame.fill"
        case .togetherDreamBoard:          return "sparkles.rectangle.stack.fill"
        case .togetherCoach:               return "wand.and.stars"
        }
    }

    /// Daily limit for free users (nil = binary access, not daily-limited)
    var freeDailyLimit: Int? {
        switch self {
        case .aiMoodSuggestions: return 1
        case .dateIdeas:         return 0  // locked
        case .aiCoach:           return 1  // 1 session per day on free tier
        case .chatPhotos:        return 1  // 1 photo per day on free tier
        case .customQuizzes:     return 1  // 1 custom chat quiz per day on free tier
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
        active: false, plan: nil, source: .free, expiresAt: nil
    )

    var isActive: Bool {
        guard active else { return false }
        if let expiresAt { return expiresAt > Date() }
        return true
    }
}
