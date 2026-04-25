//
//  AppleSignInCoordinator.swift
//  Coupley
//
//  Bridges Apple's callback-based `ASAuthorizationController` into a single
//  `async throws` call site. We need an `NSObject` subclass to satisfy the
//  delegate / presentation-context-providing protocols, and the parent
//  `FirebaseAuthService` retains us for the duration of the request because
//  `ASAuthorizationController` does NOT retain its delegate.
//

import AuthenticationServices
import UIKit

// MARK: - Result

struct AppleSignInResult {
    let idToken: String
    let rawNonce: String
    let fullName: PersonNameComponents?

    /// Concatenated formatted name suitable for `displayName`. Apple only
    /// returns `fullName` on the first sign-in for a given Apple ID, so this
    /// will be empty on subsequent attempts — call sites must handle that.
    var formattedFullName: String? {
        guard let fullName else { return nil }
        let formatter = PersonNameComponentsFormatter()
        formatter.style = .default
        let formatted = formatter.string(from: fullName).trimmingCharacters(in: .whitespaces)
        return formatted.isEmpty ? nil : formatted
    }
}

// MARK: - Coordinator

final class AppleSignInCoordinator:
    NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding
{

    private let rawNonce: String
    private var continuation: CheckedContinuation<AppleSignInResult, Error>?
    private var controller: ASAuthorizationController?

    init(rawNonce: String) {
        self.rawNonce = rawNonce
    }

    /// Hashable identity keeps `Set<AppleSignInCoordinator>` happy in the
    /// service. `===` semantics — each instance is its own request.
    static func == (lhs: AppleSignInCoordinator, rhs: AppleSignInCoordinator) -> Bool {
        lhs === rhs
    }
    override var hash: Int { ObjectIdentifier(self).hashValue }

    // MARK: - Entry point

    @MainActor
    func start(with request: ASAuthorizationAppleIDRequest) async throws -> AppleSignInResult {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<AppleSignInResult, Error>) in
            self.continuation = cont
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            self.controller = controller
            controller.performRequests()
        }
    }

    // MARK: - Delegate

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        defer { continuation = nil; self.controller = nil }

        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            continuation?.resume(throwing: AuthError.providerFailed("Unexpected credential type."))
            return
        }
        guard let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8) else {
            continuation?.resume(throwing: AuthError.missingIdentityToken)
            return
        }

        continuation?.resume(returning: AppleSignInResult(
            idToken: idToken,
            rawNonce: rawNonce,
            fullName: credential.fullName
        ))
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        defer { continuation = nil; self.controller = nil }

        // User-cancel surfaces as code .canceled — we silence it so the UI
        // doesn't show a scary error after a deliberate dismiss.
        if let asError = error as? ASAuthorizationError, asError.code == .canceled {
            continuation?.resume(throwing: AuthError.providerCancelled)
            return
        }
        continuation?.resume(throwing: AuthError.providerFailed(error.localizedDescription))
    }

    // MARK: - Presentation context

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // First key window across all connected scenes — covers both portrait
        // and multi-scene iPad cases.
        let scenes = UIApplication.shared.connectedScenes
        for scene in scenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            if let key = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first {
                return key
            }
        }
        // Fallback: anchor we own. Not ideal but better than crashing.
        return ASPresentationAnchor()
    }
}
