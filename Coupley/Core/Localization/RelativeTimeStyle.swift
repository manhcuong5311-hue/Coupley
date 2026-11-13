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
    /// in the rest.
    nonisolated static var compactUnitsStyle: UnitsStyle {
        Locale.current.language.languageCode == .english ? .abbreviated : .short
    }
}
