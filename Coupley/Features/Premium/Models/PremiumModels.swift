//
//  PremiumModels.swift
//  Coupley
//
//  Since 1.1 every feature is free for everyone. The only purchase is a
//  one-time "Remove Ads" that turns ads off for both partners. The old
//  Monthly / Yearly subscriptions are no longer sold, but existing
//  subscribers keep working (and stay ad-free forever).
//

import Foundation

// MARK: - Premium Plan

enum PremiumPlan: String, CaseIterable, Identifiable, Codable {
    /// Legacy auto-renewable subscriptions (no longer sold).
    case monthly
    case yearly
    /// One-time, non-consumable "Remove Ads".
    case removeAds

    var id: String { rawValue }

    var isSubscription: Bool { self != .removeAds }

    /// StoreKit product identifier (configured in App Store Connect).
    var productID: String {
        switch self {
        case .monthly:   return "com.coupley.premium.monthly"
        case .yearly:    return "com.coupley.premium.yearly"
        case .removeAds: return "com.coupley.removeads"
        }
    }

    /// Shown only until StoreKit reports the localized price.
    static let removeAdsFallbackPrice = "$9.99"
}

// MARK: - Premium Source

/// Why this user is ad-free. Derived from the stored `purchaserId`:
///   - `.selfPaid`       → users/{uid}.premium.purchaserId == uid
///   - `.partnerShared`  → couples/{cid}.premium.purchaserId == partnerUid
///                          (and this user is not self-paid)
///   - `.free`           → neither doc reports an active, valid entitlement
///
/// Only `.selfPaid` survives a disconnect.
enum PremiumSource: String, Codable {
    case free = "none"           // raw values kept for backward compat with
    case selfPaid = "self"       // any previously-written Firestore snapshots
    case partnerShared = "partner"
}

// MARK: - Feature usage

/// Features that used to be premium. All of them are unlocked now; the enum
/// remains for the AI / date-idea daily fair-use limits and call-site clarity.
enum PremiumFeature: String, CaseIterable {
    case customAvatar
    case anniversaryPhoto
    case allThemes
    case fullQuizAccess
    case customQuizzes
    case dateIdeas
    case aiMoodSuggestions
    case aiCoach
    case chatPhotos
    case memoryCapsule
    case togetherGoalsUnlimited
    case togetherChallengesUnlimited
    case togetherDreamBoard
    case togetherCoach

    /// Daily fair-use limit for everyone (nil = unlimited). AI calls cost
    /// money per request, so they keep a cap; the server enforces the same
    /// numbers (functions/index.js → LIMITS).
    var dailyLimit: Int? {
        switch self {
        case .aiMoodSuggestions: return 10
        case .aiCoach:           return 10
        case .dateIdeas:         return 25
        default:                 return nil
        }
    }

    /// Legacy subscribers keep the higher AI allowance they paid for until
    /// their subscription ends.
    var subscriberDailyLimit: Int? {
        switch self {
        case .aiMoodSuggestions: return 50
        case .aiCoach:           return 50
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
