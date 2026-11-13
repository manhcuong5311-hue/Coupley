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
        let expiry = PresenceExpiry()
        return db.collection(FirestorePath.users).document(partnerId)
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

                // "Online" was only ever re-evaluated when this document
                // changed. A partner who drops off without the background
                // write (crash, lost network, or a 1.1 build that never
                // writes `presenceActive`) leaves it unchanged forever, so
                // the Home hero kept saying they had the app open — still
                // there the next morning. Time it out locally instead.
                expiry.schedule(online: online, lastSeen: lastSeen, window: self.onlineWindow) {
                    onUpdate(lastSeen, false)
                }
            }
    }
}

// MARK: - Expiry

/// Flips presence to offline once the online window lapses with no newer
/// heartbeat. Every snapshot supersedes the previous timer.
private final class PresenceExpiry {
    private var generation = 0

    func schedule(online: Bool, lastSeen: Date?, window: TimeInterval,
                  expire: @escaping () -> Void) {
        generation += 1
        guard online, let lastSeen else { return }
        let token = generation
        let remaining = max(0, window - Date().timeIntervalSince(lastSeen)) + 1
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { [weak self] in
            guard let self, self.generation == token else { return }
            expire()
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
