//
//  TreeGrowthStage.swift
//  Coupley
//
//  Computes the visual maturity of the Relationship Tree from the number
//  of days the couple has been together. Each stage adds new visual
//  layers — branches, leaves, flowers, fruits, crown — so the tree
//  evolves alongside the relationship without ever resetting backwards.
//
//  All thresholds are intentionally generous in early stages so new
//  couples see meaningful growth in their first weeks (this is the
//  retention window where a static tree would feel disappointing).
//

import Foundation
import SwiftUI

// MARK: - Tree Growth Stage

enum TreeGrowthStage: Int, CaseIterable, Comparable {
    case seed       // 0 - 6 days
    case sprout     // 7 - 29 days
    case sapling    // 30 - 89 days
    case young      // 90 - 179 days
    case blooming   // 180 - 364 days
    case fruiting   // 1 - 2 years
    case mature     // 2 - 4 years
    case ancient    // 4+ years

    static func < (lhs: TreeGrowthStage, rhs: TreeGrowthStage) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    static func from(daysTogether: Int) -> TreeGrowthStage {
        switch daysTogether {
        case ..<7:        return .seed
        case 7..<30:      return .sprout
        case 30..<90:     return .sapling
        case 90..<180:    return .young
        case 180..<365:   return .blooming
        case 365..<730:   return .fruiting
        case 730..<1460:  return .mature
        default:          return .ancient
        }
    }

    // MARK: - Display

    var displayName: String {
        switch self {
        case .seed:      return "Seed"
        case .sprout:    return "Sprout"
        case .sapling:   return "Sapling"
        case .young:     return "Young Tree"
        case .blooming:  return "Blooming"
        case .fruiting:  return "Fruiting"
        case .mature:    return "Mature"
        case .ancient:   return "Ancient"
        }
    }

    /// Short emotional caption shown under the tree stage badge.
    var poeticCaption: String {
        switch self {
        case .seed:      return "Just planted. Tender beginnings."
        case .sprout:    return "First green. Reaching for light."
        case .sapling:   return "Steady growth, finding its shape."
        case .young:     return "Branches stretching outward."
        case .blooming:  return "First flowers — your tree is blooming."
        case .fruiting:  return "Golden fruit. A year of you."
        case .mature:    return "Strong roots. Wide canopy."
        case .ancient:   return "An old tree. Remarkable, rare."
        }
    }

    // MARK: - Drawing parameters

    /// 0…1 trunk maturity — drives trunk thickness and height.
    var trunkScale: CGFloat {
        switch self {
        case .seed:      return 0.18
        case .sprout:    return 0.30
        case .sapling:   return 0.45
        case .young:     return 0.60
        case .blooming:  return 0.74
        case .fruiting:  return 0.86
        case .mature:    return 0.95
        case .ancient:   return 1.00
        }
    }

    /// 0…1 canopy fullness — leaf count multiplier.
    var canopyFullness: CGFloat {
        switch self {
        case .seed:      return 0.05
        case .sprout:    return 0.18
        case .sapling:   return 0.36
        case .young:     return 0.54
        case .blooming:  return 0.72
        case .fruiting:  return 0.86
        case .mature:    return 0.96
        case .ancient:   return 1.00
        }
    }

    /// Number of major branch limbs.
    var branchCount: Int {
        switch self {
        case .seed:      return 0
        case .sprout:    return 2
        case .sapling:   return 3
        case .young:     return 5
        case .blooming:  return 7
        case .fruiting:  return 9
        case .mature:    return 11
        case .ancient:   return 13
        }
    }

    /// Number of decorative blossoms drawn on the canopy.
    var blossomCount: Int {
        switch self {
        case .seed, .sprout, .sapling: return 0
        case .young:                   return 3
        case .blooming:                return 9
        case .fruiting:                return 7   // some replaced by fruit
        case .mature:                  return 9
        case .ancient:                 return 11
        }
    }

    /// Golden fruits — appear at the fruiting stage and beyond.
    var fruitCount: Int {
        switch self {
        case .seed, .sprout, .sapling, .young, .blooming: return 0
        case .fruiting:  return 5
        case .mature:    return 7
        case .ancient:   return 9
        }
    }

    /// Whether to render the wide ornamental crown ring above the tree.
    /// Only the most mature trees earn it — separate from per-anniversary
    /// crown bursts, which are short-lived celebration overlays.
    var showsAmbientCrown: Bool {
        switch self {
        case .mature, .ancient: return true
        default:                return false
        }
    }
}

// MARK: - Season

/// Subtle seasonal tint applied to the tree canopy. Resolved from the
/// device's current month in the user's timezone — purely cosmetic, but
/// it gives the canvas a sense of time passing and rewards users who
/// open the app across seasons.
enum TreeSeason {
    case spring
    case summer
    case autumn
    case winter

    static func current(now: Date = Date(), calendar: Calendar = .current) -> TreeSeason {
        let month = calendar.component(.month, from: now)
        switch month {
        case 3...5:   return .spring
        case 6...8:   return .summer
        case 9...11:  return .autumn
        default:      return .winter   // Dec, Jan, Feb
        }
    }

    /// Two-stop palette for canopy leaves (top → bottom of leaf).
    /// Designed to read on both light and dark themes — saturation kept
    /// low so it doesn't fight the background gradient.
    var canopyColors: (top: Color, bottom: Color) {
        switch self {
        case .spring:
            return (
                Color(red: 0.62, green: 0.84, blue: 0.58),
                Color(red: 0.42, green: 0.70, blue: 0.48)
            )
        case .summer:
            return (
                Color(red: 0.40, green: 0.74, blue: 0.46),
                Color(red: 0.22, green: 0.56, blue: 0.34)
            )
        case .autumn:
            return (
                Color(red: 0.94, green: 0.66, blue: 0.32),
                Color(red: 0.78, green: 0.42, blue: 0.22)
            )
        case .winter:
            return (
                Color(red: 0.78, green: 0.85, blue: 0.92),
                Color(red: 0.58, green: 0.68, blue: 0.80)
            )
        }
    }

    var displayName: String {
        switch self {
        case .spring: return "Spring"
        case .summer: return "Summer"
        case .autumn: return "Autumn"
        case .winter: return "Winter"
        }
    }

    var emoji: String {
        switch self {
        case .spring: return "🌱"
        case .summer: return "☀️"
        case .autumn: return "🍂"
        case .winter: return "❄️"
        }
    }
}
