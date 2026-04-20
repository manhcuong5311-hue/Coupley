//
//  ThemeManager.swift
//  Coupley
//
//  User-selectable theme (system / light / dark) stored in AppStorage.
//  Attach via `.preferredColorScheme(themeManager.colorScheme)` on the root view.
//

import SwiftUI
import Combine
// MARK: - App Theme

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

    @AppStorage("appTheme") private var storedTheme: String = AppTheme.dark.rawValue

    var theme: AppTheme {
        get { AppTheme(rawValue: storedTheme) ?? .dark }
        set {
            storedTheme = newValue.rawValue
            objectWillChange.send()
        }
    }

    var colorScheme: ColorScheme? { theme.colorScheme }
}
