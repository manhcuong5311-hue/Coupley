//
//  CountedCaption.swift
//  Coupley
//
//  Captions drawn beside a number that is shown on its own ("292" over
//  "days together", "5" next to "check-ins").
//

import Foundation

enum CountedCaption {

    /// `phrase` without its first run of digits (in whatever digits the
    /// language writes) and the space that set it apart.
    ///
    /// A caption still has to agree with its number: Russian says "1 день",
    /// "2 дня", "5 дней". So the caption is localized as a plural key that
    /// carries the count ("\(n) days together"), which the string catalog
    /// requires every plural form to reference, and the number is then taken
    /// out again here. A translation that already leaves it out comes back
    /// unchanged.
    nonisolated static func removingCount(from phrase: String) -> String {
        guard let start = phrase.firstIndex(where: isDecimalDigit) else { return phrase }
        var end = start
        while end < phrase.endIndex, isDecimalDigit(phrase[end]) {
            end = phrase.index(after: end)
        }
        var head = String(phrase[..<start])
        var tail = String(phrase[end...])
        if tail.first?.isWhitespace == true {
            tail.removeFirst()
        } else if head.last?.isWhitespace == true {
            head.removeLast()
        }
        return (head + tail).trimmingCharacters(in: .whitespaces)
    }

    /// A decimal digit in any script (0-9, Arabic-Indic, Devanagari, Thai...).
    /// Not `Character.isWholeNumber`, which is also true for CJK numerals such
    /// as 一 in 一起 ("together"), and would cut them out of the caption.
    private nonisolated static func isDecimalDigit(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { $0.properties.numericType == .decimal }
    }
}
