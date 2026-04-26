//
//  CrownMilestone.swift
//  Coupley
//
//  Crown milestones are the gamified anniversaries — 100 days, 1 year,
//  500 days, 1000 days, 2 years, 3 years, 5 years, 7 years, 10 years.
//  When a couple crosses one, the tree unlocks a new visual flourish
//  (a golden crown ring) and a one-time celebration overlay fires.
//
//  Crowns are computed entirely on-device from the relationship anchor.
//  We do NOT persist a "this crown was reached" flag — the celebration
//  overlay uses a small UserDefaults flag keyed by milestone+coupleId so
//  it shows once per achievement per device, not once per app launch.
//

import Foundation

// MARK: - Crown Milestone

/// A reachable milestone on the relationship's timeline. Two flavors:
///   - day-based  ("100 Days", "500 Days", "1000 Days")
///   - year-based ("1 Year", "2 Years", ...)
struct CrownMilestone: Identifiable, Hashable, Equatable {

    enum Kind: Hashable, Equatable {
        case days(Int)
        case years(Int)
    }

    let kind: Kind

    var id: String {
        switch kind {
        case .days(let d):  return "d\(d)"
        case .years(let y): return "y\(y)"
        }
    }

    /// Title displayed in pills, banners, and the unlock overlay.
    /// e.g. "100 Days", "1 Year", "5 Years".
    var displayTitle: String {
        switch kind {
        case .days(let d):
            return "\(d) Days"
        case .years(let y):
            return y == 1 ? "1 Year" : "\(y) Years"
        }
    }

    /// Short, warm subtitle used on the celebration overlay.
    var celebrationSubtitle: String {
        switch kind {
        case .days(100):  return "A hundred small days. One growing love."
        case .days(500):  return "Five hundred days of choosing each other."
        case .days(1000): return "A thousand days. A library of memories."
        case .days(let d): return "\(d) days of building this together."
        case .years(1):   return "Your first ring on the tree."
        case .years(2):   return "Two years deep. Roots holding firm."
        case .years(3):   return "Three years. The branches stretch wider."
        case .years(5):   return "Five years. The tree has stories of its own."
        case .years(7):   return "Seven years. Rare, and still growing."
        case .years(10):  return "A decade. An ancient, golden tree."
        case .years(let y): return "\(y) years, and still writing new chapters."
        }
    }

    /// The exact day this milestone is reached, given an anchor date.
    /// Computed at calendar day-granularity so DST/timezone shifts don't
    /// jitter the date by ±1 day.
    func date(anchor: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: anchor)
        switch kind {
        case .days(let d):
            return calendar.date(byAdding: .day, value: d, to: start) ?? start
        case .years(let y):
            return calendar.date(byAdding: .year, value: y, to: start) ?? start
        }
    }

    /// Has the couple already reached this milestone?
    func isReached(anchor: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        date(anchor: anchor, calendar: calendar) <= calendar.startOfDay(for: now)
    }

    /// Days remaining until reaching this milestone. 0 if today is the
    /// milestone day. Negative if already past.
    func daysUntil(anchor: Date, now: Date = Date(), calendar: Calendar = .current) -> Int {
        let target = calendar.startOfDay(for: date(anchor: anchor, calendar: calendar))
        let today  = calendar.startOfDay(for: now)
        return calendar.dateComponents([.day], from: today, to: target).day ?? 0
    }
}

// MARK: - Default ladder

extension CrownMilestone {

    /// The full ladder, in order from easiest to hardest. New entries
    /// can be appended without breaking anything — old devices will
    /// simply not render the milestones they don't know about, but the
    /// computed list at runtime always reflects this single source.
    static let ladder: [CrownMilestone] = [
        .init(kind: .days(100)),
        .init(kind: .years(1)),
        .init(kind: .days(500)),
        .init(kind: .days(1000)),
        .init(kind: .years(2)),
        .init(kind: .years(3)),
        .init(kind: .years(5)),
        .init(kind: .years(7)),
        .init(kind: .years(10)),
    ]

    /// The next unreached milestone given an anchor. nil if the couple
    /// has already passed every entry in the ladder (which is a great
    /// problem to have).
    static func next(after anchor: Date, now: Date = Date(), calendar: Calendar = .current) -> CrownMilestone? {
        ladder.first { !$0.isReached(anchor: anchor, now: now, calendar: calendar) }
    }

    /// All milestones already reached, oldest first.
    static func reached(after anchor: Date, now: Date = Date(), calendar: Calendar = .current) -> [CrownMilestone] {
        ladder.filter { $0.isReached(anchor: anchor, now: now, calendar: calendar) }
    }

    /// Did the couple pass this milestone within the last 24 hours? Used
    /// to drive the one-time celebration overlay on first appearance
    /// after the milestone day arrives.
    func isFreshlyReached(anchor: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let milestoneDay = calendar.startOfDay(for: date(anchor: anchor, calendar: calendar))
        let today = calendar.startOfDay(for: now)
        return milestoneDay == today
    }
}
