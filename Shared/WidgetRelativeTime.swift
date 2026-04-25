//
//  WidgetRelativeTime.swift
//  Coupley
//
//  Shared formatter for "Updated 2h ago" style strings. The widget
//  process can't safely create RelativeDateTimeFormatter on every render
//  (allocation-heavy); we cache one per process.
//

import Foundation

// MARK: - Formatter

enum WidgetRelativeTime {

    private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        f.dateTimeStyle = .numeric
        return f
    }()

    /// Returns "Just now" within 60s, otherwise the localized short form.
    static func string(for date: Date, now: Date = Date()) -> String {
        let elapsed = now.timeIntervalSince(date)
        if elapsed < 60 { return "Just now" }
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
