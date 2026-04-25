//
//  WidgetDeepLinkRouter.swift
//  Coupley
//
//  Translates widget deeplinks into app navigation events. The router is
//  an `ObservableObject` that publishes a `pendingDestination` — views
//  observe it and reconcile their own state (e.g. ContentView flips
//  `selectedTab`).
//
//  This indirection keeps the URL parsing free of UIKit/SwiftUI concerns
//  and means deeplinks fired before the UI is ready get queued instead
//  of dropped.
//

import Foundation
import SwiftUI
import Combine
// MARK: - Router

@MainActor
final class WidgetDeepLinkRouter: ObservableObject {

    static let shared = WidgetDeepLinkRouter()

    @Published var pendingDestination: WidgetDeepLink?

    private init() {}

    /// Attempts to handle an incoming URL. Returns `true` when the URL
    /// matched a widget deeplink and the router queued the navigation —
    /// callers can use the boolean to decide whether to chain to other
    /// URL handlers.
    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard let destination = WidgetDeepLink.parse(url) else { return false }
        pendingDestination = destination
        return true
    }

    /// Mark the destination as consumed so views don't re-trigger nav on
    /// every render pass.
    func consume() {
        pendingDestination = nil
    }
}

// MARK: - View Modifier

private struct WidgetDeepLinkHandler: ViewModifier {
    func body(content: Content) -> some View {
        content.onOpenURL { url in
            _ = WidgetDeepLinkRouter.shared.handle(url)
        }
    }
}

extension View {
    /// Parses incoming widget deep links into router events. Attach once
    /// at the root view.
    func handleWidgetDeepLinks() -> some View {
        modifier(WidgetDeepLinkHandler())
    }
}
