//
//  AuthService.swift
//  Coupley
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

// MARK: - Protocol

protocol AuthServiceProtocol {
    func signIn(email: String, password: String) async throws
    func signUp(email: String, password: String, displayName: String) async throws
    func signOut() throws
}

// MARK: - Firebase Implementation

final class FirebaseAuthService: AuthServiceProtocol {

    private let db = Firestore.firestore()

    func signIn(email: String, password: String) async throws {
        try await Auth.auth().signIn(withEmail: email, password: password)
    }

    func signUp(email: String, password: String, displayName: String) async throws {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)

        let changeRequest = result.user.createProfileChangeRequest()
        changeRequest.displayName = displayName
        try await changeRequest.commitChanges()

        // Create Firestore user document (no coupleId yet — triggers .needsPairing)
        try await db.collection(FirestorePath.users).document(result.user.uid).setData([
            "userId": result.user.uid,
            "displayName": displayName,
            "email": email,
            "createdAt": FieldValue.serverTimestamp()
        ])
    }

    func signOut() throws {
        try Auth.auth().signOut()
    }
}
