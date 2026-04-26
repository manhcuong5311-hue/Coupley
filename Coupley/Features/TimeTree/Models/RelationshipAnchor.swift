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

import Foundation
import FirebaseFirestore

// MARK: - Relationship Anchor

struct RelationshipAnchor: Codable, Equatable, Hashable {
    /// The day the relationship started — what day-counting and tree
    /// growth are computed from. Stored as a Firestore Timestamp.
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

    /// Whole days elapsed between the anchor and `now`, computed at
    /// day-granularity in the device's calendar. Always non-negative.
    func daysTogether(now: Date = Date(), calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: startDate)
        let today = calendar.startOfDay(for: now)
        let comps = calendar.dateComponents([.day], from: start, to: today)
        return max(0, comps.day ?? 0)
    }

    /// Date of the next yearly anniversary on or after `now`. If today is
    /// the anniversary, returns today.
    func nextYearlyAnniversary(now: Date = Date(), calendar: Calendar = .current) -> Date {
        let startOfNow = calendar.startOfDay(for: now)
        let startOfStart = calendar.startOfDay(for: startDate)

        // The anniversary candidate this year keeps the original month/day.
        var components = calendar.dateComponents([.month, .day], from: startOfStart)
        components.year = calendar.component(.year, from: startOfNow)

        guard let thisYear = calendar.date(from: components) else { return startOfStart }
        if thisYear >= startOfNow { return thisYear }

        components.year = (components.year ?? 0) + 1
        return calendar.date(from: components) ?? thisYear
    }

    /// Whole years completed at `now`. 0 before the first anniversary.
    func yearsCompleted(now: Date = Date(), calendar: Calendar = .current) -> Int {
        let comps = calendar.dateComponents(
            [.year],
            from: calendar.startOfDay(for: startDate),
            to: calendar.startOfDay(for: now)
        )
        return max(0, comps.year ?? 0)
    }

    /// Days until the next yearly anniversary. 0 if today is the day.
    func daysUntilNextAnniversary(now: Date = Date(), calendar: Calendar = .current) -> Int {
        let target = calendar.startOfDay(for: nextYearlyAnniversary(now: now, calendar: calendar))
        let today  = calendar.startOfDay(for: now)
        let comps  = calendar.dateComponents([.day], from: today, to: target)
        return max(0, comps.day ?? 0)
    }
}
