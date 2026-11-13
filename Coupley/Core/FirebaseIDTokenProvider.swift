//
//  FirebaseIDTokenProvider.swift
//  Coupley
//
//  Supplies the Firebase ID token that the AI Cloud Functions authenticate
//  with. `aiMiddleware` in functions/index.js rejects any request without a
//  valid `Authorization: Bearer <idToken>` header, and the hybrid services
//  swallow that failure by falling back to their on-device mock — so a
//  missing token looks exactly like "the AI is a bit basic" rather than like
//  an error. That silence is why this is wired as the *default* for both
//  remote services instead of being passed in per call site.
//

import Foundation
import FirebaseAuth

enum AuthTokenError: LocalizedError {
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return String(localized: "You need to be signed in to use this.",
                                         comment: "Error: an action needs a signed-in account")
        }
    }
}

enum FirebaseIDTokenProvider {

    /// Current user's ID token, refreshed by the SDK when it has expired.
    static func token() async throws -> String {
        guard let user = Auth.auth().currentUser else {
            throw AuthTokenError.notSignedIn
        }
        return try await user.getIDToken()
    }
}
