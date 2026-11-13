//
//  ContentL10n.swift
//  Coupley
//
//  Display-time translation of content banks: quiz questions and options,
//  daily photo prompts, micro-action ideas, suggestion templates.
//
//  These strings are DATA as well as copy. Their English ("base") form is
//  what gets written to Firestore and what older documents are matched
//  against (see PRE_L10N_AUDIT.md, A2/A3/A16), so the base text must never
//  change with the user's language. Only the display path goes through
//  here: the base text is the key into the "Content" string catalog
//  (Coupley/Core/Localization/Content.xcstrings), and a missing translation
//  falls back to the base text itself, so an untranslated item reads as
//  consistent English rather than breaking.
//
//  Chrome (buttons, titles, labels, errors) does NOT go through here; it
//  uses SwiftUI literals, String(localized:) or LocalizedStringResource and
//  lives in Shared/Localizable.xcstrings.
//

import Foundation

nonisolated enum ContentL10n {

    /// The catalog table that holds content-bank translations.
    static let table = "Content"

    /// The display form of a base-language content string, in the user's
    /// language when the Content catalog has it, otherwise `base` unchanged.
    static func text(_ base: String) -> String {
        guard !base.isEmpty else { return base }
        return Bundle.main.localizedString(forKey: base, value: base, table: table)
    }
}
