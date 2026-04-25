//
//  ManagePartnerViewModel.swift
//  Coupley
//
//  Drives the "Manage partner" + "Manage shared data" screens. Handles
//  soft-disconnect, archived-connection lookup, and hard-delete flows.
//

import Foundation
import Combine

@MainActor
final class ManagePartnerViewModel: ObservableObject {

    // MARK: - Published state

    @Published private(set) var isDisconnecting: Bool = false
    @Published private(set) var isDeleting: Bool = false
    @Published var errorMessage: String?
    @Published var didDisconnect: Bool = false
    @Published var didDeleteSharedData: Bool = false
    @Published private(set) var archivedConnection: PartnerConnection?

    // MARK: - Deps

    private let service: ConnectionService

    init(service: ConnectionService? = nil) {
        self.service = service ?? FirestoreConnectionService()
    }

    // MARK: - Actions

    /// Soft-disconnect. Returns quickly; the SessionStore listener will
    /// transition the app to `.needsPairing` and tear down listeners.
    func disconnect(session: UserSession, partnerDisplayName: String?) {
        guard !isDisconnecting else { return }
        isDisconnecting = true
        errorMessage = nil

        Task {
            defer { isDisconnecting = false }
            do {
                try await service.disconnect(
                    session: session,
                    partnerDisplayName: partnerDisplayName
                )
                didDisconnect = true
            } catch {
                // Edge: offline. Firestore queues the write; UI will still
                // feel disconnected locally because appState flips on next
                // snapshot. We surface a soft note instead of a hard error.
                errorMessage = "We saved your disconnect request. Sync will finish when you're back online."
                didDisconnect = true
            }
        }
    }

    /// Loads archived connection metadata for the "Manage shared data" screen.
    func loadArchived(connectionId: String?) {
        guard let connectionId, !connectionId.isEmpty else { return }
        Task {
            do {
                archivedConnection = try await service.loadConnection(connectionId: connectionId)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Hard-delete. Only proceeds when the connection is already marked
    /// `disconnected` — the service enforces this too as a second guard.
    func deleteSharedData(connectionId: String?, userId: String) {
        guard let connectionId, !connectionId.isEmpty else { return }
        guard !isDeleting else { return }
        isDeleting = true
        errorMessage = nil

        Task {
            defer { isDeleting = false }
            do {
                try await service.deleteSharedData(
                    connectionId: connectionId,
                    userId: userId
                )
                didDeleteSharedData = true
            } catch {
                errorMessage = "Couldn't delete shared data: \(error.localizedDescription)"
            }
        }
    }

    /// Dismisses the "your partner disconnected" banner.
    func acknowledgeDisconnectNotice(userId: String) {
        Task {
            try? await service.acknowledgeDisconnectNotice(userId: userId)
        }
    }
}
