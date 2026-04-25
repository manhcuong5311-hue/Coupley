//
//  WidgetSyncCoordinator.swift
//  Coupley
//
//  Bridge between SessionStore and WidgetSyncService. Subscribes to
//  appState transitions and binds/unbinds the sync service so the widget
//  snapshot always reflects the current pairing state.
//
//  Attached to the root view via `.attachWidgetSync()`.
//

import Foundation
import SwiftUI
import Combine
import FirebaseFirestore

// MARK: - Coordinator

@MainActor
final class WidgetSyncCoordinator: ObservableObject {

    private let sessionStore: SessionStore
    private var cancellable: AnyCancellable?

    init(sessionStore: SessionStore) {
        self.sessionStore = sessionStore
        observe()
    }

    private func observe() {
        cancellable = sessionStore.$appState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.apply(state)
            }
    }

    private func apply(_ state: AppState) {
        switch state {
        case .ready(let session):
            // Pull the partner's display name lazily — the sync service
            // also listens to the partner user doc, so the name will
            // update even if we pass nil here at first.
            WidgetSyncService.shared.bind(session: session, partnerDisplayName: nil)

        case .needsPairing, .unauthenticated, .loading:
            WidgetSyncService.shared.unbind()
        }
    }
}

// MARK: - View Modifier

private struct WidgetSyncAttachment: ViewModifier {
    @EnvironmentObject private var sessionStore: SessionStore
    @State private var coordinator: WidgetSyncCoordinator?

    func body(content: Content) -> some View {
        content.onAppear {
            if coordinator == nil {
                coordinator = WidgetSyncCoordinator(sessionStore: sessionStore)
            }
        }
    }
}

extension View {
    /// Attaches the widget sync coordinator. Call this once at the root
    /// of the app — `RootView` is the right home.
    func attachWidgetSync() -> some View {
        modifier(WidgetSyncAttachment())
    }
}
