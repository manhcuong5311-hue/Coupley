//
//  CurrencyFormatting.swift
//  Coupley
//
//  Single entry point for turning a Double + ISO code into a display string.
//  Replaces the locale-only `NumberFormatter().numberStyle = .currency` pattern
//  that silently re-symbol'd amounts based on the viewer's device — the bug
//  where a US partner saw "$1,000" and a Vietnamese partner saw "1.000 ₫" for
//  the same goal target.
//
//  Rule: the *currency* is fixed by the stored code on the document; only
//  grouping/decimal separators come from `Locale.current`.
//

import Foundation

enum CurrencyFormatting {

    /// Formats `value` using the given ISO 4217 `code`. The currency is locked
    /// to `code` regardless of device locale; locale only influences grouping
    /// and decimal separators (e.g. "$1,000" vs "$1.000").
    ///
    /// Whole numbers render with no decimals; non-whole numbers get up to 2.
    /// This keeps "$5,000" tidy without losing precision on "$12.50".
    static func format(_ value: Double, code: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.locale = Locale.current
        formatter.maximumFractionDigits = value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2

        if let s = formatter.string(from: NSNumber(value: value)) {
            return s
        }
        // Defensive fallback. NumberFormatter virtually never returns nil for
        // a finite Double, but if it does we'd rather show the right symbol
        // than crash or render something misleading.
        let info = CurrencyCatalog.info(for: code)
        return "\(info.symbol)\(Int(value))"
    }
}
