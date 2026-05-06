//
//  SessionStore.swift
//  Coupley
//
//  Single source of truth for "where is the user in the app?" — drives
//  RootView's routing between Splash, Welcome, Onboarding, and the main
//  content tree. Wraps Firebase Auth's state stream and a Firestore
//  listener on `/users/{uid}` so coupleId / partnerId / archived
//  connection fields are reactive too.
//
//  ## Auth lifecycle (the bit that has bitten us)
//
//  Sign-out used to call `stop()` which removed the auth state listener.
//  The next sign-in then succeeded at the Firebase layer but no one was
//  subscribed to the state change, so `appState` stayed `.unauthenticated`
//  and RootView never routed to the main app. The fix here keeps the auth
//  listener bound for the entire app lifetime; only the per-session
//  `userListener` and downstream subsystem listeners get torn down on
//  sign-out.
//
//  ## Teardown ordering
//
//  `signOut()` runs registered teardown hooks BEFORE calling
//  `Auth.auth().signOut()` so subsystems with active Firestore listeners
//  (PremiumStore, NotificationViewModel, etc.) cancel cleanly while the
//  auth context is still valid. Without this, listeners briefly poll on
//  a deauth'd session and the SDK fills the console with "Missing or
//  insufficient permissions" warnings.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import Combine

// MARK: - App State

enum AppState: Equatable {
    case loading
    case unauthenticated
    /// Authenticated but no partner connected yet — shown in app with connect prompt.
    case needsPairing(userId: String, displayName: String)
    case ready(UserSession)

    static func == (lhs: AppState, rhs: AppState) -> Bool {
        switch (lhs, rhs) {
        case (.loading, .loading),
             (.unauthenticated, .unauthenticated):
            return true
        case let (.needsPairing(a, b), .needsPairing(c, d)):
            return a == c && b == d
        case let (.ready(a), .ready(b)):
            return a.userId == b.userId
                && a.coupleId == b.coupleId
                && a.partnerId == b.partnerId
        default:
            return false
        }
    }
}

// MARK: - Session Store

@MainActor
final class SessionStore: ObservableObject {

    @Published var appState: AppState = .loading

    // MARK: - Archived connection (post-disconnect)

    /// Set when the user has a retired coupleId on their user doc — used
    /// by "Manage shared data" to reach archived data after disconnect.
    @Published var lastCoupleId: String?
    @Published var lastPartnerId: String?
    @Published var lastPartnerName: String?

    /// One-shot flag written by the other user's disconnect batch. The
    /// client shows "Your partner has disconnected" and then clears it.
    @Published var pendingDisconnectNotice: Bool = false

    var session: UserSession? {
        switch appState {
        case .ready(let s):            return s
        case .needsPairing(let id, _): return UserSession.solo(userId: id)
        default:                       return nil
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

    /// Hooks invoked synchronously inside `signOut()` BEFORE Firebase Auth
    /// is signed out. Subsystems with active listeners or async tasks
    /// register here so cleanup runs while the auth context is still
    /// valid — preventing the cascade of "Missing or insufficient
    /// permissions" warnings that otherwise fire while listeners poll on
    /// a deauth'd session.
    ///
    /// Keep hooks fast and synchronous. Long-running work should spawn
    /// its own detached Task so signOut returns promptly.
    private var teardownHooks: [() -> Void] = []

    // MARK: - Lifecycle

    /// Bind to Firebase Auth's state stream. Idempotent — repeat calls
    /// no-op so cold-restart and SwiftUI scene reactivation are both
    /// safe entry points.
    func start() {
        guard authListener == nil else { return }

        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let user {
                    self.observeUserDocument(
                        userId: user.uid,
                        displayName: user.displayName ?? ""
                    )
                } else {
                    self.handleSignedOutState()
                }
            }
        }
    }

    /// Detach all listeners. Used only on full app teardown — NOT called
    /// from `signOut()`. See the file header for the history of why this
    /// was a footgun.
    func stop() {
        if let listener = authListener {
            Auth.auth().removeStateDidChangeListener(listener)
            authListener = nil
        }
        userListener?.remove()
        userListener = nil
    }

    // MARK: - Teardown registry

    /// Register a hook that `signOut()` will invoke synchronously, before
    /// `Auth.auth().signOut()` runs. The pattern at call sites is:
    ///
    ///     sessionStore.registerTeardown { [weak premiumStore] in
    ///         premiumStore?.unbind()
    ///     }
    ///
    /// Hooks are kept for the lifetime of the SessionStore — they only
    /// run on user-initiated sign-outs, and the SessionStore lives as
    /// long as the app process.
    func registerTeardown(_ hook: @escaping () -> Void) {
        teardownHooks.append(hook)
    }

    // MARK: - Sign Out

    /// User-initiated sign-out. Order matters:
    ///
    ///   1. Run every registered teardown hook synchronously while the
    ///      auth context is still valid. PremiumStore, NotificationVM,
    ///      and any future subsystem with Firestore listeners cancel
    ///      themselves here, before Firebase yanks the credentials.
    ///   2. Detach our own user-doc listener.
    ///   3. Snap `appState` to `.unauthenticated` so SwiftUI starts
    ///      routing to WelcomeView immediately — no flash of stale state.
    ///   4. Call `Auth.auth().signOut()`. The state-change listener is
    ///      still bound (intentionally), so it fires once with `nil` —
    ///      but the resulting transition is a no-op since `appState` is
    ///      already `.unauthenticated`.
    ///
    /// Idempotent — calling twice while already signed out short-circuits.
    func signOut() {
        guard appState != .unauthenticated else {
            // Defensive: still call Firebase signOut in case auth and
            // app state ever drift, but skip the rest.
            try? Auth.auth().signOut()
            return
        }

        for hook in teardownHooks {
            hook()
        }

        userListener?.remove()
        userListener = nil

        clearArchivedConnectionFields()
        appState = .unauthenticated

        try? Auth.auth().signOut()
    }

    // MARK: - Pairing Complete (called by PairingViewModel after successful pair)

    func refreshSession() {
        guard let userId = Auth.auth().currentUser?.uid,
              let displayName = Auth.auth().currentUser?.displayName else { return }
        observeUserDocument(userId: userId, displayName: displayName)
    }

    /// Detach the user-doc listener ahead of an in-progress account
    /// deletion. Without this, `db.delete(/users/{uid})` fires the snapshot
    /// listener with nil data, briefly flipping the state to `.needsPairing`
    /// before `Auth.auth().currentUser?.delete()` finishes and routes the
    /// user back to Welcome. The auth listener stays bound so the final
    /// `.unauthenticated` transition still drives navigation.
    func prepareForDeletion() {
        userListener?.remove()
        userListener = nil
    }

    // MARK: - Private

    private func handleSignedOutState() {
        userListener?.remove()
        userListener = nil
        clearArchivedConnectionFields()
        // Avoid an unnecessary @Published republish if we're already here.
        if appState != .unauthenticated {
            appState = .unauthenticated
        }
    }

    private func clearArchivedConnectionFields() {
        lastCoupleId = nil
        lastPartnerId = nil
        lastPartnerName = nil
        pendingDisconnectNotice = false
    }

    private func observeUserDocument(userId: String, displayName: String) {
        userListener?.remove()

        userListener = db.collection(FirestorePath.users).document(userId)
            .addSnapshotListener { [weak self] snapshot, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }

                    guard let data = snapshot?.data() else {
                        // No Firestore document yet — treat as solo (not a blocker)
                        self.clearArchivedConnectionFields()
                        self.appState = .needsPairing(
                            userId: userId,
                            displayName: displayName
                        )
                        return
                    }

                    // Archived connection fields (populated after disconnect)
                    self.lastCoupleId    = data[ConnectionField.lastCoupleId]    as? String
                    self.lastPartnerId   = data[ConnectionField.lastPartnerId]   as? String
                    self.lastPartnerName = data[ConnectionField.lastPartnerName] as? String
                    self.pendingDisconnectNotice =
                        (data[ConnectionField.pendingDisconnectNotice] as? Bool) ?? false

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
                        self.appState = .needsPairing(
                            userId: userId,
                            displayName: displayName
                        )
                    }
                }
            }
    }
}
