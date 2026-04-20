//
//  PresenceService.swift
//  Coupley
//
//  Lightweight presence: writes a heartbeat to users/{uid} and observes the partner's.
//

import Foundation
import FirebaseFirestore

// MARK: - Presence Service Protocol

protocol PresenceService {
    func updateHeartbeat(userId: String) async throws
    func sendPing(coupleId: String, fromUserId: String) async throws
    func observePartnerPresence(
        partnerId: String,
        onUpdate: @escaping (Date?, Bool) -> Void
    ) -> ListenerRegistration
}

// MARK: - Firestore Presence Service

final class FirestorePresenceService: PresenceService {

    private let db = Firestore.firestore()

    /// Threshold for considering a user "online" based on lastSeen.
    private let onlineWindow: TimeInterval = 120 // 2 minutes

    func updateHeartbeat(userId: String) async throws {
        guard !userId.isEmpty else { return }
        try await db.collection(FirestorePath.users).document(userId).setData([
            "lastSeen": FieldValue.serverTimestamp(),
            "timezone": TimeZone.current.identifier
        ], merge: true)
    }

    func sendPing(coupleId: String, fromUserId: String) async throws {
        guard !coupleId.isEmpty, !fromUserId.isEmpty else { return }
        try await db.collection("couples/\(coupleId)/pings").addDocument(data: [
            "fromUserId": fromUserId,
            "createdAt": FieldValue.serverTimestamp()
        ])
    }

    func observePartnerPresence(
        partnerId: String,
        onUpdate: @escaping (Date?, Bool) -> Void
    ) -> ListenerRegistration {
        db.collection(FirestorePath.users).document(partnerId)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self else { return }
                let data = snapshot?.data()
                let lastSeen = (data?["lastSeen"] as? Timestamp)?.dateValue()
                let online: Bool
                if let lastSeen {
                    online = Date().timeIntervalSince(lastSeen) < self.onlineWindow
                } else {
                    online = false
                }
                onUpdate(lastSeen, online)
            }
    }
}

// MARK: - Mock

final class MockPresenceService: PresenceService {
    func updateHeartbeat(userId: String) async throws {}
    func sendPing(coupleId: String, fromUserId: String) async throws {}
    func observePartnerPresence(
        partnerId: String,
        onUpdate: @escaping (Date?, Bool) -> Void
    ) -> ListenerRegistration {
        onUpdate(Date().addingTimeInterval(-300), false)
        return MockListenerRegistration {}
    }
}
