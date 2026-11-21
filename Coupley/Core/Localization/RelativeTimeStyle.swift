//
//  RelativeTimeStyle.swift
//  Coupley
//
//  The units style for short relative times such as "5h ago".
//

import Foundation

extension RelativeDateTimeFormatter {

    /// `.abbreviated` reads "5h ago" in English, but in Russian, French,
    /// Swedish, Norwegian and Romanian it is CLDR's narrow past form, a bare
    /// "-5 ч" / "-5 h". Every other language gets the short style, which reads
    /// as a phrase there ("5 ч назад", "il y a 5 h") and is just as compact
    /// in the rest. Three languages take the full style, where the short one
    /// is wrong (`RelativeTimeWording.needsFullUnits`).
    nonisolated static var compactUnitsStyle: UnitsStyle {
        if Locale.current.language.languageCode == .english { return .abbreviated }
        return RelativeTimeWording.needsFullUnits ? .full : .short
    }

    /// A short relative time for `date`: "5h ago", "in 3 days". Languages iOS
    /// has no relative wording for get the date itself (`RelativeTimeWording`).
    nonisolated static func compactString(for date: Date, relativeTo now: Date = Date()) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = compactUnitsStyle
        return RelativeTimeWording.orDate(formatter.localizedString(for: date, relativeTo: now),
                                          for: date, now: now)
    }
}
