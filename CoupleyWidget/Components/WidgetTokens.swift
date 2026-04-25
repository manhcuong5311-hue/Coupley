//
//  WidgetTokens.swift
//  CoupleyWidget
//
//  Self-contained design tokens for the widget process. The main-app
//  Brand palette is intentionally NOT imported — widgets are rendered
//  outside the app process, can't read the live theme, and need a stable
//  appearance that looks great over both wallpaper and the photo
//  background. These tokens are tuned for those constraints.
//

import SwiftUI

// MARK: - Colors

enum WidgetPalette {

    // Romantic gradient — used when no couple photo is set.
    static let gradientTop    = Color(red: 1.00, green: 0.61, blue: 0.74) // soft rose
    static let gradientMid    = Color(red: 0.96, green: 0.42, blue: 0.62) // warm pink
    static let gradientBottom = Color(red: 0.55, green: 0.32, blue: 0.78) // dusk violet

    // Accent for milestones / celebratory moments
    static let goldStart = Color(red: 1.00, green: 0.78, blue: 0.42)
    static let goldEnd   = Color(red: 0.96, green: 0.52, blue: 0.32)

    // Surface tint floated over photo backgrounds — pure black at low alpha
    // gives the cleanest legibility without staining colours behind it.
    static let scrimTop    = Color.black.opacity(0.10)
    static let scrimBottom = Color.black.opacity(0.55)

    // Glass capsule background
    static let glass = Color.white.opacity(0.14)
    static let glassBorder = Color.white.opacity(0.22)

    // Text
    static let textPrimary   = Color.white
    static let textSecondary = Color.white.opacity(0.78)
    static let textTertiary  = Color.white.opacity(0.55)
}

// MARK: - Gradient

extension LinearGradient {

    static let widgetRomantic = LinearGradient(
        colors: [
            WidgetPalette.gradientTop,
            WidgetPalette.gradientMid,
            WidgetPalette.gradientBottom
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let widgetGold = LinearGradient(
        colors: [WidgetPalette.goldStart, WidgetPalette.goldEnd],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Sits between the photo and the foreground content so light photos
    /// don't bleach the type. Top stays mostly clear, bottom is dark.
    static let widgetPhotoScrim = LinearGradient(
        colors: [WidgetPalette.scrimTop, WidgetPalette.scrimBottom],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - Typography

enum WidgetType {
    static func hero(_ size: CGFloat = 44) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }
    static func title(_ size: CGFloat = 17) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }
    static func body(_ size: CGFloat = 13) -> Font {
        .system(size: size, weight: .medium, design: .rounded)
    }
    static func caption(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .medium, design: .rounded)
    }
    static func micro(_ size: CGFloat = 10) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }
}
