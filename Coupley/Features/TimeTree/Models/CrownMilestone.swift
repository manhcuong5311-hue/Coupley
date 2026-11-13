//
//  CrownMilestone.swift
//  Coupley
//
//  Crown milestones are the gamified anniversaries — 100 days, 1 year,
//  500 days, 2 years, 1000 days, 3 years, 5 years, 7 years, 10 years.
//  When a couple crosses one, the tree unlocks a new visual flourish
//  (a golden crown ring) and a one-time celebration overlay fires.
//
//  Crowns are computed entirely on-device from the relationship anchor.
//  We do NOT persist a "this crown was reached" flag — the celebration
//  overlay uses a small UserDefaults flag keyed by milestone+coupleId so
//  it shows once per achievement per device, not once per app launch.
//
//  Every date here counts from the day the start date names
//  (`JourneyCalendarDay.localDay(ofStored:)`), never from the raw stored
//  instant, so both partners reach a crown on the same calendar day.
//

import Foundation

// MARK: - Crown Milestone

/// A reachable milestone on the relationship's timeline. Two flavors:
///   - day-based  ("100 Days", "500 Days", "1000 Days")
///   - year-based ("1 Year", "2 Years", ...)
///
/// A pure value: usable from any isolation (the reminder scheduler computes
/// crown dates too).
nonisolated struct CrownMilestone: Identifiable, Hashable, Equatable {

    nonisolated enum Kind: Hashable, Equatable {
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

    /// ENGLISH title for the crown reminders, which stay English like every
    /// notification: "100 Days", "1 Year", "5 Years". The app's UI shows
    /// `localizedTitle` instead.
    var displayTitle: String {
        switch kind {
        case .days(let d):
            return "\(d) Days"
        case .years(let y):
            return y == 1 ? "1 Year" : "\(y) Years"
        }
    }

    /// The title in the user's language, for the UI (countdown rows and the
    /// celebration overlay): "100 Days", "1 Year", "5 Years".
    var localizedTitle: String {
        switch kind {
        case .days(let d):
            return String(localized: "\(d) Days", comment: "Crown milestone title, e.g. '100 Days' (days together)")
        case .years(let y):
            return y == 1
                ? String(localized: "1 Year", comment: "Crown milestone title: one year together")
                : String(localized: "\(y) Years", comment: "Crown milestone title, e.g. '5 Years' (years together)")
        }
    }

    /// The subtitle in the user's language, for the celebration overlay.
    var localizedCelebrationSubtitle: String {
        switch kind {
        case .days(100):
            return String(localized: "A hundred small days. One growing love.", comment: "Crown celebration subtitle: 100 days together")
        case .days(500):
            return String(localized: "Five hundred days of choosing each other.", comment: "Crown celebration subtitle: 500 days together")
        case .days(1000):
            return String(localized: "A thousand days. A library of memories.", comment: "Crown celebration subtitle: 1000 days together")
        case .days(let d):
            return String(localized: "\(d) days of building this together.", comment: "Crown celebration subtitle for any other day count")
        case .years(1):
            return String(localized: "Your first ring on the tree.", comment: "Crown celebration subtitle: 1 year together (a tree ring)")
        case .years(2):
            return String(localized: "Two years deep. Roots holding firm.", comment: "Crown celebration subtitle: 2 years together")
        case .years(3):
            return String(localized: "Three years. The branches stretch wider.", comment: "Crown celebration subtitle: 3 years together")
        case .years(5):
            return String(localized: "Five years. The tree has stories of its own.", comment: "Crown celebration subtitle: 5 years together")
        case .years(7):
            return String(localized: "Seven years. Rare, and still growing.", comment: "Crown celebration subtitle: 7 years together")
        case .years(10):
            return String(localized: "A decade. An ancient, golden tree.", comment: "Crown celebration subtitle: 10 years together")
        case .years(let y):
            return String(localized: "\(y) years, and still writing new chapters.", comment: "Crown celebration subtitle for any other year count")
        }
    }

    /// ENGLISH subtitle, the body of a crown reminder (notifications stay
    /// English). The celebration overlay shows `localizedCelebrationSubtitle`.
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

    /// The day this milestone is reached (the start of that day in
    /// `calendar`), counted from the day the stored start date names.
    /// Day-granular, so DST and time-zone shifts can't jitter it by a day.
    func date(anchor: Date, calendar: Calendar = .current) -> Date {
        let start = JourneyCalendarDay.localDay(ofStored: anchor, calendar: calendar)
        let reached: Date?
        switch kind {
        case .days(let d):
            reached = calendar.date(byAdding: .day, value: d, to: start)
        case .years(let y):
            reached = JourneyCalendarDay.gregorian(in: calendar).date(byAdding: .year, value: y, to: start)
        }
        return calendar.startOfDay(for: reached ?? start)
    }

    /// Has the couple already reached this milestone?
    func isReached(anchor: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        date(anchor: anchor, calendar: calendar) <= calendar.startOfDay(for: now)
    }

    /// Days remaining until reaching this milestone. 0 if today is the
    /// milestone day. Negative if already past.
    func daysUntil(anchor: Date, now: Date = Date(), calendar: Calendar = .current) -> Int {
        let target = date(anchor: anchor, calendar: calendar)
        let today  = calendar.startOfDay(for: now)
        return calendar.dateComponents([.day], from: today, to: target).day ?? 0
    }

    /// Reached, and at most `withinDays` calendar days ago (0 = today).
    /// Drives the automatic celebration, so a couple who first opens the app
    /// a day or two after the milestone still gets the moment.
    func isRecentlyReached(anchor: Date,
                           now: Date = Date(),
                           withinDays: Int = 3,
                           calendar: Calendar = .current) -> Bool {
        let daysAgo = -daysUntil(anchor: anchor, now: now, calendar: calendar)
        return daysAgo >= 0 && daysAgo <= max(0, withinDays)
    }
}

// MARK: - Default ladder

extension CrownMilestone {

    /// The full ladder, in date order for every start date (2 years is day
    /// 730 or 731, before 1000 days; 3 years is day 1095 or 1096, after it).
    /// `next` and `reached` still sort by each milestone's actual date for
    /// the given anchor, so this order is never load-bearing.
    static let ladder: [CrownMilestone] = [
        .init(kind: .days(100)),
        .init(kind: .years(1)),
        .init(kind: .days(500)),
        .init(kind: .years(2)),
        .init(kind: .days(1000)),
        .init(kind: .years(3)),
        .init(kind: .years(5)),
        .init(kind: .years(7)),
        .init(kind: .years(10)),
    ]

    /// The ladder sorted by the date each milestone falls on for `anchor`
    /// (ladder order breaks a tie).
    private static func sortedLadder(for anchor: Date, calendar: Calendar) -> [CrownMilestone] {
        ladder.enumerated()
            .map { (date: $0.element.date(anchor: anchor, calendar: calendar), index: $0.offset, milestone: $0.element) }
            .sorted { ($0.date, $0.index) < ($1.date, $1.index) }
            .map(\.milestone)
    }

    /// The next unreached milestone given an anchor, by date. nil if the
    /// couple has already passed every entry in the ladder (which is a great
    /// problem to have).
    static func next(after anchor: Date, now: Date = Date(), calendar: Calendar = .current) -> CrownMilestone? {
        sortedLadder(for: anchor, calendar: calendar)
            .first { !$0.isReached(anchor: anchor, now: now, calendar: calendar) }
    }

    /// All milestones already reached, oldest first (by date).
    static func reached(after anchor: Date, now: Date = Date(), calendar: Calendar = .current) -> [CrownMilestone] {
        sortedLadder(for: anchor, calendar: calendar)
            .filter { $0.isReached(anchor: anchor, now: now, calendar: calendar) }
    }

    /// The ladder entry with this `id` ("d100", "y2", …), e.g. from a crown
    /// reminder's payload. nil for anything not on the ladder.
    static func milestone(id: String) -> CrownMilestone? {
        ladder.first { $0.id == id }
    }

    /// Reached today. Kept for existing callers; the celebration now uses
    /// `isRecentlyReached(anchor:now:withinDays:calendar:)`.
    func isFreshlyReached(anchor: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        daysUntil(anchor: anchor, now: now, calendar: calendar) == 0
    }
}
