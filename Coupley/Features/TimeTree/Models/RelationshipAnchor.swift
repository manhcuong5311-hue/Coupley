//
//  RelationshipAnchor.swift
//  Coupley
//
//  The "when did our story begin" date that anchors the entire Time Tree.
//  Stored as a single document at couples/{coupleId}/timeTreeMeta/config so
//  it lives alongside other tree-level metadata we may add later (theme
//  preferences, shared mood tone, etc.) without polluting the top-level
//  couple doc.
//
//  The anchor is shared — when one partner sets it, both see it. The
//  most recent write wins (last-write-wins is acceptable here because
//  setting an anchor is a one-time, intentional act, and conflicts are
//  rare enough that surfacing them would be more confusing than useful).
//
//  The start date is a calendar DAY. New values are stored as 10:00 UTC of
//  the picked Gregorian day (`JourneyCalendarDay.storedMoment(forLocalDay:)`),
//  which 1.1/1.2 also read as that day from UTC-10 to UTC+13, and every
//  metric below counts from the day that value names
//  (`JourneyCalendarDay.localDay(ofStored:)`), so partners in different time
//  zones count the same days. Older values keep naming the viewer's local day.
//

import Foundation
import FirebaseFirestore

// MARK: - Relationship Anchor

struct RelationshipAnchor: Codable, Equatable, Hashable {
    /// The day the relationship started — what day-counting and tree
    /// growth are computed from. Stored as a Firestore Timestamp; read it
    /// through `JourneyCalendarDay.localDay(ofStored:)`, never directly.
    var startDate: Date
    /// Who set the anchor. Used for the "set by X" attribution row.
    var setBy: String
    /// Display name captured at the time the anchor was set, so we can
    /// show "Set by Alex" without round-tripping through the user doc.
    /// Optional because partner names aren't always known at write time.
    var setByName: String?
    var setAt: Date
    var updatedAt: Date

    init(
        startDate: Date,
        setBy: String,
        setByName: String? = nil,
        setAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.startDate = startDate
        self.setBy = setBy
        self.setByName = setByName
        self.setAt = setAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Derived metrics

extension RelationshipAnchor {

    /// The start of the day the start date names, in `calendar`.
    private func startDay(_ calendar: Calendar) -> Date {
        JourneyCalendarDay.localDay(ofStored: startDate, calendar: calendar)
    }

    /// The `years`-th anniversary of `start` (the start of that day). Adds
    /// whole GREGORIAN years like `CrownMilestone` does, so a Feb 29 start
    /// has its anniversary on Feb 28 in other years, the same day as its
    /// year crowns, and phones on other calendars agree with their partner.
    private func anniversary(_ years: Int, from start: Date, _ calendar: Calendar) -> Date {
        let gregorian = JourneyCalendarDay.gregorian(in: calendar)
        guard let date = gregorian.date(byAdding: .year, value: years, to: start) else {
            return .distantFuture
        }
        return calendar.startOfDay(for: date)
    }

    /// Whole days elapsed between the start day and `now`, computed at
    /// day-granularity in the device's calendar. Always non-negative.
    func daysTogether(now: Date = Date(), calendar: Calendar = .current) -> Int {
        let start = startDay(calendar)
        let today = calendar.startOfDay(for: now)
        let comps = calendar.dateComponents([.day], from: start, to: today)
        return max(0, comps.day ?? 0)
    }

    /// Date of the next yearly anniversary (1st, 2nd, …) on or after `now`.
    /// If today is an anniversary, returns today. The start day itself is not
    /// an anniversary.
    func nextYearlyAnniversary(now: Date = Date(), calendar: Calendar = .current) -> Date {
        let start = startDay(calendar)
        let today = calendar.startOfDay(for: now)
        // Begin one year below the elapsed count, so an off-by-one in the
        // calendar's own year arithmetic (Feb 29) can only make us step
        // forward, never skip the answer.
        let elapsed = JourneyCalendarDay.gregorian(in: calendar).dateComponents([.year], from: start, to: today).year ?? 0
        var years = max(1, elapsed - 1)
        var candidate = anniversary(years, from: start, calendar)
        while candidate < today {
            years += 1
            candidate = anniversary(years, from: start, calendar)
        }
        return candidate
    }

    /// Whole years completed at `now`. 0 before the first anniversary.
    /// Counts the same anniversaries as `nextYearlyAnniversary`.
    func yearsCompleted(now: Date = Date(), calendar: Calendar = .current) -> Int {
        let start = startDay(calendar)
        let today = calendar.startOfDay(for: now)
        let elapsed = JourneyCalendarDay.gregorian(in: calendar).dateComponents([.year], from: start, to: today).year ?? 0
        var years = max(0, elapsed + 1)
        while years > 0 && anniversary(years, from: start, calendar) > today {
            years -= 1
        }
        return years
    }

    /// Days until the next yearly anniversary. 0 if today is the day.
    func daysUntilNextAnniversary(now: Date = Date(), calendar: Calendar = .current) -> Int {
        let target = nextYearlyAnniversary(now: now, calendar: calendar)
        let today  = calendar.startOfDay(for: now)
        let comps  = calendar.dateComponents([.day], from: today, to: target)
        return max(0, comps.day ?? 0)
    }
}
