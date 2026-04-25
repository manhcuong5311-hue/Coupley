//
//  ConnectionService.swift
//  Coupley
//
//  Soft-disconnect + later hard-delete. The disconnect flow never deletes
//  shared data — it just flips status on couples/{coupleId} and clears the
//  live `coupleId`/`partnerId` links on both user docs, preserving them in
//  `lastCoupleId`/`lastPartnerId` so the owner can return later and remove
//  data intentionally.
//

import Foundation
import FirebaseFirestore

// MARK: - Protocol

protocol ConnectionService {
    /// Soft-disconnect. Does NOT delete shared data.
    func disconnect(session: UserSession, partnerDisplayName: String?) async throws

    /// Loads the archived connection document so cleanup screens can show
    /// a summary (dates / who disconnected).
    func loadConnection(connectionId: String) async throws -> PartnerConnection?

    /// Hard delete. Removes all known shared subcollections under the
    /// couple, then the couple doc itself, then clears `lastCoupleId` /
    /// `lastPartnerId` on the caller's user doc.
    func deleteSharedData(connectionId: String, userId: String) async throws

    /// Clears the one-shot "your partner disconnected" banner flag.
    func acknowledgeDisconnectNotice(userId: String) async throws
}

// MARK: - Errors

enum ConnectionError: LocalizedError {
    case notConnected
    case alreadyDisconnected
    case connectionNotFound

    var errorDescription: String? {
        switch self {
        case .notConnected:        return "You're not connected to a partner."
        case .alreadyDisconnected: return "This connection has already been disconnected."
        case .connectionNotFound:  return "We couldn't find that shared data."
        }
    }
}

// MARK: - Firestore Implementation

final class FirestoreConnectionService: ConnectionService {

    private let db = Firestore.firestore()

    // MARK: - Disconnect (soft)

    func disconnect(session: UserSession, partnerDisplayName: String?) async throws {
        guard session.isPaired else { throw ConnectionError.notConnected }

        let coupleRef  = db.collection(FirestorePath.couples).document(session.coupleId)
        let meRef      = db.collection(FirestorePath.users).document(session.userId)
        let partnerRef = db.collection(FirestorePath.users).document(session.partnerId)

        // Atomicity matters: if the batch partially commits we end up with
        // one user still "paired" to a disconnected couple.
        let batch = db.batch()

        batch.setData([
            ConnectionField.status:         ConnectionStatus.disconnected.rawValue,
            ConnectionField.disconnectedAt: FieldValue.serverTimestamp(),
            ConnectionField.disconnectedBy: session.userId
        ], forDocument: coupleRef, merge: true)

        // Clear the shared premium slot atomically with the disconnect so the
        // non-paying partner drops to free the instant the batch commits.
        // The paying user's `/users/{uid}.premium` is NOT touched here —
        // their real subscription must survive disconnect (ownership rule).
        batch.setData([
            "premium": ["active": false]
        ], forDocument: coupleRef, merge: true)

        // Archive the link on the initiator's doc.
        batch.setData([
            ConnectionField.coupleId:      FieldValue.delete(),
            ConnectionField.partnerId:     FieldValue.delete(),
            ConnectionField.lastCoupleId:  session.coupleId,
            ConnectionField.lastPartnerId: session.partnerId
        ], forDocument: meRef, merge: true)

        // Archive on the other user's doc AND raise the one-shot notice
        // flag so their client can surface "Your partner has disconnected."
        var partnerPayload: [String: Any] = [
            ConnectionField.coupleId:                FieldValue.delete(),
            ConnectionField.partnerId:               FieldValue.delete(),
            ConnectionField.lastCoupleId:            session.coupleId,
            ConnectionField.lastPartnerId:           session.userId,
            ConnectionField.pendingDisconnectNotice: true
        ]
        if let name = partnerDisplayName, !name.isEmpty {
            partnerPayload[ConnectionField.lastPartnerName] = name
        }
        batch.setData(partnerPayload, forDocument: partnerRef, merge: true)

        try await batch.commit()
    }

    // MARK: - Load archived connection

    func loadConnection(connectionId: String) async throws -> PartnerConnection? {
        let snap = try await db.collection(FirestorePath.couples)
            .document(connectionId)
            .getDocument()
        guard let data = snap.data() else { return nil }
        return PartnerConnection(connectionId: connectionId, data: data)
    }

    // MARK: - Delete shared data (hard)

    func deleteSharedData(connectionId: String, userId: String) async throws {
        guard !connectionId.isEmpty else { throw ConnectionError.connectionNotFound }

        let coupleRef = db.collection(FirestorePath.couples).document(connectionId)

        // Safety: refuse if the connection is still active. Hard-delete is
        // only allowed on an already-disconnected couple — prevents a bug
        // from nuking a live pairing.
        //
        // A missing couple doc is fine: the auto-cleanup cron likely ran
        // already, so we just clear the pointer below.
        let snap = try await coupleRef.getDocument()
        if snap.exists,
           let data = snap.data(),
           let statusRaw = data[ConnectionField.status] as? String,
           statusRaw == ConnectionStatus.active.rawValue {
            throw ConnectionError.alreadyDisconnected
        }

        // Subcollections under couples/{coupleId} that we know about.
        // Keep this list in sync when new shared data is added.
        let simpleSubcollections = [
            "messages",
            "quizzes",
            "syncScores",
            "coupleProfile",
            "notifications"
        ]

        for name in simpleSubcollections {
            try await deleteCollection(coupleRef.collection(name))
        }

        // Moods have nested `reactions` under each mood doc — purge those
        // first so we don't orphan documents.
        try await deleteMoodsWithReactions(coupleRef: coupleRef)

        // Finally, the couple doc itself.
        try await coupleRef.delete()

        // Clear the pointer on the caller's user doc. (We don't touch the
        // other user's doc — they do their own cleanup when they're ready.)
        try await db.collection(FirestorePath.users).document(userId).setData([
            ConnectionField.lastCoupleId:  FieldValue.delete(),
            ConnectionField.lastPartnerId: FieldValue.delete(),
            ConnectionField.lastPartnerName: FieldValue.delete()
        ], merge: true)
    }

    /// Paginates a collection and deletes up to `pageSize` docs per batch.
    /// Firestore has no recursive delete on the client SDK; a Cloud Function
    /// would be more robust for very large datasets.
    private func deleteCollection(
        _ ref: CollectionReference,
        pageSize: Int = 300
    ) async throws {
        while true {
            let snap = try await ref.limit(to: pageSize).getDocuments()
            if snap.documents.isEmpty { return }

            let batch = db.batch()
            for doc in snap.documents {
                batch.deleteDocument(doc.reference)
            }
            try await batch.commit()

            if snap.documents.count < pageSize { return }
        }
    }

    private func deleteMoodsWithReactions(coupleRef: DocumentReference) async throws {
        let moodsRef = coupleRef.collection("moods")
        while true {
            let snap = try await moodsRef.limit(to: 100).getDocuments()
            if snap.documents.isEmpty { return }

            for doc in snap.documents {
                try await deleteCollection(doc.reference.collection("reactions"))
            }

            let batch = db.batch()
            for doc in snap.documents {
                batch.deleteDocument(doc.reference)
            }
            try await batch.commit()

            if snap.documents.count < 100 { return }
        }
    }

    // MARK: - Acknowledge notice

    func acknowledgeDisconnectNotice(userId: String) async throws {
        try await db.collection(FirestorePath.users).document(userId).setData([
            ConnectionField.pendingDisconnectNotice: FieldValue.delete()
        ], merge: true)
    }
}

// MARK: - Auto-cleanup (server-side spec)
//
// The client-side delete above is only triggered when the user taps
// "Delete all shared data". We also want a safety net that removes
// long-abandoned disconnected connections automatically.
//
// Deploy as a Cloud Function scheduled job (Firebase Functions) — keeping
// the spec here so it lives next to the client code that produced the data.
//
// Pseudocode (Node / functions.pubsub.schedule):
//
//   exports.autoCleanupDisconnectedCouples = functions.pubsub
//     .schedule("every 24 hours")
//     .onRun(async () => {
//       const cutoff = admin.firestore.Timestamp.fromDate(
//         new Date(Date.now() - 30 * 24 * 60 * 60 * 1000)   // 30 days
//       );
//
//       const stale = await db.collection("couples")
//         .where("status", "==", "disconnected")
//         .where("disconnectedAt", "<=", cutoff)
//         .limit(50)
//         .get();
//
//       for (const doc of stale.docs) {
//         // Delete subcollections: moods (+ nested reactions), messages,
//         // quizzes, syncScores, coupleProfile, notifications.
//         await deleteSubcollections(doc.ref);
//         await doc.ref.delete();
//       }
//     });
//
// Notes:
//  - Use `firebase-tools` `firestore:delete --recursive` or a helper that
//    paginates to avoid the 500-write batch limit.
//  - Both user docs still carry `lastCoupleId` pointing at the deleted
//    couple; the client treats a missing couple doc as "already cleaned"
//    and silently clears those fields on next read.
//  - Set `disconnectedAt` with `FieldValue.serverTimestamp()` (as we do
//    in `disconnect(session:)`) so the 30-day window is clock-skew safe.

