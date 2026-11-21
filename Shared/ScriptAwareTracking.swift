//
//  ScriptAwareTracking.swift
//  Coupley (app and widget)
//
//  Letter-spacing for eyebrows and small caps labels, skipped for scripts it
//  breaks, and the separator between two short facts.
//

import SwiftUI

enum ScriptSpacing {

    /// False when the app runs in a language whose script must not be
    /// letter-spaced: Arabic and Hebrew letters join or sit on a baseline that
    /// tracking pulls apart, Thai and Devanagari vowel and tone marks drift off
    /// their letters, and CJK and Hangul are set on their own grid.
    nonisolated static let allowsTracking: Bool = !untrackedLanguages.contains(languageCode)

    /// The app's " · " between two short facts drawn side by side ("Since 26
    /// Jan 2026 · Edit"). The zero of Arabic, Persian and Pashto digits is a
    /// dot, so beside a number a middle dot reads as a digit ("1 ·" as 10):
    /// those languages get a spaced dash, here and in their translations.
    nonisolated static let factSeparator: String = " \(factMark) "

    /// The separator's mark alone, for a row that spaces its own parts.
    nonisolated static let factMark: String = dotZeroLanguages.contains(languageCode) ? "–" : "·"

    /// Space added between the lines of every paragraph. Khmer and Burmese
    /// stack marks under one line and over the next, and at the system's
    /// line height they collide (in Khmer "និង" then reads as "នឹង"); Urdu's
    /// slanted Nastaliq runs into the line above; Telugu comes close. A view
    /// that sets its own line spacing keeps it.
    nonisolated static let extraLineSpacing: CGFloat = [
        "km": 4, "my": 4, "ur": 4, "te": 2,
    ][languageCode] ?? 0

    /// The language the app is running in.
    private nonisolated static let languageCode: String = {
        let resolved = Bundle.main.preferredLocalizations.first ?? "en"
        return Locale(identifier: resolved).language.languageCode?.identifier ?? "en"
    }()

    private nonisolated static let dotZeroLanguages: Set<String> = ["ar", "fa", "ps"]

    private nonisolated static let untrackedLanguages: Set<String> = [
        "ar", "fa", "ur", "ps", "he", "yi",     // Arabic and Hebrew scripts
        "hi", "mr", "ne", "bn", "as", "pa",     // Devanagari and related
        "gu", "or", "ta", "te", "kn", "ml", "si",
        "th", "lo", "km", "my",                 // Thai and other Southeast Asian
        "ja", "ko", "zh",                       // CJK and Hangul
    ]
}

extension Text {
    /// `tracking(_:)`, or none for scripts letter-spacing breaks.
    func scriptAwareTracking(_ value: CGFloat) -> Text {
        tracking(ScriptSpacing.allowsTracking ? value : 0)
    }

    /// `kerning(_:)`, or none for scripts letter-spacing breaks.
    func scriptAwareKerning(_ value: CGFloat) -> Text {
        kerning(ScriptSpacing.allowsTracking ? value : 0)
    }
}

extension View {
    /// `tracking(_:)`, or none for scripts letter-spacing breaks.
    func scriptAwareTracking(_ value: CGFloat) -> some View {
        tracking(ScriptSpacing.allowsTracking ? value : 0)
    }

    /// `kerning(_:)`, or none for scripts letter-spacing breaks.
    func scriptAwareKerning(_ value: CGFloat) -> some View {
        kerning(ScriptSpacing.allowsTracking ? value : 0)
    }

    /// `lineSpacing(_:)`, plus the room the tallest scripts need between
    /// lines (`ScriptSpacing.extraLineSpacing`). Text without a line spacing
    /// of its own gets that room from the app's root view.
    func scriptAwareLineSpacing(_ value: CGFloat) -> some View {
        lineSpacing(value + ScriptSpacing.extraLineSpacing)
    }
}
