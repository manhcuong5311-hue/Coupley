//
//  WidgetCountdownEngine.swift
//  Coupley
//
//  Pure logic for "days together", "next anniversary", and milestone
//  highlighting. No SwiftUI, no Foundation date pickers — just calendar
//  math so every code path is unit-testable.
//

import Foundation

// MARK: - Highlight

/// What the anniversary block decides to surface on screen. The widget
/// view picks layout + accent color from this enum — never reads the raw
/// date again.
enum WidgetAnniversaryHighlight: Equatable {

    /// User hasn't set any anniversary yet — empty state.
    case empty

    /// A milestone is happening *today* or imminently (within
    /// `MilestoneEngine.imminenceWindow` days). Drives the celebratory
    /// "100 Days Together" / "1 Year Anniversary" hero treatment.
    case milestone(Milestone, daysAway: Int, daysTogether: Int)

    /// A regular anniversary is coming up. Drives the calmer "Next
    /// anniversary in N days" treatment.
    case upcomingAnniversary(title: String, daysAway: Int, daysTogether: Int)

    /// No close milestone, no scheduled anniversary — fall back to the
    /// running total. Always available once `relationshipStart` is set.
    case daysTogether(Int)
}

// MARK: - Milestone

/// A specific landmark on the relationship timeline. We highlight it when
/// the actual *day count* matches one of these values (within the
/// imminence window, both sides).
struct Milestone: Equatable, Hashable {
    let dayCount: Int
    let title: String
    let isMajor: Bool

    /// All recognised milestones. Ordered ascending so the engine can
    /// binary-search for the next-up landmark.
    static let all: [Milestone] = [
        Milestone(dayCount: 30,    title: "1 Month Together",   isMajor: false),
        Milestone(dayCount: 100,   title: "100 Days Together",  isMajor: true),
        Milestone(dayCount: 200,   title: "200 Days Together",  isMajor: false),
        Milestone(dayCount: 365,   title: "1 Year Anniversary", isMajor: true),
        Milestone(dayCount: 500,   title: "500 Days of Love",   isMajor: true),
        Milestone(dayCount: 730,   title: "2 Year Anniversary", isMajor: true),
        Milestone(dayCount: 1000,  title: "1000 Days of Love",  isMajor: true),
        Milestone(dayCount: 1095,  title: "3 Year Anniversary", isMajor: true),
        Milestone(dayCount: 1460,  title: "4 Year Anniversary", isMajor: true),
        Milestone(dayCount: 1825,  title: "5 Year Anniversary", isMajor: true),
        Milestone(dayCount: 2555,  title: "7 Year Anniversary", isMajor: true),
        Milestone(dayCount: 3650,  title: "10 Years of Love",   isMajor: true),
    ]
}

// MARK: - Countdown Engine

enum WidgetCountdownEngine {

    /// How close (in days) a milestone has to be to "win" over a regular
    /// anniversary. Past-recent ones inside this window also win — so the
    /// "100 Days Together" treatment lingers for a few days after the
    /// actual milestone, which is the warmer behaviour.
    static let imminenceWindow = 7

    // MARK: - Public

    /// Computes the headline highlight from a snapshot. `now` is parameterised
    /// for testability and so the timeline provider can pre-compute future
    /// entries.
    static func highlight(
        from snapshot: AnniversarySnapshot?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> WidgetAnniversaryHighlight {

        guard let snapshot, let start = snapshot.relationshipStart else {
            return .empty
        }

        let daysTogether = days(from: start, to: now, calendar: calendar)

        // 1. Imminent milestone wins (future or just-passed within window).
        if let imminent = nearestMilestone(forDays: daysTogether) {
            return .milestone(
                imminent.milestone,
                daysAway: imminent.daysAway,
                daysTogether: max(0, daysTogether)
            )
        }

        // 2. Otherwise look for the next named anniversary the user added.
        if let next = nextAnniversary(in: snapshot.upcoming, now: now, calendar: calendar) {
            return .upcomingAnniversary(
                title: next.title,
                daysAway: next.daysAway,
                daysTogether: max(0, daysTogether)
            )
        }

        // 3. Fallback — running total.
        return .daysTogether(max(0, daysTogether))
    }

    // MARK: - Days Together

    /// Number of full calendar days from `start` up to and including `now`.
    /// Negative when the relationship-start date is in the future (treat as 0
    /// at the call site).
    static func days(
        from start: Date,
        to now: Date,
        calendar: Calendar = .current
    ) -> Int {
        let s = calendar.startOfDay(for: start)
        let e = calendar.startOfDay(for: now)
        return calendar.dateComponents([.day], from: s, to: e).day ?? 0
    }

    /// Days between `now` and `target`. Positive = future, negative = past.
    static func daysBetween(
        now: Date,
        target: Date,
        calendar: Calendar = .current
    ) -> Int {
        let n = calendar.startOfDay(for: now)
        let t = calendar.startOfDay(for: target)
        return calendar.dateComponents([.day], from: n, to: t).day ?? 0
    }

    // MARK: - Milestone Lookup

    private struct ImminentMilestone {
        let milestone: Milestone
        let daysAway: Int
    }

    /// Returns the milestone that should hijack the display, if any.
    /// Picks the nearest milestone whose absolute distance from
    /// `daysTogether` is within `imminenceWindow`. Future imminence is
    /// preferred over past-recent — "5 days to 100 Days Together" outranks
    /// "yesterday was 30 days".
    private static func nearestMilestone(forDays daysTogether: Int) -> ImminentMilestone? {
        guard daysTogether >= 0 else { return nil }

        var bestFuture: ImminentMilestone?
        var bestPast: ImminentMilestone?

        for m in Milestone.all {
            let distance = m.dayCount - daysTogether
            guard abs(distance) <= imminenceWindow else { continue }

            if distance >= 0 {
                if bestFuture == nil || distance < bestFuture!.daysAway {
                    bestFuture = ImminentMilestone(milestone: m, daysAway: distance)
                }
            } else {
                if bestPast == nil || (-distance) < (-bestPast!.daysAway) {
                    bestPast = ImminentMilestone(milestone: m, daysAway: distance)
                }
            }
        }

        return bestFuture ?? bestPast
    }

    // MARK: - Next Named Anniversary

    private struct NextAnniversary {
        let title: String
        let daysAway: Int
    }

    private static func nextAnniversary(
        in upcoming: [UpcomingAnniversary],
        now: Date,
        calendar: Calendar
    ) -> NextAnniversary? {
        // Pick the soonest future-or-today entry.
        let candidates = upcoming
            .map { (item: $0, daysAway: daysBetween(now: now, target: $0.date, calendar: calendar)) }
            .filter { $0.daysAway >= 0 }
            .sorted { $0.daysAway < $1.daysAway }

        guard let first = candidates.first else { return nil }
        return NextAnniversary(title: first.item.title, daysAway: first.daysAway)
    }
}

// MARK: - Display Helpers

extension WidgetAnniversaryHighlight {

    /// Compact one-line caption used in the small-family widget.
    var compactCaption: String {
        switch self {
        case .empty:
            return "Start your love journey"
        case .milestone(let m, let daysAway, _):
            if daysAway == 0 { return m.title }
            if daysAway > 0  { return "\(daysAway)d to \(m.title)" }
            return "\(m.title) · \(-daysAway)d ago"
        case .upcomingAnniversary(let title, let daysAway, _):
            if daysAway == 0 { return "\(title) — today" }
            if daysAway == 1 { return "\(title) tomorrow" }
            return "\(title) in \(daysAway)d"
        case .daysTogether(let days):
            return "Together \(days) Days"
        }
    }

    /// Hero number used in the medium-family widget. Returns the number
    /// itself — the surrounding view chooses the suffix word.
    var heroNumber: Int {
        switch self {
        case .empty:                                return 0
        case .milestone(_, let daysAway, _):        return abs(daysAway)
        case .upcomingAnniversary(_, let daysAway, _): return daysAway
        case .daysTogether(let days):               return days
        }
    }

    /// Word that follows the hero number ("Days", "Day", etc).
    var heroUnit: String {
        switch self {
        case .empty:
            return ""
        case .milestone(_, let daysAway, _):
            return abs(daysAway) == 1 ? "Day" : "Days"
        case .upcomingAnniversary(_, let daysAway, _):
            return daysAway == 1 ? "Day" : "Days"
        case .daysTogether(let days):
            return days == 1 ? "Day" : "Days"
        }
    }

    /// The line above the hero number.
    var topline: String {
        switch self {
        case .empty:                              return "Together"
        case .milestone(_, let daysAway, _):
            if daysAway == 0  { return "Today" }
            if daysAway > 0   { return "Coming up" }
            return "Just celebrated"
        case .upcomingAnniversary:                return "Next Anniversary"
        case .daysTogether:                       return "Together For"
        }
    }

    /// The line below the hero number.
    var subline: String {
        switch self {
        case .empty:
            return "Set your start date ❤️"
        case .milestone(let m, let daysAway, _):
            if daysAway == 0  { return m.title + " 🎉" }
            if daysAway > 0   { return m.title }
            return m.title
        case .upcomingAnniversary(let title, _, _):
            return title
        case .daysTogether:
            return "of love"
        }
    }

    /// Drives the warm vs. neutral accent in the view layer.
    var isCelebratory: Bool {
        switch self {
        case .milestone(let m, let daysAway, _):
            return m.isMajor && abs(daysAway) <= WidgetCountdownEngine.imminenceWindow
        default:
            return false
        }
    }
}

// MARK: - Refresh Cadence

extension WidgetCountdownEngine {

    /// When should the widget timeline reload after rendering at `now`?
    /// We aim for the next significant boundary (next midnight) so the
    /// "days together" number rolls over naturally — but no later than
    /// 6 hours from now so we eventually pick up new mood/nudge data
    /// even when the main app isn't relaunched.
    static func nextRefreshDate(after now: Date, calendar: Calendar = .current) -> Date {
        let nextMidnight = calendar.nextDate(
            after: now,
            matching: DateComponents(hour: 0, minute: 0, second: 5),
            matchingPolicy: .nextTime
        ) ?? now.addingTimeInterval(60 * 60 * 6)

        let cap = now.addingTimeInterval(60 * 60 * 6)
        return min(nextMidnight, cap)
    }
}
