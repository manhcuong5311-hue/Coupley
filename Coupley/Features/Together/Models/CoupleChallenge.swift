//
//  CoupleChallenge.swift
//  Coupley
//
//  A time-boxed challenge the couple commits to together. Distinct from a
//  goal in two ways:
//   1. challenges are streak-driven, not progress-driven (you check in once
//      per day rather than contributing increments)
//   2. challenges have a fixed duration after which they wrap up — goals
//      have an optional due date but can run indefinitely
//
//  Free users get 1 active challenge. Premium gets unlimited.
//

import Foundation
import FirebaseFirestore

// MARK: - Challenge Category

enum ChallengeCategory: String, Codable, CaseIterable, Identifiable {
    case gratitude
    case fitness
    case romance
    case savings
    case mindful
    case connection
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .gratitude:  return "Gratitude"
        case .fitness:    return "Fitness"
        case .romance:    return "Romance"
        case .savings:    return "Savings"
        case .mindful:    return "Mindfulness"
        case .connection: return "Connection"
        case .other:      return "Other"
        }
    }

    var icon: String {
        switch self {
        case .gratitude:  return "leaf.fill"
        case .fitness:    return "figure.run"
        case .romance:    return "heart.fill"
        case .savings:    return "banknote"
        case .mindful:    return "moon.stars.fill"
        case .connection: return "person.2.fill"
        case .other:      return "sparkles"
        }
    }

    var emoji: String {
        switch self {
        case .gratitude:  return "🌿"
        case .fitness:    return "💪"
        case .romance:    return "❤️"
        case .savings:    return "💰"
        case .mindful:    return "🌙"
        case .connection: return "💑"
        case .other:      return "✨"
        }
    }
}

// MARK: - Challenge Cadence

/// How often a check-in counts. Daily challenges advance every day; weekly
/// challenges advance every week. We don't support custom cadences in v1
/// because the streak model gets ugly fast.
enum ChallengeCadence: String, Codable, CaseIterable {
    case daily
    case weekly

    var label: String {
        switch self {
        case .daily:  return "Daily"
        case .weekly: return "Weekly"
        }
    }

    /// One unit of cadence in seconds (roughly — close enough for streak math).
    var unitSeconds: TimeInterval {
        switch self {
        case .daily:  return 60 * 60 * 24
        case .weekly: return 60 * 60 * 24 * 7
        }
    }

    /// The cadence unit a date falls into. Both partners checking in on the
    /// same day land in one bucket.
    func bucket(for date: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .daily:
            return calendar.startOfDay(for: date)
        case .weekly:
            // ISO-8601 week start, so a weekly bucket does not depend on
            // which day someone happened to check in.
            let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            return calendar.date(from: comps) ?? date
        }
    }

    /// Distinct cadence units represented in a check-in log.
    func buckets(for dates: [Date], calendar: Calendar = .current) -> Set<Date> {
        Set(dates.map { bucket(for: $0, calendar: calendar) })
    }
}

// MARK: - Couple Challenge

struct CoupleChallenge: Identifiable, Codable, Equatable {
    @DocumentID var firestoreId: String?

    let id: String
    var title: String
    var category: ChallengeCategory
    var colorway: TogetherColorway
    var cadence: ChallengeCadence

    /// Total number of check-ins required to complete the challenge. e.g. a
    /// "30 days gratitude" challenge would have `targetCount = 30`.
    var targetCount: Int

    /// Aggregate completed check-ins. We store both partners' contributions in
    /// the same map so the UI can show a "12 of 14 done by you, 2 by partner"
    /// split when it matters.
    var contribution: TogetherContribution

    /// Day-by-day check-in tracking. Encoded as a date list so the heat-map
    /// view can render activity over time without a subcollection.
    var checkInLog: [Date]

    /// Who checked in, and when. `checkInLog` records *that* a check-in
    /// happened but not *who* — which is the exact question a mutual
    /// challenge is built on, and the reason `hasCheckedIn(for:on:)` used to
    /// answer it wrong. Documents written before this field exists decode to
    /// an empty map; see `hasCheckedIn` for how that is handled.
    var checkInsByUser: [String: [Date]] = [:]

    /// Streak state. Recomputed from `checkInLog` whenever a check-in is
    /// recorded so it stays consistent without a separate write.
    var streak: TogetherStreak

    /// When the challenge starts counting. Future-dated challenges show a
    /// "Starts in 3d" chip and don't accept check-ins yet.
    let startDate: Date

    let createdBy: String
    let createdAt: Date
    var updatedAt: Date

    var completedAt: Date?

    var documentId: String { firestoreId ?? id }

    // MARK: - Derived

    /// Progress is measured in cadence units, not raw check-ins.
    ///
    /// `targetCount` means days ("a 30 days gratitude challenge would have
    /// targetCount = 30"), so once both partners can check in on the same day
    /// — which they could not before `hasCheckedIn` was fixed — counting raw
    /// entries would finish a 30-day challenge in 15. Legacy logs hold at
    /// most one entry per day, so this changes nothing for existing data.
    var totalCheckIns: Int { cadence.buckets(for: checkInLog).count }

    var progress: Double {
        guard targetCount > 0 else { return 0 }
        return min(1.0, Double(totalCheckIns) / Double(targetCount))
    }

    var isComplete: Bool {
        completedAt != nil || totalCheckIns >= targetCount
    }

    var hasStarted: Bool {
        startDate <= Date()
    }

    /// Calendar-aware deadline. Daily challenges end after `targetCount` days
    /// from start; weekly multiplies by 7.
    var endDate: Date {
        let interval = cadence.unitSeconds * Double(targetCount)
        return startDate.addingTimeInterval(interval)
    }

    /// Whether *this user* has already checked in for this cadence unit.
    ///
    /// This used to ignore `userId` entirely and ask only "did anyone check
    /// in today", which made the first partner's tap consume the day for
    /// both: the second partner's check-in was silently dropped by the
    /// idempotency guard in `recordCheckIn`, so their contribution never
    /// counted and no Together surface actually required mutual action.
    ///
    /// Legacy documents carry `checkInLog` entries with no attribution. They
    /// are treated as nobody-has-checked-in-yet rather than guessed at: that
    /// allows at most one extra check-in per existing challenge, once, and
    /// the map is populated from the next write onward. Guessing an owner
    /// would be wrong permanently; this is wrong briefly and self-corrects.
    func hasCheckedIn(for userId: String, on date: Date = Date()) -> Bool {
        let calendar = Calendar.current
        return (checkInsByUser[userId] ?? []).contains { logDate in
            calendar.isDate(logDate, inSameDayAs: date)
        }
    }

    /// How many times this partner has checked in overall.
    func checkInCount(for userId: String) -> Int {
        (checkInsByUser[userId] ?? []).count
    }

    var statusLine: String {
        if isComplete { return "Completed 🎉" }
        if !hasStarted {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return "Starts \(formatter.localizedString(for: startDate, relativeTo: Date()))"
        }
        switch cadence {
        case .daily:  return "Day \(totalCheckIns) of \(targetCount)"
        case .weekly: return "Week \(totalCheckIns) of \(targetCount)"
        }
    }
}

// MARK: - Challenge Suggestions

struct ChallengeSuggestion: Identifiable {
    let id = UUID()
    let title: String
    let category: ChallengeCategory
    let cadence: ChallengeCadence
    let targetCount: Int
    let emoji: String
    let blurb: String

    static let library: [ChallengeSuggestion] = [
        ChallengeSuggestion(
            title: "14 Days of Gratitude",
            category: .gratitude, cadence: .daily, targetCount: 14, emoji: "🌿",
            blurb: "One thing you're grateful for. Every day, for two weeks."
        ),
        ChallengeSuggestion(
            title: "20 Days Gym Together",
            category: .fitness, cadence: .daily, targetCount: 20, emoji: "💪",
            blurb: "Move your body, side by side. 20 sessions in a month."
        ),
        ChallengeSuggestion(
            title: "Weekly Date Challenge",
            category: .romance, cadence: .weekly, targetCount: 8, emoji: "🌹",
            blurb: "Eight weeks. Eight nights that are just for you two."
        ),
        ChallengeSuggestion(
            title: "Daily Savings Habit",
            category: .savings, cadence: .daily, targetCount: 30, emoji: "💰",
            blurb: "Tiny daily wins that compound into a real fund."
        ),
        ChallengeSuggestion(
            title: "30 Days No Fighting",
            category: .connection, cadence: .daily, targetCount: 30, emoji: "🤝",
            blurb: "Disagree softer. Recover faster. Stay in it together."
        ),
        ChallengeSuggestion(
            title: "Digital Detox Nights",
            category: .mindful, cadence: .weekly, targetCount: 6, emoji: "🌙",
            blurb: "Phones away. Just you, your partner, and the evening."
        ),
        ChallengeSuggestion(
            title: "Sleep Early Together",
            category: .mindful, cadence: .daily, targetCount: 21, emoji: "😴",
            blurb: "Three weeks of going to bed by 11. You'll feel it."
        ),
        ChallengeSuggestion(
            title: "Daily Affection",
            category: .romance, cadence: .daily, targetCount: 21, emoji: "💋",
            blurb: "A kiss, a compliment, or a six-second hug. Every day."
        )
    ]
}
