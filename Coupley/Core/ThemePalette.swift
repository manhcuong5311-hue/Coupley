//
//  ThemePalette.swift
//  Coupley
//
//  Theme variants (Classic vs CoupleSync) define the full palette + shape language.
//  Read lazily from UserDefaults so dynamic UIColors can react to variant changes.
//

import SwiftUI
import UIKit

// MARK: - Theme Variant

enum ThemeVariant: String, CaseIterable, Identifiable {
    /// Warm beige + terracotta, soft and rounded (inspired by the CoupleSync mockup).
    case coupleSync
    /// The original rose→coral gradient look with ambient glows.
    case classic

    var id: String { rawValue }

    var label: String {
        switch self {
        case .coupleSync: return "CoupleSync"
        case .classic:    return "Classic"
        }
    }

    var tagline: String {
        switch self {
        case .coupleSync: return "Soft, warm, and calm"
        case .classic:    return "Bold rose gradient"
        }
    }

    var icon: String {
        switch self {
        case .coupleSync: return "leaf.fill"
        case .classic:    return "sparkles"
        }
    }

    // Shape language

    var buttonCornerRadius: CGFloat {
        switch self {
        case .coupleSync: return 28   // fully rounded pill
        case .classic:    return 18
        }
    }

    var cardCornerRadius: CGFloat {
        switch self {
        case .coupleSync: return 22
        case .classic:    return 20
        }
    }

    var showsAmbientGlow: Bool {
        switch self {
        case .coupleSync: return false
        case .classic:    return true
        }
    }

    var usesSolidPrimary: Bool {
        switch self {
        case .coupleSync: return true    // flat terracotta CTA
        case .classic:    return false   // gradient CTA
        }
    }

    // MARK: Current variant (read from AppStorage)

    private static let storageKey = "themeVariant"

    static var current: ThemeVariant {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? ""
        return ThemeVariant(rawValue: raw) ?? .coupleSync
    }
}

// MARK: - Palette (per-variant swatches)

enum Palette {

    // Backgrounds -----------------------------------------------------------

    static let backgroundTop = dynamic(
        classicDark:  rgb(0.07, 0.04, 0.15),
        classicLight: rgb(0.98, 0.96, 0.99),
        syncDark:     rgb(0.12, 0.09, 0.07),
        syncLight:    rgb(0.96, 0.94, 0.91)
    )

    static let backgroundMid = dynamic(
        classicDark:  rgb(0.09, 0.05, 0.18),
        classicLight: rgb(0.99, 0.95, 0.96),
        syncDark:     rgb(0.14, 0.10, 0.08),
        syncLight:    rgb(0.95, 0.92, 0.88)
    )

    static let backgroundBottom = dynamic(
        classicDark:  rgb(0.12, 0.06, 0.22),
        classicLight: rgb(1.00, 0.94, 0.92),
        syncDark:     rgb(0.17, 0.12, 0.09),
        syncLight:    rgb(0.94, 0.90, 0.85)
    )

    // Accents ---------------------------------------------------------------

    static let accentStart = dynamic(
        classicDark:  rgb(1.00, 0.38, 0.60),
        classicLight: rgb(1.00, 0.38, 0.60),
        syncDark:     rgb(0.85, 0.60, 0.54),
        syncLight:    rgb(0.78, 0.52, 0.46)     // terracotta (matches mockup CTA)
    )

    static let accentEnd = dynamic(
        classicDark:  rgb(1.00, 0.60, 0.35),
        classicLight: rgb(1.00, 0.60, 0.35),
        syncDark:     rgb(0.78, 0.52, 0.46),
        syncLight:    rgb(0.72, 0.47, 0.42)
    )

    // Surfaces --------------------------------------------------------------

    static let surfaceLight = dynamic(
        classicDark:  UIColor.white.withAlphaComponent(0.08),
        classicLight: UIColor.black.withAlphaComponent(0.04),
        syncDark:     rgb(0.21, 0.16, 0.12),
        syncLight:    rgb(0.92, 0.88, 0.83)     // warm beige card
    )

    static let surfaceMid = dynamic(
        classicDark:  UIColor.white.withAlphaComponent(0.12),
        classicLight: UIColor.black.withAlphaComponent(0.07),
        syncDark:     rgb(0.25, 0.19, 0.14),
        syncLight:    rgb(0.89, 0.84, 0.78)
    )

    static let divider = dynamic(
        classicDark:  UIColor.white.withAlphaComponent(0.10),
        classicLight: UIColor.black.withAlphaComponent(0.08),
        syncDark:     rgb(0.31, 0.25, 0.20),
        syncLight:    rgb(0.85, 0.80, 0.73)
    )

    // Text ------------------------------------------------------------------

    static let textPrimary = dynamic(
        classicDark:  .white,
        classicLight: .black,
        syncDark:     rgb(0.96, 0.93, 0.88),
        syncLight:    rgb(0.24, 0.20, 0.17)     // warm near-black
    )

    static let textSecondary = dynamic(
        classicDark:  UIColor.white.withAlphaComponent(0.62),
        classicLight: UIColor.black.withAlphaComponent(0.60),
        syncDark:     rgb(0.70, 0.63, 0.56),
        syncLight:    rgb(0.45, 0.40, 0.36)
    )

    static let textTertiary = dynamic(
        classicDark:  UIColor.white.withAlphaComponent(0.38),
        classicLight: UIColor.black.withAlphaComponent(0.42),
        syncDark:     rgb(0.52, 0.47, 0.42),
        syncLight:    rgb(0.60, 0.55, 0.50)
    )

    // MARK: - Helpers

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> UIColor {
        UIColor(red: r, green: g, blue: b, alpha: a)
    }

    /// Resolve dark/light/variant combination at render time via a dynamic UIColor.
    private static func dynamic(
        classicDark: UIColor,
        classicLight: UIColor,
        syncDark: UIColor,
        syncLight: UIColor
    ) -> Color {
        Color(uiColor: UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            switch ThemeVariant.current {
            case .classic:    return isDark ? classicDark : classicLight
            case .coupleSync: return isDark ? syncDark    : syncLight
            }
        })
    }
}
