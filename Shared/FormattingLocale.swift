//
//  FormattingLocale.swift
//  Coupley (app and widget)
//
//  Burmese numbers are formatted with Latin digits.
//

import Foundation

enum FormattingLocale {

    /// The preference iOS reads the current locale from. A process's own
    /// value wins over the device's, as it does for an Xcode scheme's App
    /// Region and for the `-AppleLocale` launch argument.
    private nonisolated static let localeKey = "AppleLocale"

    /// What this code last wrote there, so it only ever takes back its own value.
    private nonisolated static let markerKey = "coupley.formattingLocale.override"

    /// Call first thing at launch: Foundation reads the preference once per
    /// process, when the current locale is first used. A change made later
    /// applies from the next launch.
    ///
    /// Burmese: the rounded bold system font draws the Burmese digits ၂ and ၅
    /// broken ("၁၂" reads as "၁ |"). Numbers use Latin digits, as most
    /// Myanmar apps write them. Every other language is left alone, and an
    /// override written for an earlier language is taken back.
    ///
    /// Only what rides on the locale as a keyword can be changed this way.
    /// iOS always puts the app's own language into the current locale, so a
    /// language it has no calendar names for (Haitian Creole: "M11 21, Sat")
    /// cannot borrow another language's.
    nonisolated static func applyOverride(defaults: UserDefaults = .standard,
                                          appLanguage: String? = Bundle.main.preferredLocalizations.first,
                                          appDomain: String? = Bundle.main.bundleIdentifier) {
        let language = appLanguage.flatMap { Locale(identifier: $0).language.languageCode?.identifier }
        let ownValue = appDomain.flatMap { defaults.persistentDomain(forName: $0)?[localeKey] as? String }
        let ours = defaults.string(forKey: markerKey)
        let deviceValue = defaults.persistentDomain(forName: UserDefaults.globalDomain)?[localeKey] as? String

        if let wanted = override(forLanguage: language, deviceLocale: deviceValue ?? ownValue) {
            if ownValue != wanted { defaults.set(wanted, forKey: localeKey) }
            if ours != wanted { defaults.set(wanted, forKey: markerKey) }
        } else if let ours {
            // Only our own value: iOS or a launch argument may have set another since.
            if ownValue == ours { defaults.removeObject(forKey: localeKey) }
            defaults.removeObject(forKey: markerKey)
        }
    }

    /// The locale identifier to format with, or nil to keep the system's.
    nonisolated static func override(forLanguage language: String?, deviceLocale: String?) -> String? {
        let region = deviceLocale.flatMap { Locale(identifier: $0).region?.identifier }
        switch language {
        case "my": return "my_\(region ?? "MM")@numbers=latn"
        default:   return nil
        }
    }
}
