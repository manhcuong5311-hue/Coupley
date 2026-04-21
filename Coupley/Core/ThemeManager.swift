//
//  ThemeManager.swift
//  Coupley
//
//  User-selectable appearance (system / light / dark) + theme variant
//  (CoupleSync / Classic). Both are stored in AppStorage.
//  Attach via `.preferredColorScheme(themeManager.colorScheme)` on the root view,
//  and re-key the tree with `.id(themeManager.variant)` so Brand tokens refresh.
//

import SwiftUI
import Combine

// MARK: - App Theme (light/dark/system)

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: return "gearshape.fill"
        case .light:  return "sun.max.fill"
        case .dark:   return "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

// MARK: - Theme Manager

@MainActor
final class ThemeManager: ObservableObject {

    @AppStorage("appTheme")     private var storedTheme:   String = AppTheme.dark.rawValue
    @AppStorage("themeVariant") private var storedVariant: String = ThemeVariant.coupleSync.rawValue

    var theme: AppTheme {
        get { AppTheme(rawValue: storedTheme) ?? .dark }
        set {
            storedTheme = newValue.rawValue
            objectWillChange.send()
        }
    }

    var variant: ThemeVariant {
        get { ThemeVariant(rawValue: storedVariant) ?? .coupleSync }
        set {
            storedVariant = newValue.rawValue
            objectWillChange.send()
            // UITabBarAppearance is captured once at launch; refresh it now.
            AppTheming.configureTabBar()
        }
    }

    var colorScheme: ColorScheme? { theme.colorScheme }
}
