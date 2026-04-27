//
//  TogetherInsight.swift
//  Coupley
//
//  AI Couple Coach output. Insights are computed locally from the goals,
//  challenges, and dreams the user has on file — keeping the bar low for
//  premium-feeling intelligence without requiring a backend round-trip.
//
//  When a real LLM is wired up later, it'll produce the same shape and the
//  UI doesn't need to change.
//

import Foundation

// MARK: - Insight Tone

/// Drives the visual treatment on the coach card (icon, accent color).
/// Distinct from category — tone is *how it feels*, category is *what it's
/// about*. We deliberately keep the count small so the home page doesn't
/// turn into a rainbow.
enum InsightTone: String, Codable, CaseIterable {
    case celebrate     // green — "you did the thing"
    case encourage     // gold — "keep going"
    case nudge         // soft pink — "here's what's next"
    case suggest       // lavender — "have you thought about..."
    case warn          // muted — "this is slipping"

    var color: TogetherColorway {
        switch self {
        case .celebrate: return .meadow
        case .encourage: return .sunset
        case .nudge:     return .blossom
        case .suggest:   return .lavender
        case .warn:      return .mist
        }
    }

    var icon: String {
        switch self {
        case .celebrate: return "sparkles"
        case .encourage: return "flame.fill"
        case .nudge:     return "arrow.up.right.circle.fill"
        case .suggest:   return "lightbulb.fill"
        case .warn:      return "moon.stars.fill"
        }
    }
}

// MARK: - Insight Category

enum InsightCategory: String, Codable {
    case progress     // about advancing on a goal/challenge
    case consistency  // about streaks and habit health
    case emotional    // about how the relationship is feeling
    case financial    // about savings goals
    case dream        // about future plans
    case habit        // about daily rhythms
}

// MARK: - Together Insight

struct TogetherInsight: Identifiable, Equatable {
    let id: String
    let tone: InsightTone
    let category: InsightCategory

    /// One line — the quote-worthy headline. Should read aloud nicely.
    let title: String

    /// Optional second line for context. Always one or two sentences.
    let detail: String?

    /// Optional CTA the card can render as a button. Tapping deeplinks into
    /// whatever view the action references.
    let action: InsightAction?

    /// Used to sort + dedupe. Higher = more important.
    let weight: Int
}

// MARK: - Action

enum InsightAction: Equatable {
    case openGoal(id: String)
    case openChallenge(id: String)
    case openDream(id: String)
    case createGoal(suggestion: String)
    case createChallenge(suggestion: String)
    case createDream(suggestion: String)
    case openPaywall

    var label: String {
        switch self {
        case .openGoal:                 return "Open goal"
        case .openChallenge:            return "Open challenge"
        case .openDream:                return "Open dream"
        case .createGoal:               return "Start this goal"
        case .createChallenge:          return "Start this challenge"
        case .createDream:              return "Add this dream"
        case .openPaywall:              return "Unlock Coach"
        }
    }
}

// MARK: - Coach Stats Snapshot

/// Top-of-tab summary of how things are going. The hero pulls a single bit
/// of copy from the most-relevant insight; this snapshot is the supporting
/// numerical layer (used by the streak chip, the progress ring, etc.).
struct TogetherStats: Equatable {
    let activeGoalCount: Int
    let activeChallengeCount: Int
    let dreamCount: Int

    /// Highest current streak across all challenges.
    let longestActiveStreak: Int

    /// Goal closest to completion (by progress %), used for the headline.
    let leadingGoalTitle: String?
    let leadingGoalProgress: Double?

    /// Total progress across all active goals — averaged. Used for the hero
    /// progress ring on Today Together.
    let overallProgress: Double

    /// Whether *any* goal/challenge has had activity today.
    let hasActivityToday: Bool

    static let empty = TogetherStats(
        activeGoalCount: 0,
        activeChallengeCount: 0,
        dreamCount: 0,
        longestActiveStreak: 0,
        leadingGoalTitle: nil,
        leadingGoalProgress: nil,
        overallProgress: 0,
        hasActivityToday: false
    )
}
