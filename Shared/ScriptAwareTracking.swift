//
//  ScriptAwareTracking.swift
//  Coupley (app and widget)
//
//  Letter-spacing for eyebrows and small caps labels, skipped for scripts it
//  breaks.
//

import SwiftUI

enum ScriptSpacing {

    /// False when the app runs in a language whose script must not be
    /// letter-spaced: Arabic and Hebrew letters join or sit on a baseline that
    /// tracking pulls apart, Thai and Devanagari vowel and tone marks drift off
    /// their letters, and CJK and Hangul are set on their own grid.
    nonisolated static let allowsTracking: Bool = {
        let resolved = Bundle.main.preferredLocalizations.first ?? "en"
        let code = Locale(identifier: resolved).language.languageCode?.identifier ?? "en"
        return !untrackedLanguages.contains(code)
    }()

    private nonisolated static let untrackedLanguages: Set<String> = [
        "ar", "fa", "ur", "he", "yi",           // Arabic and Hebrew scripts
        "hi", "mr", "ne", "bn", "pa", "gu",     // Devanagari and related
        "ta", "te", "kn", "ml", "si",
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
}
