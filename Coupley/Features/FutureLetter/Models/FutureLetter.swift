//
//  FutureLetter.swift
//  Coupley
//
//  A letter one partner seals for the other, readable only from a moment the
//  sender picks.
//
//  Two documents per letter, same id, written in ONE batch:
//
//    couples/{c}/futureLetters/{id}       The envelope: who, to whom, when.
//                                         Both partners read it, so Home can
//                                         pin it with a countdown. It never
//                                         carries anything the sender wrote.
//    couples/{c}/futureLetterBodies/{id}  The words. The rules let the
//                                         recipient `get` it only once the
//                                         SERVER clock has passed `opensAt`,
//                                         and nobody can list the collection.
//
//  The device clock only decides what the screen shows: countdowns, the flip
//  to "ready" and the local reminder. Whether the words can be read is decided
//  by `request.time` in firestore.rules, so changing a phone's clock shows an
//  early "ready" at most, never the letter.
//

import Foundation
import FirebaseFirestore

extension FirestorePath {
    static func futureLetters(coupleId: String) -> String {
        "\(couples)/\(coupleId)/futureLetters"
    }

    static func futureLetterBodies(coupleId: String) -> String {
        "\(couples)/\(coupleId)/futureLetterBodies"
    }
}

// MARK: - Envelope

/// Decode with `ServerTimestampBehavior.estimate`: `sealedAt` and `openedAt`
/// are server timestamps, and while one is pending it would otherwise decode
/// as nil. Any field added later must be optional — reads are
/// `try? data(as:)`, and a document that fails to decode silently disappears.
struct FutureLetter: Identifiable, Codable, Equatable, Hashable {
    @DocumentID var firestoreId: String?
    let id: String
    let fromUserId: String
    let toUserId: String
    let opensAt: Date
    var sealedAt: Date? = nil
    var openedAt: Date? = nil

    /// When it was sealed, for display. Only a malformed document lacks it.
    var sealedMoment: Date { sealedAt ?? opensAt }

    func phase(viewer: String, now: Date) -> FutureLetterPhase {
        if toUserId == viewer {
            if openedAt != nil { return .openedByMe }
            return now >= opensAt ? .readyForMe : .sealedForMe
        }
        if openedAt != nil { return .openedByPartner }
        return now >= opensAt ? .waitingForPartner : .sealedByMe
    }
}

// MARK: - Body

/// Carries its own copy of from/to/opensAt because the rules gate the read on
/// this document's fields alone; nothing can change them after sealing.
struct FutureLetterBody: Codable, Equatable {
    let fromUserId: String
    let toUserId: String
    let opensAt: Date
    let text: String
}

// MARK: - Phase

enum FutureLetterPhase: Equatable {
    /// I am the recipient.
    case sealedForMe, readyForMe, openedByMe
    /// I am the sender.
    case sealedByMe, waitingForPartner, openedByPartner
}

enum FutureLetterOpenError: Error, Equatable {
    /// The server's clock has not reached `opensAt` (this device's is ahead).
    case notYet
    case offline
    /// Unsent, purged, or never fully written.
    case unavailable
    case other
}

// MARK: - Schedule

enum FutureLetterSchedule {
    #if DEBUG
    /// Short in Debug so a letter's flip can be watched on two simulators.
    static let minimumLead: TimeInterval = 2 * 60
    #else
    static let minimumLead: TimeInterval = 60 * 60
    #endif
    /// "1 hour" ("2 minutes" in Debug), worded and pluralized by Foundation
    /// in the user's language.
    static var minimumLeadDescription: String {
        Duration.seconds(minimumLead).formatted(.units(allowed: [.hours, .minutes], width: .wide))
    }
    /// Ten years. The rules allow 3,700 days, a little more than this.
    static let maximumLead: TimeInterval = 3650 * 86_400
    /// Same hour the Memory Capsule reminders use.
    static let defaultHour = 9
    static let maxCharacters = 10_000
    /// How long "Sam opened your letter" stays pinned on the sender's Home.
    static let receiptWindow: TimeInterval = 24 * 3600

    /// The earliest moment the picker offers, rounded UP to a whole minute.
    static func earliest(now: Date, calendar: Calendar = .current) -> Date {
        let raw = now.addingTimeInterval(minimumLead)
        let start = normalized(raw, calendar: calendar)
        return start < raw ? start.addingTimeInterval(60) : start
    }

    static func latest(now: Date) -> Date {
        now.addingTimeInterval(maximumLead)
    }

    /// Tomorrow at 9:00 AM local, or the earliest allowed moment if later.
    static func defaultOpensAt(now: Date, calendar: Calendar = .current) -> Date {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let nine = calendar.date(bySettingHour: defaultHour, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        return max(nine, earliest(now: now, calendar: calendar))
    }

    /// Drops the seconds, so the stored instant is a whole minute.
    static func normalized(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .minute, for: date)?.start ?? date
    }

    /// One minute of grace below the minimum: the picker's lower bound was
    /// computed when the screen opened, and time has passed since.
    static func isValid(_ opensAt: Date, now: Date) -> Bool {
        opensAt >= now.addingTimeInterval(minimumLead - 60) && opensAt <= latest(now: now)
    }
}

// MARK: - Formatting

/// Pure formatting in the viewer's own calendar and time zone, in the
/// viewer's language. Every result is display text: never store or compare it.
enum FutureLetterClock {

    /// "today at 9:00 AM", "tomorrow at 9:00 AM", "yesterday at 9:14 AM",
    /// "Thu, Dec 25 at 9:00 AM", or "Thu, Dec 25, 2027 at 9:00 AM" when the
    /// year differs. Callers put it after "Opens", "Opened", "Unsealed" or
    /// "Ready since".
    static func moment(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) {
            return String(localized: "today at \(time)",
                          comment: "A moment, as in 'Opens today at 9:00 AM'. %@ is a time.")
        }
        if let next = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: next) {
            return String(localized: "tomorrow at \(time)",
                          comment: "A moment, as in 'Opens tomorrow at 9:00 AM'. %@ is a time.")
        }
        if let previous = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: previous) {
            return String(localized: "yesterday at \(time)",
                          comment: "A moment, as in 'Opened yesterday at 9:14 AM'. %@ is a time.")
        }
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day()
        if calendar.component(.year, from: date) != calendar.component(.year, from: now) {
            style = style.year()
        }
        let day = date.formatted(style)
        return String(localized: "\(day) at \(time)",
                      comment: "A moment: a date, then a time, as in 'Thu, Dec 25 at 9:00 AM'.")
    }

    /// "Nov 13", or "Nov 13, 2025" when the year differs. `locale` is only
    /// for the letter reminder, whose copy stays English.
    static func shortDate(_ date: Date, now: Date, calendar: Calendar = .current,
                          locale: Locale = .autoupdatingCurrent) -> String {
        var style = Date.FormatStyle.dateTime.month(.abbreviated).day().locale(locale)
        if calendar.component(.year, from: date) != calendar.component(.year, from: now) {
            style = style.year()
        }
        return date.formatted(style)
    }

    /// "today", "yesterday" or "on Nov 13", as in "Sam sealed it today".
    static func sealedPhrase(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return String(localized: "today", comment: "When a letter was sealed, as in 'Sam sealed it today'.")
        }
        if let previous = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: previous) {
            return String(localized: "yesterday", comment: "When a letter was sealed, as in 'Sam sealed it yesterday'.")
        }
        let day = shortDate(date, now: now, calendar: calendar)
        return String(localized: "on \(day)",
                      comment: "When a letter was sealed, as in 'Sam sealed it on Nov 13'. %@ is a date.")
    }

    /// "Now", "1 min" … "59 min" (rounded up), "1 hr" … "23 hr" (rounded
    /// down), then "1 day" / "12 days" counted in calendar days.
    static func shortCountdown(to opensAt: Date, now: Date, calendar: Calendar = .current) -> String {
        let remaining = opensAt.timeIntervalSince(now)
        if remaining <= 0 {
            return String(localized: "Now", comment: "Countdown chip on a sealed letter: it opens now.")
        }
        if let minutes = minutesLeft(remaining) {
            return String(localized: "\(minutes) min", comment: "Countdown chip on a sealed letter: minutes left, abbreviated.")
        }
        if let hours = hoursLeft(remaining, opensAt: opensAt, now: now, calendar: calendar) {
            return String(localized: "\(hours) hr", comment: "Countdown chip on a sealed letter: hours left, abbreviated.")
        }
        let days = calendarDays(from: now, to: opensAt, calendar: calendar)
        return days == 1
            ? String(localized: "1 day", comment: "Countdown chip on a sealed letter: one day left.")
            : String(localized: "\(days) days", comment: "Countdown chip on a sealed letter: days left.")
    }

    /// Same buckets as `shortCountdown`, split for a big number and its unit:
    /// (12, "days until it opens"), (5, "hours until it opens"), (42, "minutes until it opens").
    static func bigCountdown(to opensAt: Date, now: Date, calendar: Calendar = .current) -> (value: Int, unit: String) {
        let remaining = max(0, opensAt.timeIntervalSince(now))
        if let minutes = minutesLeft(max(remaining, 1)) {
            return (minutes, untilItOpens(.minutes, count: minutes))
        }
        if let hours = hoursLeft(remaining, opensAt: opensAt, now: now, calendar: calendar) {
            return (hours, untilItOpens(.hours, count: hours))
        }
        let days = calendarDays(from: now, to: opensAt, calendar: calendar)
        return (days, untilItOpens(.days, count: days))
    }

    private enum CountdownUnit { case minutes, hours, days }

    /// The words under the big countdown number, "days until it opens".
    ///
    /// The number is on screen already, so no language repeats it here, but
    /// most languages need it to choose a plural form (Russian has three for
    /// "days"). The string catalog only accepts plural forms that reference
    /// the number, so each translation keeps it and
    /// `CountedCaption.removingCount(from:)` takes it out again. English, the
    /// source language, has only "1" and "not 1": it keeps two plain phrases,
    /// which read right with or without a catalog.
    private static func untilItOpens(_ unit: CountdownUnit, count: Int) -> String {
        if appRunsInEnglish {
            switch unit {
            case .minutes: return count == 1 ? "minute until it opens" : "minutes until it opens"
            case .hours:   return count == 1 ? "hour until it opens" : "hours until it opens"
            case .days:    return count == 1 ? "day until it opens" : "days until it opens"
            }
        }
        let phrase: String
        switch unit {
        case .minutes:
            phrase = String(localized: "\(count) minutes until it opens",
                            comment: "Under a big countdown number shown above it. Keep the number: the app removes it before showing the text, so write it to read naturally without the number ('%lld days until it opens' shows as 'days until it opens').")
        case .hours:
            phrase = String(localized: "\(count) hours until it opens",
                            comment: "Under a big countdown number shown above it. Keep the number: the app removes it before showing the text, so write it to read naturally without the number ('%lld days until it opens' shows as 'days until it opens').")
        case .days:
            phrase = String(localized: "\(count) days until it opens",
                            comment: "Under a big countdown number shown above it. Keep the number: the app removes it before showing the text, so write it to read naturally without the number ('%lld days until it opens' shows as 'days until it opens').")
        }
        return CountedCaption.removingCount(from: phrase)
    }

    /// Whether the localization the app resolved for this launch is English,
    /// as it is for any language the app does not ship. A language change
    /// relaunches the app, so this is read once.
    private static let appRunsInEnglish: Bool = {
        guard let resolved = Bundle.main.preferredLocalizations.first, resolved != "Base" else { return true }
        return Locale(identifier: resolved).language.languageCode == .english
    }()

    /// Whole minutes, rounded up, while under an hour. Rounding up the last
    /// seconds of the hour gives 60, which is "1 hr", not "60 min".
    private static func minutesLeft(_ remaining: TimeInterval) -> Int? {
        guard remaining < 3600 else { return nil }
        let minutes = max(1, Int((remaining / 60).rounded(.up)))
        return minutes < 60 ? minutes : nil
    }

    /// Whole hours, rounded down, under a day, and also for anything still
    /// on today's date: on a 25-hour fall-back day a letter opening tonight
    /// is not "1 day" away.
    private static func hoursLeft(_ remaining: TimeInterval, opensAt: Date, now: Date, calendar: Calendar) -> Int? {
        guard remaining < 86_400 || calendar.isDate(opensAt, inSameDayAs: now) else { return nil }
        return max(1, Int(remaining / 3600))
    }

    /// Calendar days between the two dates, counted noon to noon: midnight
    /// does not exist on a DST-start day in some zones, and noon always does.
    private static func calendarDays(from now: Date, to date: Date, calendar: Calendar) -> Int {
        func noon(_ day: Date) -> Date {
            calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
        }
        let days = calendar.dateComponents([.day], from: noon(now), to: noon(date)).day ?? 1
        return max(1, days)
    }
}
