//
//  SessionStore.swift
//  Coupley
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import Combine

// MARK: - App State

enum AppState {
    case loading
    case unauthenticated
    /// Authenticated but no partner connected yet — shown in app with connect prompt.
    case needsPairing(userId: String, displayName: String)
    case ready(UserSession)
}

// MARK: - Session Store

@MainActor
final class SessionStore: ObservableObject {

    @Published var appState: AppState = .loading

    var session: UserSession? {
        switch appState {
        case .ready(let s):          return s
        case .needsPairing(let id, _): return UserSession.solo(userId: id)
        default:                     return nil
        }
    }

    var isPaired: Bool {
        if case .ready = appState { return true }
        return false
    }

    var soloUserId: String? {
        if case .needsPairing(let id, _) = appState { return id }
        return nil
    }

    var soloDisplayName: String? {
        if case .needsPairing(_, let name) = appState { return name }
        return nil
    }

    private let db = Firestore.firestore()
    private var authListener: AuthStateDidChangeListenerHandle?
    nonisolated(unsafe) private var userListener: ListenerRegistration?

    // MARK: - Lifecycle

    func start() {
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let user = user {
                    self.observeUserDocument(userId: user.uid, displayName: user.displayName ?? "")
                } else {
                    self.userListener?.remove()
                    self.userListener = nil
                    self.appState = .unauthenticated
                }
            }
        }
    }

    func stop() {
        if let listener = authListener {
            Auth.auth().removeStateDidChangeListener(listener)
            authListener = nil
        }
        userListener?.remove()
        userListener = nil
    }

    // MARK: - Sign Out

    func signOut() {
        stop()
        try? Auth.auth().signOut()
        appState = .unauthenticated
    }

    // MARK: - Pairing Complete (called by PairingViewModel after successful pair)

    func refreshSession() {
        guard let userId = Auth.auth().currentUser?.uid,
              let displayName = Auth.auth().currentUser?.displayName else { return }
        observeUserDocument(userId: userId, displayName: displayName)
    }

    // MARK: - Private

    private func observeUserDocument(userId: String, displayName: String) {
        userListener?.remove()

        userListener = db.collection(FirestorePath.users).document(userId)
            .addSnapshotListener { [weak self] snapshot, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }

                    guard let data = snapshot?.data() else {
                        // No Firestore document yet — treat as solo (not a blocker)
                        self.appState = .needsPairing(userId: userId, displayName: displayName)
                        return
                    }

                    if let coupleId = data["coupleId"] as? String,
                       let partnerId = data["partnerId"] as? String,
                       !coupleId.isEmpty, !partnerId.isEmpty {
                        self.appState = .ready(UserSession(
                            userId: userId,
                            coupleId: coupleId,
                            partnerId: partnerId
                        ))
                    } else {
                        // Authenticated but partner not connected yet
                        self.appState = .needsPairing(userId: userId, displayName: displayName)
                    }
                }
            }
    }
}
