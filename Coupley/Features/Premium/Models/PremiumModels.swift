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
        case .monthly: return "$4.99 / month"
        case .yearly:  return "$39.99 / year"
        }
    }

    var savingsBadge: String? {
        switch self {
        case .monthly: return nil
        case .yearly:  return "Save 33%"
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
    case self_        = "self"
    case partner
}

// MARK: - Premium Feature

/// Features gated behind premium. Use `PremiumStore.hasAccess(to:)` at call sites.
enum PremiumFeature: String, CaseIterable {
    case unlimitedAISuggestions
    case advancedStats
    case customThemes
    case moodHistoryExport
    case prioritySupport

    var label: String {
        switch self {
        case .unlimitedAISuggestions: return "Unlimited AI suggestions"
        case .advancedStats:          return "Advanced couple analytics"
        case .customThemes:           return "Custom themes + wallpapers"
        case .moodHistoryExport:      return "Export mood history"
        case .prioritySupport:        return "Priority support"
        }
    }

    var icon: String {
        switch self {
        case .unlimitedAISuggestions: return "sparkles"
        case .advancedStats:          return "chart.bar.xaxis"
        case .customThemes:           return "paintpalette.fill"
        case .moodHistoryExport:      return "square.and.arrow.up.on.square"
        case .prioritySupport:        return "lifepreserver.fill"
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
