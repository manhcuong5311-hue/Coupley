//
//  TogetherTypes.swift
//  Coupley
//
//  Shared enums and value types for the Together tab. Three product surfaces
//  share a small vocabulary: a colorway palette so cards co-exist visually,
//  a contributor attribution model, and a `Decimal`-friendly money type for
//  financial goals (which the rest of the codebase otherwise wouldn't need).
//
//  Goals, challenges, and dreams each have their own dedicated category enum
//  living next to their model — this file is intentionally limited to the
//  cross-cutting tokens.
//

import SwiftUI

// MARK: - Color Palette

/// One of nine premium-feeling tones. We don't expose raw RGB on the model;
/// the user picks a colorway and we resolve to a gradient at render time.
/// Keeping this enum small avoids the "rainbow of options" trap that breaks
/// premium feel — every color was hand-picked against the CoupleSync palette.
enum TogetherColorway: String, Codable, CaseIterable, Identifiable {
    case blossom    // soft pink → coral
    case sunset     // warm gold → terracotta
    case meadow     // sage → emerald
    case ocean      // teal → indigo
    case lavender   // lilac → plum
    case dawn       // peach → rose
    case ember      // amber → cinnamon
    case mist       // pearl → slate
    case sapphire   // sky → cobalt

    var id: String { rawValue }

    var label: String {
        switch self {
        case .blossom:  return "Blossom"
        case .sunset:   return "Sunset"
        case .meadow:   return "Meadow"
        case .ocean:    return "Ocean"
        case .lavender: return "Lavender"
        case .dawn:     return "Dawn"
        case .ember:    return "Ember"
        case .mist:     return "Mist"
        case .sapphire: return "Sapphire"
        }
    }

    /// Two-stop gradient. Used for hero panes, photo-less dream covers, and
    /// the progress bar fill on goal cards.
    var gradient: LinearGradient {
        LinearGradient(
            colors: stops,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Single representative color for chips, icons, glow effects.
    var primary: Color { stops[0] }

    /// Slightly darker companion — used for shadow tints and pressed states.
    var deep: Color { stops[1] }

    private var stops: [Color] {
        switch self {
        case .blossom:  return [Color(red: 1.00, green: 0.62, blue: 0.74), Color(red: 0.96, green: 0.42, blue: 0.55)]
        case .sunset:   return [Color(red: 1.00, green: 0.74, blue: 0.42), Color(red: 0.92, green: 0.46, blue: 0.32)]
        case .meadow:   return [Color(red: 0.65, green: 0.84, blue: 0.62), Color(red: 0.36, green: 0.66, blue: 0.50)]
        case .ocean:    return [Color(red: 0.46, green: 0.78, blue: 0.85), Color(red: 0.30, green: 0.52, blue: 0.78)]
        case .lavender: return [Color(red: 0.78, green: 0.70, blue: 0.92), Color(red: 0.58, green: 0.48, blue: 0.80)]
        case .dawn:     return [Color(red: 1.00, green: 0.78, blue: 0.68), Color(red: 0.95, green: 0.55, blue: 0.62)]
        case .ember:    return [Color(red: 0.98, green: 0.62, blue: 0.42), Color(red: 0.78, green: 0.36, blue: 0.28)]
        case .mist:     return [Color(red: 0.82, green: 0.80, blue: 0.84), Color(red: 0.55, green: 0.55, blue: 0.62)]
        case .sapphire: return [Color(red: 0.55, green: 0.74, blue: 0.95), Color(red: 0.30, green: 0.40, blue: 0.78)]
        }
    }

    /// Default fallbacks per category — tuned so a brand new user with zero
    /// taste-input still gets a varied, considered grid.
    static func suggested(for goalCategory: GoalCategory) -> TogetherColorway {
        switch goalCategory {
        case .travel:     return .ocean
        case .savings:    return .sunset
        case .wedding:    return .blossom
        case .home:       return .meadow
        case .lifestyle:  return .lavender
        case .health:     return .ember
        case .gratitude:  return .dawn
        case .learning:   return .sapphire
        case .other:      return .mist
        }
    }

    static func suggested(for dreamCategory: DreamCategory) -> TogetherColorway {
        switch dreamCategory {
        case .travel:    return .ocean
        case .home:      return .meadow
        case .family:    return .blossom
        case .career:    return .sapphire
        case .lifestyle: return .lavender
        case .pet:       return .dawn
        case .other:     return .mist
        }
    }

    static func suggested(for challengeCategory: ChallengeCategory) -> TogetherColorway {
        switch challengeCategory {
        case .gratitude:  return .dawn
        case .fitness:    return .ember
        case .romance:    return .blossom
        case .savings:    return .sunset
        case .mindful:    return .lavender
        case .connection: return .meadow
        case .other:      return .mist
        }
    }
}

// MARK: - Contributor Attribution

/// Tracks who contributed what toward a goal. We don't store full progress
/// history (that's a feature scope too large for v1) — just an aggregate
/// per-partner so cards can show "You: 60% · Partner: 40%" splits.
struct TogetherContribution: Codable, Equatable {
    /// Indexed by user id. Always two entries when paired (or one when solo).
    var amounts: [String: Double]

    static let empty = TogetherContribution(amounts: [:])

    var total: Double { amounts.values.reduce(0, +) }

    func amount(for userId: String) -> Double {
        amounts[userId] ?? 0
    }

    /// Returns 0...1 share for a given user. Returns 0.5 when no contributions
    /// exist yet so empty cards don't render with a 0/0 split.
    func share(for userId: String) -> Double {
        guard total > 0 else { return 0.5 }
        return amount(for: userId) / total
    }

    mutating func add(_ delta: Double, for userId: String) {
        amounts[userId, default: 0] += delta
    }
}

// MARK: - Streak

/// Rolling streak window. Streaks are recomputed locally from `lastCheckIn`
/// timestamps so the model stays compact and doesn't need a separate write
/// every midnight.
struct TogetherStreak: Codable, Equatable {
    var current: Int
    var longest: Int
    var lastCheckIn: Date?

    static let zero = TogetherStreak(current: 0, longest: 0, lastCheckIn: nil)

    /// Whether checking in *today* would extend the streak vs. start a new one.
    func isAlive(at now: Date = Date()) -> Bool {
        guard let last = lastCheckIn else { return false }
        let calendar = Calendar.current
        if calendar.isDate(last, inSameDayAs: now) { return true }
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else {
            return false
        }
        return calendar.isDate(last, inSameDayAs: yesterday)
    }

    func didCheckInToday(at now: Date = Date()) -> Bool {
        guard let last = lastCheckIn else { return false }
        return Calendar.current.isDate(last, inSameDayAs: now)
    }
}
