//
//  CurrencyCatalog.swift
//  Coupley
//
//  Curated list of currencies the goal/contribution UI supports. Each entry
//  carries the ISO 4217 code (the source of truth, stored on docs), a display
//  flag + symbol, and a `quickBaseUnit` that drives the per-currency
//  contribution chips so a Vietnamese user doesn't see "+₫25" suggestions.
//

import Foundation

struct CurrencyInfo: Identifiable, Equatable, Hashable {
    /// ISO 4217 code. Stored on Firestore, used everywhere as the source of truth.
    let code: String
    let name: String
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
}

enum CurrencyCatalog {

    /// Hand-curated top-tier currencies. Order matters — the picker shows them
    /// in this order under "Popular" before falling back to alphabetical.
    static let all: [CurrencyInfo] = [
        CurrencyInfo(code: "USD", name: "US Dollar",          symbol: "$",   flag: "🇺🇸", quickBaseUnit: 25),
        CurrencyInfo(code: "EUR", name: "Euro",               symbol: "€",   flag: "🇪🇺", quickBaseUnit: 25),
        CurrencyInfo(code: "GBP", name: "British Pound",      symbol: "£",   flag: "🇬🇧", quickBaseUnit: 25),
        CurrencyInfo(code: "JPY", name: "Japanese Yen",       symbol: "¥",   flag: "🇯🇵", quickBaseUnit: 1_000),
        CurrencyInfo(code: "VND", name: "Vietnamese Dong",    symbol: "₫",   flag: "🇻🇳", quickBaseUnit: 50_000),
        CurrencyInfo(code: "SGD", name: "Singapore Dollar",   symbol: "S$",  flag: "🇸🇬", quickBaseUnit: 25),
        CurrencyInfo(code: "AUD", name: "Australian Dollar",  symbol: "A$",  flag: "🇦🇺", quickBaseUnit: 25),
        CurrencyInfo(code: "CAD", name: "Canadian Dollar",    symbol: "C$",  flag: "🇨🇦", quickBaseUnit: 25),
        CurrencyInfo(code: "CNY", name: "Chinese Yuan",       symbol: "¥",   flag: "🇨🇳", quickBaseUnit: 100),
        CurrencyInfo(code: "KRW", name: "South Korean Won",   symbol: "₩",   flag: "🇰🇷", quickBaseUnit: 10_000),
        CurrencyInfo(code: "INR", name: "Indian Rupee",       symbol: "₹",   flag: "🇮🇳", quickBaseUnit: 500),
        CurrencyInfo(code: "THB", name: "Thai Baht",          symbol: "฿",   flag: "🇹🇭", quickBaseUnit: 200),
        CurrencyInfo(code: "PHP", name: "Philippine Peso",    symbol: "₱",   flag: "🇵🇭", quickBaseUnit: 500),
        CurrencyInfo(code: "IDR", name: "Indonesian Rupiah",  symbol: "Rp",  flag: "🇮🇩", quickBaseUnit: 50_000),
        CurrencyInfo(code: "MYR", name: "Malaysian Ringgit",  symbol: "RM",  flag: "🇲🇾", quickBaseUnit: 50),
        CurrencyInfo(code: "HKD", name: "Hong Kong Dollar",   symbol: "HK$", flag: "🇭🇰", quickBaseUnit: 100),
        CurrencyInfo(code: "TWD", name: "Taiwan Dollar",      symbol: "NT$", flag: "🇹🇼", quickBaseUnit: 500),
        CurrencyInfo(code: "NZD", name: "New Zealand Dollar", symbol: "NZ$", flag: "🇳🇿", quickBaseUnit: 25),
        CurrencyInfo(code: "CHF", name: "Swiss Franc",        symbol: "CHF", flag: "🇨🇭", quickBaseUnit: 25),
        CurrencyInfo(code: "MXN", name: "Mexican Peso",       symbol: "$",   flag: "🇲🇽", quickBaseUnit: 200),
        CurrencyInfo(code: "BRL", name: "Brazilian Real",     symbol: "R$",  flag: "🇧🇷", quickBaseUnit: 50),
        CurrencyInfo(code: "ZAR", name: "South African Rand", symbol: "R",   flag: "🇿🇦", quickBaseUnit: 200),
        CurrencyInfo(code: "AED", name: "UAE Dirham",         symbol: "د.إ", flag: "🇦🇪", quickBaseUnit: 100),
        CurrencyInfo(code: "SAR", name: "Saudi Riyal",        symbol: "﷼",   flag: "🇸🇦", quickBaseUnit: 100)
    ]

    /// Hard fallback when device locale gives us a code we don't have in the
    /// catalog. USD because it's globally legible.
    static let fallback: CurrencyInfo = all[0]

    /// Lookup by ISO code. Always returns *something* — falls back to USD so
    /// callers don't have to deal with optionals on the hot path.
    static func info(for code: String) -> CurrencyInfo {
        all.first { $0.code == code } ?? fallback
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
