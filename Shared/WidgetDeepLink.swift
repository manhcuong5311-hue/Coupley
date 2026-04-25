//
//  WidgetDeepLink.swift
//  Coupley
//
//  URL builder + parser used by both sides — the widget builds URLs with
//  `widgetURL(_:)`, the main app's Scene parses incoming URLs in
//  `onOpenURL`. Keeping this in shared code prevents typos drifting
//  between the two targets.
//

import Foundation

// MARK: - Destination

enum WidgetDeepLink: Equatable {
    case home
    case anniversary
    case mood
    case partner

    // MARK: - Build

    var url: URL {
        var components = URLComponents()
        components.scheme = WidgetShared.urlScheme
        components.host = host
        return components.url ?? URL(string: "\(WidgetShared.urlScheme)://home")!
    }

    private var host: String {
        switch self {
        case .home:         return "home"
        case .anniversary:  return "anniversary"
        case .mood:         return "mood"
        case .partner:      return "partner"
        }
    }

    // MARK: - Parse

    /// Parses an incoming URL — returns nil for any URL we don't own so
    /// the main app can chain to other handlers (Universal Links etc.)
    /// without false positives.
    static func parse(_ url: URL) -> WidgetDeepLink? {
        guard url.scheme == WidgetShared.urlScheme else { return nil }
        switch url.host {
        case "home":         return .home
        case "anniversary":  return .anniversary
        case "mood":         return .mood
        case "partner":      return .partner
        default:             return nil
        }
    }
}
