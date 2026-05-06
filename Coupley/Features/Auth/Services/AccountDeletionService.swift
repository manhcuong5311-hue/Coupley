//
//  AccountDeletionService.swift
//  Coupley
//
//  Apple App Store Guideline 5.1.1(v) — In-app account deletion.
//
//  Pipeline (executes in this order; downstream steps tolerate prior
//  Firestore failures so a single hiccup never strands the user with an
//  undeletable Firebase Auth record):
//
//    1. Re-authenticate the user with their original provider. Firebase
//       Auth requires a fresh credential within ~5 minutes to authorize
//       `currentUser.delete()`.
//         • Email/Password → reauth with email + password
//         • Apple          → fresh Sign in with Apple, captures the
//                            short-lived authorizationCode for token revoke
//         • Google         → fresh OAuthProvider("google.com") web flow
//
//    2. Soft-disconnect the partner pairing (when paired) via the existing
//       ConnectionService so the partner's client receives the canonical
//       "your partner has disconnected" notice.
//
//    3. Hard-delete the shared couple document and all known subcollections
//       (messages, moods + reactions, syncScores, quizzes, coupleProfile,
//       notifications) using ConnectionService.deleteSharedData — same
//       routine the "Delete shared data" UI runs.
//
//    4. Delete any pairing codes the user created — /pairingCodes where
//       creatorId == uid.
//
//    5. Clear the user's premium ownership slot (defensive — couple slot
//       is already wiped, but this catches solo subscribers too).
//
//    6. Delete /users/{uid} — removes profile fields, archived connection
//       metadata, notification prefs, premium flags, etc.
//
//    7. Revoke the Sign in with Apple token (Apple-required for SIWA
//       accounts — uses the authorizationCode captured in step 1).
//
//    8. Delete the Firebase Auth user. The auth state listener in
//       SessionStore observes this and routes the app to WelcomeView.
//

import Foundation
import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseFirestore
import Combine

// MARK: - Errors

enum AccountDeletionError: LocalizedError {
    case notSignedIn
    case requiresPasswordEntry
    case incorrectPassword
    case userCancelledReauth
    case unsupportedProvider(String)
    case reauthenticationFailed(String)
    case requiresRecentLogin
    case deletionFailed(String)
    case offline

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "You're not signed in."
        case .requiresPasswordEntry:
            return "Please enter your password to confirm account deletion."
        case .incorrectPassword:
            return "Incorrect password. Please try again."
        case .userCancelledReauth:
            return ""  // silent — user backed out on purpose
        case .unsupportedProvider(let provider):
            return "Account deletion isn't supported yet for the \(provider) sign-in method. " +
                   "Please contact support."
        case .reauthenticationFailed(let message):
            return message
        case .requiresRecentLogin:
            return "For your security, please sign out and sign back in, then try deleting again."
        case .deletionFailed(let message):
            return message
        case .offline:
            return "You appear to be offline. Connect to the internet and try again."
        }
    }
}

// MARK: - Provider Detection

/// Provider we know how to re-authenticate. Anything not in this enum is
/// surfaced via `.unsupportedProvider` so the UI can offer a graceful
/// fallback (contact support / manual deletion request).
enum AccountAuthProvider: String, Equatable {
    case password = "password"
    case apple    = "apple.com"
    case google   = "google.com"

    var displayName: String {
        switch self {
        case .password: return "Email & Password"
        case .apple:    return "Apple"
        case .google:   return "Google"
        }
    }

    /// Whether the provider needs a password input from the user. The UI
    /// hides the password field for OAuth providers.
    var needsPasswordInput: Bool { self == .password }
}

// MARK: - Service

@MainActor
final class AccountDeletionService: NSObject, ObservableObject {

    private let connectionService: ConnectionService
    private let premiumService: PremiumService
    private let db = Firestore.firestore()

    /// Strong-references in-flight Apple sign-in coordinators —
    /// ASAuthorizationController doesn't retain its delegate.
    private var pendingAppleCoordinators: Set<AppleSignInCoordinator> = []

    /// Defaults are constructed inside the body rather than as parameter
    /// defaults — Swift 6's strict concurrency treats default expressions
    /// as nonisolated, which conflicts with `@MainActor` init.
    init(
        connectionService: ConnectionService? = nil,
        premiumService: PremiumService? = nil
    ) {
        self.connectionService = connectionService ?? FirestoreConnectionService()
        self.premiumService = premiumService ?? FirestorePremiumService()
        super.init()
    }

    // MARK: - Provider Detection

    /// The signed-in user's primary auth provider. When more than one is
    /// linked we prefer Apple → Google → password so the OAuth flow that
    /// actually authenticated the user takes priority.
    var currentProvider: AccountAuthProvider? {
        guard let user = Auth.auth().currentUser else { return nil }
        let providers = user.providerData.map { $0.providerID }
        if providers.contains(AccountAuthProvider.apple.rawValue)    { return .apple }
        if providers.contains(AccountAuthProvider.google.rawValue)   { return .google }
        if providers.contains(AccountAuthProvider.password.rawValue) { return .password }
        return nil
    }

    var currentEmail: String? {
        Auth.auth().currentUser?.email
    }

    /// True if a real user is signed in (used by the UI to disable the
    /// confirm button before everything is ready).
    var isReady: Bool {
        Auth.auth().currentUser != nil && currentProvider != nil
    }

    // MARK: - Re-authentication

    /// Re-authenticates the current user. Apple/Google providers present
    /// the system sign-in sheet — the UI MUST be on the main actor when
    /// calling this. Email/Password requires the caller to pass `password`.
    ///
    /// On Apple, returns the authorization code so the deletion pipeline
    /// can call `Auth.revokeToken(withAuthorizationCode:)`. Returns nil for
    /// other providers.
    func reauthenticate(password: String?) async throws -> String? {
        guard let user = Auth.auth().currentUser else {
            throw AccountDeletionError.notSignedIn
        }
        guard let provider = currentProvider else {
            let raw = user.providerData.first?.providerID ?? "unknown"
            throw AccountDeletionError.unsupportedProvider(raw)
        }

        switch provider {
        case .password:
            return try await reauthenticateWithPassword(user: user, password: password)
        case .apple:
            return try await reauthenticateWithApple(user: user)
        case .google:
            try await reauthenticateWithGoogle(user: user)
            return nil
        }
    }

    private func reauthenticateWithPassword(user: User, password: String?) async throws -> String? {
        guard let password, !password.isEmpty else {
            throw AccountDeletionError.requiresPasswordEntry
        }
        guard let email = user.email else {
            throw AccountDeletionError.notSignedIn
        }
        let credential = EmailAuthProvider.credential(withEmail: email, password: password)
        do {
            _ = try await user.reauthenticate(with: credential)
            return nil
        } catch let nsError as NSError {
            if nsError.code == AuthErrorCode.wrongPassword.rawValue
                || nsError.code == AuthErrorCode.invalidCredential.rawValue {
                throw AccountDeletionError.incorrectPassword
            }
            if nsError.code == AuthErrorCode.networkError.rawValue {
                throw AccountDeletionError.offline
            }
            throw AccountDeletionError.reauthenticationFailed(nsError.localizedDescription)
        }
    }

    private func reauthenticateWithApple(user: User) async throws -> String? {
        let rawNonce = Self.makeRandomNonce()
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.email]
        request.nonce = Self.sha256(rawNonce)

        let coordinator = AppleSignInCoordinator(rawNonce: rawNonce)
        pendingAppleCoordinators.insert(coordinator)
        defer { pendingAppleCoordinators.remove(coordinator) }

        let result: AppleSignInResult
        do {
            result = try await coordinator.start(with: request)
        } catch let err as AuthError {
            if case .providerCancelled = err {
                throw AccountDeletionError.userCancelledReauth
            }
            throw AccountDeletionError.reauthenticationFailed(
                err.errorDescription ?? "Apple sign-in failed."
            )
        }

        let credential = OAuthProvider.appleCredential(
            withIDToken: result.idToken,
            rawNonce: rawNonce,
            fullName: result.fullName
        )

        do {
            _ = try await user.reauthenticate(with: credential)
            return result.authorizationCode
        } catch let nsError as NSError {
            if nsError.code == AuthErrorCode.userMismatch.rawValue {
                throw AccountDeletionError.reauthenticationFailed(
                    "Please sign in with the same Apple ID you used to create this account."
                )
            }
            throw AccountDeletionError.reauthenticationFailed(nsError.localizedDescription)
        }
    }

    private func reauthenticateWithGoogle(user: User) async throws {
        let provider = OAuthProvider(providerID: "google.com")
        provider.scopes = ["email", "profile"]
        provider.customParameters = ["prompt": "select_account"]

        let credential: AuthCredential = try await withCheckedThrowingContinuation { cont in
            provider.getCredentialWith(nil) { credential, error in
                if let error {
                    cont.resume(throwing: AccountDeletionError.reauthenticationFailed(
                        error.localizedDescription
                    ))
                    return
                }
                guard let credential else {
                    cont.resume(throwing: AccountDeletionError.reauthenticationFailed(
                        "Google sign-in returned no credential."
                    ))
                    return
                }
                cont.resume(returning: credential)
            }
        }

        do {
            _ = try await user.reauthenticate(with: credential)
        } catch let nsError as NSError {
            if nsError.code == AuthErrorCode.userMismatch.rawValue {
                throw AccountDeletionError.reauthenticationFailed(
                    "Please sign in with the same Google account you used to create this account."
                )
            }
            throw AccountDeletionError.reauthenticationFailed(nsError.localizedDescription)
        }
    }

    // MARK: - Delete Pipeline

    /// Runs the full deletion pipeline. Caller MUST have completed
    /// `reauthenticate(...)` within the last few minutes — Firebase Auth
    /// rejects `delete()` otherwise with `requiresRecentLogin`.
    ///
    /// `appleAuthorizationCode` is the value returned by `reauthenticate(...)`
    /// when the active provider was Apple. It's used to revoke the Apple
    /// token before tearing down the Firebase account.
    func deleteEverything(
        session: UserSession?,
        partnerDisplayName: String?,
        archivedCoupleId: String?,
        appleAuthorizationCode: String?
    ) async throws {
        guard let user = Auth.auth().currentUser else {
            throw AccountDeletionError.notSignedIn
        }
        let userId = user.uid

        // 1) Soft-disconnect the live pairing (if any) so the partner's
        // client gets the canonical "your partner has disconnected" notice
        // via pendingDisconnectNotice.
        if let session, session.isPaired {
            try? await connectionService.disconnect(
                session: session,
                partnerDisplayName: partnerDisplayName
            )
        }

        // 2) Hard-delete couple-shared data. Disconnect just moved the live
        // coupleId into lastCoupleId, so we use whichever is non-empty.
        let coupleIdToWipe = (session?.coupleId).flatMap { $0.isEmpty ? nil : $0 }
            ?? archivedCoupleId
        if let coupleId = coupleIdToWipe, !coupleId.isEmpty {
            try? await connectionService.deleteSharedData(
                connectionId: coupleId,
                userId: userId
            )
        }

        // 3) Delete pairing codes this user created. Codes self-expire
        // server-side, but cleaning them up here is hygienic and avoids a
        // dead pairing code that points at a deleted creator.
        try? await deletePairingCodes(creatorId: userId)

        // 4) Clear the user's premium ownership slot defensively. The
        // shared couple slot was already wiped above; this catches solo
        // subscribers and any stale mirror that survived.
        try? await premiumService.clearEntitlement(userId: userId, coupleId: nil)

        // 5) Delete /users/{uid}. After this the SessionStore's user-doc
        // listener will report nil and route the app away from any
        // user-scoped views even before auth tears down.
        try? await db.collection(FirestorePath.users).document(userId).delete()

        // 6) Revoke the Apple Sign-in token (Apple Guideline 5.1.1(v) for
        // SIWA). Best-effort — if the token is already invalid, we don't
        // want to block deletion on it.
        if let code = appleAuthorizationCode, !code.isEmpty {
            try? await Auth.auth().revokeToken(withAuthorizationCode: code)
        }

        // 7) Delete the Firebase Auth user. The auth state listener flips
        // SessionStore.appState to .unauthenticated; RootView routes to
        // WelcomeView; PremiumStore.unbind() runs from RootView's
        // syncPremiumBinding.
        do {
            try await user.delete()
        } catch let nsError as NSError {
            if nsError.code == AuthErrorCode.requiresRecentLogin.rawValue {
                throw AccountDeletionError.requiresRecentLogin
            }
            if nsError.code == AuthErrorCode.networkError.rawValue {
                throw AccountDeletionError.offline
            }
            throw AccountDeletionError.deletionFailed(nsError.localizedDescription)
        }
    }

    // MARK: - Private

    private func deletePairingCodes(creatorId: String) async throws {
        let snap = try await db.collection(FirestorePath.pairingCodes)
            .whereField("creatorId", isEqualTo: creatorId)
            .getDocuments()
        guard !snap.documents.isEmpty else { return }
        let batch = db.batch()
        for doc in snap.documents {
            batch.deleteDocument(doc.reference)
        }
        try await batch.commit()
    }

    // MARK: - Nonce helpers
    //
    // Mirrors the implementation in FirebaseAuthService — keeping a copy
    // here so account deletion has no source-file dependency on auth's
    // private helpers.

    private static func makeRandomNonce(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            precondition(status == errSecSuccess, "Unable to generate nonce. SecRandom failed.")
            for byte in randoms where remaining > 0 {
                if byte < charset.count {
                    result.append(charset[Int(byte)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
