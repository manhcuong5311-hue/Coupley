//
//  AuthService.swift
//  Coupley
//
//  Three sign-in providers, all bridged into the same Firebase Auth user:
//
//    1. Email + password (existing)
//    2. Sign in with Apple   — AuthenticationServices + nonce + OAuthProvider
//    3. Continue with Google — Firebase Auth's `OAuthProvider` web flow
//                              (ASWebAuthenticationSession under the hood, so
//                              no extra SDK dependency required)
//
//  Whichever provider is used, this service guarantees `/users/{uid}` exists
//  with `userId`, `displayName`, `email`, `createdAt` after a successful sign
//  in — `setData(merge:)` so we never clobber an existing document. The rest
//  of the app keys off the Firestore listener in SessionStore, so all
//  providers route through the same `.unauthenticated → .needsPairing →
//  .ready` state machine.
//

import Foundation
import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import UIKit

// MARK: - Errors

enum AuthError: LocalizedError {
    case missingPresentationAnchor
    case missingIdentityToken
    case missingNonce
    case providerCancelled
    case providerFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingPresentationAnchor:
            return "Couldn't open the sign-in window. Try again."
        case .missingIdentityToken:
            return "Sign in was incomplete. Please try again."
        case .missingNonce:
            return "Sign in was incomplete. Please try again."
        case .providerCancelled:
            return ""  // silent — user backed out on purpose
        case .providerFailed(let message):
            return message
        }
    }
}

// MARK: - Protocol

protocol AuthServiceProtocol {
    func signIn(email: String, password: String) async throws
    func signUp(email: String, password: String, displayName: String) async throws
    func signInWithApple() async throws
    func signInWithGoogle() async throws
    func signOut() throws
}

// MARK: - Firebase Implementation

final class FirebaseAuthService: NSObject, AuthServiceProtocol {

    private let db = Firestore.firestore()

    // Strong references to in-flight Apple sign-in coordinators. Apple's
    // ASAuthorizationController doesn't retain its delegate, so we have to.
    private var pendingAppleCoordinators: Set<AppleSignInCoordinator> = []

    // MARK: - Email

    func signIn(email: String, password: String) async throws {
        try await Auth.auth().signIn(withEmail: email, password: password)
    }

    func signUp(email: String, password: String, displayName: String) async throws {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)

        let changeRequest = result.user.createProfileChangeRequest()
        changeRequest.displayName = displayName
        try await changeRequest.commitChanges()

        try await ensureUserDocument(
            uid: result.user.uid,
            displayName: displayName,
            email: email
        )
    }

    func signOut() throws {
        try Auth.auth().signOut()
    }

    // MARK: - Apple

    /// Production Sign in with Apple. Generates a cryptographic nonce, hashes
    /// it for the request, then passes the raw nonce + Apple's identity token
    /// into a Firebase OAuth credential. Apple may only send the user's name
    /// on the *first* sign-in (subsequent ones return nil for `fullName`), so
    /// we capture and write it on first auth, falling back to email prefix.
    @MainActor
    func signInWithApple() async throws {
        let rawNonce = Self.makeRandomNonce()
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(rawNonce)

        let coordinator = AppleSignInCoordinator(rawNonce: rawNonce)
        pendingAppleCoordinators.insert(coordinator)
        defer { pendingAppleCoordinators.remove(coordinator) }

        let result = try await coordinator.start(with: request)

        let credential = OAuthProvider.appleCredential(
            withIDToken: result.idToken,
            rawNonce: rawNonce,
            fullName: result.fullName
        )

        let authResult = try await Auth.auth().signIn(with: credential)

        // Apple supplies the name only the first time; if we got one, persist
        // it so the user doesn't show up as "User" forever.
        let resolvedName = Self.resolveDisplayName(
            providerName: result.formattedFullName,
            firebaseName: authResult.user.displayName,
            email: authResult.user.email
        )
        if authResult.user.displayName.isNilOrEmpty, !resolvedName.isEmpty {
            let req = authResult.user.createProfileChangeRequest()
            req.displayName = resolvedName
            try? await req.commitChanges()
        }

        try await ensureUserDocument(
            uid: authResult.user.uid,
            displayName: resolvedName,
            email: authResult.user.email ?? ""
        )
    }

    // MARK: - Google

    /// Continue with Google via Firebase's `OAuthProvider`. Uses
    /// `ASWebAuthenticationSession` internally, so the user gets the system
    /// sign-in sheet without needing the GoogleSignIn-iOS SDK as a separate
    /// dependency. Requires Google to be enabled as a provider in the
    /// Firebase console — which the existing `GoogleService-Info.plist`
    /// implies is already configured.
    @MainActor
    func signInWithGoogle() async throws {
        let provider = OAuthProvider(providerID: "google.com")
        provider.scopes = ["email", "profile"]
        provider.customParameters = ["prompt": "select_account"]

        let credential: AuthCredential = try await withCheckedThrowingContinuation { cont in
            provider.getCredentialWith(nil) { credential, error in
                if let error {
                    cont.resume(throwing: AuthError.providerFailed(error.localizedDescription))
                    return
                }
                guard let credential else {
                    cont.resume(throwing: AuthError.providerFailed("No credential returned."))
                    return
                }
                cont.resume(returning: credential)
            }
        }

        let authResult = try await Auth.auth().signIn(with: credential)

        let displayName = Self.resolveDisplayName(
            providerName: authResult.user.displayName,
            firebaseName: authResult.user.displayName,
            email: authResult.user.email
        )

        try await ensureUserDocument(
            uid: authResult.user.uid,
            displayName: displayName,
            email: authResult.user.email ?? ""
        )
    }

    // MARK: - Firestore upsert

    /// Idempotent user-doc creation. Uses `merge: true` so we never overwrite
    /// fields written by the rest of the app (premium, coupleId, partnerId,
    /// preferences, etc.) on a returning sign-in. Only stamps `createdAt` if
    /// it doesn't already exist by reading the doc first.
    private func ensureUserDocument(
        uid: String,
        displayName: String,
        email: String
    ) async throws {
        let ref = db.collection(FirestorePath.users).document(uid)
        let snap = try? await ref.getDocument()
        let exists = snap?.exists == true

        var payload: [String: Any] = [
            "userId": uid,
            "displayName": displayName,
            "email": email
        ]
        if !exists {
            payload["createdAt"] = FieldValue.serverTimestamp()
        }

        try await ref.setData(payload, merge: true)
    }

    // MARK: - Helpers

    /// Pick the best name we can: provider-supplied → Firebase-cached →
    /// email local-part as a polite fallback.
    private static func resolveDisplayName(
        providerName: String?,
        firebaseName: String?,
        email: String?
    ) -> String {
        if let p = providerName?.trimmingCharacters(in: .whitespaces),
           !p.isEmpty { return p }
        if let f = firebaseName?.trimmingCharacters(in: .whitespaces),
           !f.isEmpty { return f }
        if let e = email, let prefix = e.split(separator: "@").first {
            return String(prefix).capitalized
        }
        return ""
    }

    /// Cryptographically-random nonce for Apple's PKCE-style replay
    /// protection. 32 chars from a URL-safe alphabet — entropy is what
    /// matters, not length.
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

    /// SHA-256 hex digest. Apple expects the *hashed* nonce on the request
    /// so the raw nonce can be replay-checked at credential-validation time.
    private static func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Optional<String> sugar

private extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool {
        switch self {
        case .none: return true
        case .some(let s): return s.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }
}
