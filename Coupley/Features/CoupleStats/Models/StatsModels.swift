//
//  StatsModels.swift
//  Coupley
//
//  Created by Sam Manh Cuong on 1/4/26.
//

import Foundation
import FirebaseFirestore

// MARK: - Streak Data

struct StreakData: Codable, Equatable {
    var currentStreak: Int
    var longestStreak: Int
    var lastStreakDate: Date?

    static let zero = StreakData(currentStreak: 0, longestStreak: 0, lastStreakDate: nil)

    var isActiveToday: Bool {
        guard let lastDate = lastStreakDate else { return false }
        return Calendar.current.isDateInToday(lastDate)
    }

    var milestoneReached: StreakMilestone? {
        StreakMilestone.allCases.last { currentStreak >= $0.threshold }
    }
}

// MARK: - Streak Milestone

enum StreakMilestone: Int, CaseIterable {
    case spark = 3
    case flame = 7
    case fire = 14
    case blaze = 30
    case inferno = 60
    case eternal = 100

    var threshold: Int { rawValue }

    var label: String {
        switch self {
        case .spark: return "Spark"
        case .flame: return "Flame"
        case .fire: return "On Fire"
        case .blaze: return "Blaze"
        case .inferno: return "Inferno"
        case .eternal: return "Eternal"
        }
    }

    var icon: String {
        switch self {
        case .spark: return "sparkle"
        case .flame: return "flame"
        case .fire: return "flame.fill"
        case .blaze: return "bolt.fill"
        case .inferno: return "star.fill"
        case .eternal: return "crown.fill"
        }
    }

    var next: StreakMilestone? {
        let all = Self.allCases
        guard let idx = all.firstIndex(of: self),
              idx + 1 < all.count else { return nil }
        return all[idx + 1]
    }
}

// MARK: - Sync Score

struct SyncScore: Identifiable, Codable, Equatable {
    @DocumentID var firestoreId: String?
    let id: String
    let date: String
    let score: Int
    let moodMatch: Bool
    let energyMatch: Bool
    let userAMood: String
    let userBMood: String
    let userAEnergy: String
    let userBEnergy: String

    init(
        id: String = UUID().uuidString,
        date: String,
        score: Int,
        moodMatch: Bool,
        energyMatch: Bool,
        userAMood: String,
        userBMood: String,
        userAEnergy: String,
        userBEnergy: String
    ) {
        self.id = id
        self.date = date
        self.score = score
        self.moodMatch = moodMatch
        self.energyMatch = energyMatch
        self.userAMood = userAMood
        self.userBMood = userBMood
        self.userAEnergy = userAEnergy
        self.userBEnergy = userBEnergy
    }

    var syncLevel: SyncLevel {
        SyncLevel.from(score: score)
    }
}

// MARK: - Sync Level

enum SyncLevel: String {
    case highlyInSync
    case inSync
    case slightlyOff
    case outOfSync

    static func from(score: Int) -> SyncLevel {
        switch score {
        case 85...100: return .highlyInSync
        case 65..<85: return .inSync
        case 45..<65: return .slightlyOff
        default: return .outOfSync
        }
    }

    var label: String {
        switch self {
        case .highlyInSync: return "Highly in sync"
        case .inSync: return "In sync"
        case .slightlyOff: return "Slightly off"
        case .outOfSync: return "Out of sync"
        }
    }

    var emoji: String {
        switch self {
        case .highlyInSync: return "💛"
        case .inSync: return "💚"
        case .slightlyOff: return "🧡"
        case .outOfSync: return "💙"
        }
    }

    var encouragement: String {
        switch self {
        case .highlyInSync: return "You two are vibing together!"
        case .inSync: return "Great connection today"
        case .slightlyOff: return "A little check-in could help"
        case .outOfSync: return "Different days, still a team"
        }
    }
}

// MARK: - Weekly Trend

enum SyncTrend: Equatable {
    case up(Int)
    case down(Int)
    case stable

    var label: String {
        switch self {
        case .up(let pts): return "+\(pts)% this week"
        case .down(let pts): return "-\(pts)% this week"
        case .stable: return "Steady this week"
        }
    }

    var icon: String {
        switch self {
        case .up: return "arrow.up.right"
        case .down: return "arrow.down.right"
        case .stable: return "arrow.right"
        }
    }

    var isPositive: Bool {
        switch self {
        case .up, .stable: return true
        case .down: return false
        }
    }
}

// MARK: - Daily Pair (For Calculation)

struct DailyMoodPair {
    let date: String
    let userAMood: SharedMoodEntry
    let userBMood: SharedMoodEntry
}

// syncScores path is declared in FirestorePath (CoupleModels.swift)
