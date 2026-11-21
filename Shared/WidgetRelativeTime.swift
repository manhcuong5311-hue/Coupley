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
        f.unitsStyle = RelativeTimeWording.needsFullUnits ? .full : .short
        f.dateTimeStyle = .numeric
        return f
    }()

    /// Returns "Just now" within 60s, otherwise the localized short form.
    static func string(for date: Date, now: Date = Date()) -> String {
        let elapsed = now.timeIntervalSince(date)
        if elapsed < 60 {
            return String(localized: "Just now", comment: "Widget: the partner's mood was shared less than a minute ago")
        }
        return RelativeTimeWording.orDate(formatter.localizedString(for: date, relativeTo: now),
                                          for: date, now: now)
    }
}

// MARK: - Languages without relative wording

/// iOS has no relative wording ("3 days ago") for some of the app's languages
/// (Kurdish, Yoruba, Igbo, Shona, Malagasy, Kinyarwanda, Cebuano and a few
/// more): its formatters answer with the bare root form, "-3 d". Those read
/// the day instead, or the time for a moment today.
enum RelativeTimeWording {

    /// True for the formatters' answer without wording: a sign, then a number.
    nonisolated static func isMissing(in phrase: String) -> Bool {
        var scalars = phrase.unicodeScalars.makeIterator()
        guard let sign = scalars.next(), sign == "-" || sign == "+" || sign == "\u{2212}",
              let next = scalars.next() else { return false }
        return next.properties.numericType != nil
    }

    /// Languages whose short relative forms are wrong or unreadable and
    /// whose full forms are right. Mongolian's short week is "7 хоног" (seven
    /// days), so one week ago reads "1 7 хоногийн өмнө", close to 17 days;
    /// Amharic's and Zulu's short forms have no singular ("1 weeks ago");
    /// Somali's are bare consonants ("1 tdbd khr") and Hebrew's a clipped
    /// "שב׳" for a week.
    nonisolated static var needsFullUnits: Bool {
        ["mn", "am", "zu", "so", "he"].contains(Locale.current.language.languageCode?.identifier ?? "")
    }

    /// `date` as a named phrase ("yesterday", "2 weeks ago"), or nil where
    /// the app language has no wording for it. Named phrases have their own
    /// gap: Kinyarwanda, Chichewa, Malagasy, Shona and Sundanese answer
    /// "last week" and "yesterday" in English, with no sign to tell by.
    nonisolated static func namedPhrase(for date: Date) -> String? {
        let style = Date.RelativeFormatStyle(presentation: .named, unitsStyle: .wide)
        let phrase = date.formatted(style)
        if isMissing(in: phrase) { return nil }
        if Locale.current.language.languageCode != .english,
           phrase == date.formatted(style.locale(Locale(identifier: "en"))) {
            return nil
        }
        return phrase
    }

    /// `phrase`, or the date where the phrase has no wording.
    nonisolated static func orDate(_ phrase: String, for date: Date, now: Date = Date()) -> String {
        isMissing(in: phrase) ? dateText(for: date, now: now) : phrase
    }

    /// The day, or the time for a moment today: what stands in for a phrase.
    nonisolated static func dateText(for date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        // The month in full: these languages' abbreviations are the ones
        // readers do not recognize ("rbn" for rêbendan).
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return date.formatted(.dateTime.day().month(.wide))
        }
        return date.formatted(.dateTime.day().month(.wide).year())
    }
}
