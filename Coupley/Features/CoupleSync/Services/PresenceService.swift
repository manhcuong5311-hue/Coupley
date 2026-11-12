//
//  PresenceService.swift
//  Coupley
//
//  Lightweight presence: observes the partner's heartbeat on users/{uid}.
//  The heartbeat itself is written by NotificationService.updateLastActive —
//  this file deliberately has no writer of its own, because having two was
//  how `updateHeartbeat` ended up dead code that nothing ever called.
//

import Foundation
import FirebaseFirestore

// MARK: - Presence Service Protocol

protocol PresenceService {
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
                // `presenceActive` is written false the moment the partner
                // backgrounds the app. Without it, `lastSeen` stays fresh for
                // the whole window after they have gone, so they read as
                // online for up to two minutes too long — long enough to
                // invite a live reaction at someone who already left.
                //
                // Absent on documents written by older clients, which is why
                // this is `!= false` rather than `== true`: those fall back
                // to the timestamp alone.
                let explicitlyInactive = (data?["presenceActive"] as? Bool) == false
                let online: Bool
                if let lastSeen, !explicitlyInactive {
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
    func sendPing(coupleId: String, fromUserId: String) async throws {}
    func observePartnerPresence(
        partnerId: String,
        onUpdate: @escaping (Date?, Bool) -> Void
    ) -> ListenerRegistration {
        onUpdate(Date().addingTimeInterval(-300), false)
        return MockListenerRegistration {}
    }
}
