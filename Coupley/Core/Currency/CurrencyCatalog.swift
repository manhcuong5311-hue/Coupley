//
//  CurrencyCatalog.swift
//  Coupley
//
//  Curated list of currencies the goal/contribution UI supports. Each entry
//  carries the ISO 4217 code (the source of truth, stored on docs), a display
//  flag + symbol, and a `quickBaseUnit` that drives the per-currency
//  contribution chips so a Vietnamese user doesn't see "+₫25" suggestions.
//  Names are not stored here: Foundation ships every one in every language.
//

import Foundation

struct CurrencyInfo: Identifiable, Equatable, Hashable {
    /// ISO 4217 code. Stored on Firestore, used everywhere as the source of truth.
    let code: String
    /// Best-effort display symbol. Real formatting always goes through
    /// `CurrencyFormatting`, which lets `NumberFormatter` produce the locale-correct
    /// glyph + position; this is only for compact UI hints (input prefix, badge).
    let symbol: String
    let flag: String
    /// One "small" round-amount tap chip in this currency. Chips are derived as
    /// `[base, 2*base, 5*base, 10*base, 20*base]` so a USD user gets $25/$50/$100/$250/$500
    /// while a VND user gets ₫50K/₫100K/₫250K/₫500K/₫1M.
    let quickBaseUnit: Double

    var id: String { code }

    /// The currency's name in the user's language ("US Dollar", "Đô la Mỹ",
    /// "Dólar estadounidense"), from Foundation's locale data, so it needs no
    /// catalog entry. Display only: `code` is what gets stored and compared.
    var name: String { Self.name(for: code, locale: .current) }

    /// `locale`'s name for `code`, with its first letter capitalised the way
    /// that locale does it (the name stands alone as a row title), or the
    /// code itself if Foundation has no name for it.
    static func name(for code: String, locale: Locale) -> String {
        guard let name = locale.localizedString(forCurrencyCode: code),
              let first = name.first else { return code }
        return String(first).uppercased(with: locale) + name.dropFirst()
    }

    /// Whether this currency matches a picker search: case- and
    /// diacritic-insensitive (`localizedStandardContains`) on the ISO code,
    /// the localized name and the symbol. The English name matches too, so
    /// "dollar" works in every language.
    func matches(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        let foldedNeedle = Self.searchFolded(needle)
        let englishName = Self.name(for: code, locale: Locale(identifier: "en"))
        return [code, name, symbol, englishName].contains { field in
            field.localizedStandardContains(needle)
                || Self.searchFolded(field).localizedStandardContains(foldedNeedle)
        }
    }

    /// `localizedStandardContains` folds case and combining accents, but not
    /// letters that are separate in Unicode, such as Vietnamese "Đ": without
    /// this "do la" would not find "Đô la Mỹ". Latin-ASCII only touches Latin
    /// letters ("Đô la Mỹ" → "Do la My"); other scripts pass through.
    private static func searchFolded(_ text: String) -> String {
        text.applyingTransform(StringTransform("Latin-ASCII"), reverse: false) ?? text
    }
}

enum CurrencyCatalog {

    /// Hand-curated top-tier currencies. Order matters — the picker shows them
    /// in this order under "Popular" before falling back to alphabetical.
    static let all: [CurrencyInfo] = [
        CurrencyInfo(code: "USD", symbol: "$",   flag: "🇺🇸", quickBaseUnit: 25),
        CurrencyInfo(code: "EUR", symbol: "€",   flag: "🇪🇺", quickBaseUnit: 25),
        CurrencyInfo(code: "GBP", symbol: "£",   flag: "🇬🇧", quickBaseUnit: 25),
        CurrencyInfo(code: "JPY", symbol: "¥",   flag: "🇯🇵", quickBaseUnit: 1_000),
        CurrencyInfo(code: "VND", symbol: "₫",   flag: "🇻🇳", quickBaseUnit: 50_000),
        CurrencyInfo(code: "SGD", symbol: "S$",  flag: "🇸🇬", quickBaseUnit: 25),
        CurrencyInfo(code: "AUD", symbol: "A$",  flag: "🇦🇺", quickBaseUnit: 25),
        CurrencyInfo(code: "CAD", symbol: "C$",  flag: "🇨🇦", quickBaseUnit: 25),
        CurrencyInfo(code: "CNY", symbol: "¥",   flag: "🇨🇳", quickBaseUnit: 100),
        CurrencyInfo(code: "KRW", symbol: "₩",   flag: "🇰🇷", quickBaseUnit: 10_000),
        CurrencyInfo(code: "INR", symbol: "₹",   flag: "🇮🇳", quickBaseUnit: 500),
        CurrencyInfo(code: "THB", symbol: "฿",   flag: "🇹🇭", quickBaseUnit: 200),
        CurrencyInfo(code: "PHP", symbol: "₱",   flag: "🇵🇭", quickBaseUnit: 500),
        CurrencyInfo(code: "IDR", symbol: "Rp",  flag: "🇮🇩", quickBaseUnit: 50_000),
        CurrencyInfo(code: "MYR", symbol: "RM",  flag: "🇲🇾", quickBaseUnit: 50),
        CurrencyInfo(code: "HKD", symbol: "HK$", flag: "🇭🇰", quickBaseUnit: 100),
        CurrencyInfo(code: "TWD", symbol: "NT$", flag: "🇹🇼", quickBaseUnit: 500),
        CurrencyInfo(code: "NZD", symbol: "NZ$", flag: "🇳🇿", quickBaseUnit: 25),
        CurrencyInfo(code: "CHF", symbol: "CHF", flag: "🇨🇭", quickBaseUnit: 25),
        CurrencyInfo(code: "MXN", symbol: "$",   flag: "🇲🇽", quickBaseUnit: 200),
        CurrencyInfo(code: "BRL", symbol: "R$",  flag: "🇧🇷", quickBaseUnit: 50),
        CurrencyInfo(code: "ZAR", symbol: "R",   flag: "🇿🇦", quickBaseUnit: 200),
        CurrencyInfo(code: "AED", symbol: "د.إ", flag: "🇦🇪", quickBaseUnit: 100),
        CurrencyInfo(code: "SAR", symbol: "﷼",   flag: "🇸🇦", quickBaseUnit: 100)
    ]

    /// Hard fallback when device locale gives us a code we don't have in the
    /// catalog. USD because it's globally legible.
    static let fallback: CurrencyInfo = all[0]

    /// Lookup by ISO code. Always returns *something* — falls back to USD so
    /// callers don't have to deal with optionals on the hot path.
    static func info(for code: String) -> CurrencyInfo {
        all.first { $0.code == code } ?? fallback
    }

    /// The currency picker's search results, in catalog order: every
    /// currency when `query` is blank. See `CurrencyInfo.matches(_:)`.
    static func search(_ query: String) -> [CurrencyInfo] {
        all.filter { $0.matches(query) }
    }

    /// Best guess at the user's currency from device locale, used as the
    /// initial selection in the goal-create picker. The user can change it.
    static func deviceDefault() -> CurrencyInfo {
        let resolved: String
        if #available(iOS 16, *) {
            resolved = Locale.current.currency?.identifier ?? "USD"
        } else {
            resolved = Locale.current.currencyCode ?? "USD"
        }
        return info(for: resolved)
    }
}
