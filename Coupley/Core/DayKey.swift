//
//  DayKey.swift
//  Coupley
//
//  The one formatter for day-granular Firestore keys.
//
//  `SyncScore.date` is a document id AND the range key for
//  `whereField("date", isGreaterThanOrEqualTo:)`, so it must produce the same
//  string on every device regardless of the owner's region settings.
//
//  A bare `DateFormatter()` inherits `Locale.current` and `Calendar.current`,
//  which means `"yyyy-MM-dd"` renders as:
//
//      th_TH (Buddhist)   2568-11-13
//      ja_JP (Japanese)   0007-11-13
//      ar_SA              ١٤٤٧-٠٥-٢٢
//
//  Two partners in different regions then write keys neither can read back,
//  and the string range query returns nothing with no error.
//
//  The parse side is worse than the write side: a Buddhist-calendar device
//  does not fail on "2025-11-13", it reads 2025 as a Buddhist year and hands
//  back a date in 1482 — so the chart renders a plausible, wrong weekday.
//
//  Pinning the locale alone is not enough: `calendar` is a separate property
//  and stays on the device's. Both must be set, and `en_US_POSIX` is the
//  documented choice for fixed-format machine strings.
//

import Foundation

enum DayKey {

    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// `2026-11-13` for the given instant, stable across every device region.
    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    /// Parses a key written by `string(from:)`. Returns nil for anything else
    /// rather than guessing, so a corrupt key shows as missing data instead of
    /// as a date five centuries off.
    static func date(from key: String) -> Date? {
        formatter.date(from: key)
    }

    /// Today's key.
    static var today: String { string(from: Date()) }
}
