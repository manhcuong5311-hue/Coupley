//
//  PairingService.swift
//  Coupley
//

import Foundation
import FirebaseFirestore

// MARK: - Protocol

protocol PairingServiceProtocol {
    func createInviteCode(userId: String, displayName: String) async throws -> String
    func joinWithCode(_ code: String, userId: String) async throws
    /// Peek at a code without consuming it — returns the creator's public info
    /// so the UI can show "Connect with Alex?" before the user taps Confirm.
    func previewCode(_ code: String) async throws -> PartnerPreview
}

// MARK: - Partner Preview

struct PartnerPreview: Equatable {
    let userId: String
    let displayName: String
}

// MARK: - Errors

enum PairingError: LocalizedError {
    case invalidCode
    case cannotJoinOwnCode
    case expiredCode

    var errorDescription: String? {
        switch self {
        case .invalidCode:       return "That code doesn't exist or has already been used."
        case .cannotJoinOwnCode: return "You can't connect using your own invite code."
        case .expiredCode:       return "This code has expired. Ask your partner to create a new one."
        }
    }
}

// MARK: - Firestore Implementation

final class FirestorePairingService: PairingServiceProtocol {

    private let db = Firestore.firestore()

    // MARK: - Create

    func createInviteCode(userId: String, displayName: String) async throws -> String {
        // 6-char code excluding ambiguous chars (0/O, 1/I/L)
        let chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        let code = String((0..<6).map { _ in chars.randomElement()! })

        try await db.collection(FirestorePath.pairingCodes).document(code).setData([
            "creatorId": userId,
            "creatorName": displayName,
            "createdAt": FieldValue.serverTimestamp(),
            "expiresAt": Timestamp(date: Date().addingTimeInterval(24 * 60 * 60))
        ])

        return code
    }

    // MARK: - Preview

    func previewCode(_ code: String) async throws -> PartnerPreview {
        let normalised = code.uppercased().trimmingCharacters(in: .whitespaces)
        let snapshot = try await db.collection(FirestorePath.pairingCodes)
            .document(normalised)
            .getDocument()

        guard snapshot.exists, let data = snapshot.data(),
              let creatorId = data["creatorId"] as? String else {
            throw PairingError.invalidCode
        }

        if let expires = (data["expiresAt"] as? Timestamp)?.dateValue(),
           expires < Date() {
            throw PairingError.expiredCode
        }

        // Prefer the name stored on the code doc; fall back to the user doc
        // for codes created before we started saving creatorName.
        if let name = data["creatorName"] as? String, !name.isEmpty {
            return PartnerPreview(userId: creatorId, displayName: name)
        }

        let userSnap = try await db.collection(FirestorePath.users)
            .document(creatorId)
            .getDocument()
        let displayName = (userSnap.data()?["displayName"] as? String) ?? "Partner"
        return PartnerPreview(userId: creatorId, displayName: displayName)
    }

    // MARK: - Join

    func joinWithCode(_ code: String, userId: String) async throws {
        let normalised = code.uppercased().trimmingCharacters(in: .whitespaces)
        let codeRef = db.collection(FirestorePath.pairingCodes).document(normalised)
        let snapshot = try await codeRef.getDocument()

        guard snapshot.exists,
              let data = snapshot.data(),
              let creatorId = data["creatorId"] as? String else {
            throw PairingError.invalidCode
        }

        guard creatorId != userId else {
            throw PairingError.cannotJoinOwnCode
        }

        if let expires = (data["expiresAt"] as? Timestamp)?.dateValue(),
           expires < Date() {
            throw PairingError.expiredCode
        }

        // All writes in a single batch for atomicity
        let coupleRef = db.collection(FirestorePath.couples).document()
        let coupleId = coupleRef.documentID
        let batch = db.batch()

        batch.setData([
            "userIds": [creatorId, userId],
            "createdAt": FieldValue.serverTimestamp(),
            "currentStreak": 0,
            "longestStreak": 0
        ], forDocument: coupleRef)

        // Give each user their coupleId and partnerId
        batch.setData(
            ["coupleId": coupleId, "partnerId": userId],
            forDocument: db.collection(FirestorePath.users).document(creatorId),
            merge: true
        )

        batch.setData(
            ["coupleId": coupleId, "partnerId": creatorId],
            forDocument: db.collection(FirestorePath.users).document(userId),
            merge: true
        )

        batch.deleteDocument(codeRef)

        try await batch.commit()
        // SessionStore is listening to users/{userId} — it will detect coupleId and
        // automatically transition appState to .ready(session)
    }
}
