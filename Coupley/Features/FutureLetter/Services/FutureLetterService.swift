//
//  FutureLetterService.swift
//  Coupley
//
//  Firestore access for future letters. See FutureLetter.swift for the
//  two-document model and firestore.rules for the time lock.
//

import Foundation
import FirebaseFirestore

protocol FutureLetterServicing {
    /// Every envelope of the couple, newest open date first. `pendingIds` are
    /// documents with local writes the server has not acknowledged yet.
    func observeLetters(
        coupleId: String,
        onUpdate: @escaping (_ letters: [FutureLetter], _ pendingIds: Set<String>, _ isFromCache: Bool) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration

    /// Writes the envelope and the body in one batch. Returns the letter id.
    @discardableResult
    func seal(text: String, opensAt: Date, coupleId: String, fromUserId: String, toUserId: String) async throws -> String

    func fetchBody(coupleId: String, letterId: String, source: FirestoreSource) async throws -> FutureLetterBody

    /// The recipient's one-time receipt. Fire-and-forget.
    func markOpened(coupleId: String, letterId: String)

    /// Deletes both documents in one transaction, which is never queued
    /// offline. The rules allow it only for the sender, and only before the
    /// letter opens.
    func unsend(coupleId: String, letterId: String) async throws
}

final class FirestoreFutureLetterService: FutureLetterServicing {

    private let db = Firestore.firestore()

    private func envelopes(_ coupleId: String) -> CollectionReference {
        db.collection(FirestorePath.futureLetters(coupleId: coupleId))
    }

    private func bodies(_ coupleId: String) -> CollectionReference {
        db.collection(FirestorePath.futureLetterBodies(coupleId: coupleId))
    }

    // MARK: - Observe

    func observeLetters(
        coupleId: String,
        onUpdate: @escaping ([FutureLetter], Set<String>, Bool) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        // A single-field order needs no composite index. The limit is only a
        // guard; a couple writing 500 letters is not a case to design for.
        envelopes(coupleId)
            .order(by: "opensAt", descending: true)
            .limit(to: 500)
            .addSnapshotListener(includeMetadataChanges: true) { snapshot, error in
                if let error { onError(error); return }
                guard let snapshot else { return }
                let documents = snapshot.documents
                onUpdate(
                    documents.compactMap { try? $0.data(as: FutureLetter.self, with: .estimate) },
                    Set(documents.filter { $0.metadata.hasPendingWrites }.map(\.documentID)),
                    snapshot.metadata.isFromCache
                )
            }
    }

    // MARK: - Seal

    @discardableResult
    func seal(text: String, opensAt: Date, coupleId: String, fromUserId: String, toUserId: String) async throws -> String {
        let envelopeRef = envelopes(coupleId).document()
        let id = envelopeRef.documentID
        // ONE value for both documents: the rules require them to be equal.
        let opens = Timestamp(date: opensAt)

        let batch = db.batch()
        // Explicit dictionaries rather than Codable: the key sets must match
        // the rules' `keys().hasOnly(...)` lists exactly, and an encoder would
        // add `firestoreId` handling and nil fields.
        batch.setData([
            "id": id,
            "fromUserId": fromUserId,
            "toUserId": toUserId,
            "opensAt": opens,
            "sealedAt": FieldValue.serverTimestamp()
        ], forDocument: envelopeRef)
        batch.setData([
            "fromUserId": fromUserId,
            "toUserId": toUserId,
            "opensAt": opens,
            "text": text
        ], forDocument: bodies(coupleId).document(id))

        try await batch.commitConfirmed()
        return id
    }

    // MARK: - Read

    func fetchBody(coupleId: String, letterId: String, source: FirestoreSource) async throws -> FutureLetterBody {
        let snapshot = try await bodies(coupleId).document(letterId).getDocument(source: source)
        return try snapshot.data(as: FutureLetterBody.self)
    }

    func markOpened(coupleId: String, letterId: String) {
        // If another device of the recipient stamped it first, the rules
        // refuse this one, which is the right outcome.
        envelopes(coupleId).document(letterId)
            .updateData(["openedAt": FieldValue.serverTimestamp()]) { error in
                if let error {
                    print("[FutureLetter] markOpened failed: \(error.localizedDescription)")
                }
            }
    }

    // MARK: - Unsend

    func unsend(coupleId: String, letterId: String) async throws {
        let body = bodies(coupleId).document(letterId)
        let envelope = envelopes(coupleId).document(letterId)
        // A transaction, not a batch. A batch is queued offline and judged by
        // `request.time < opensAt` whenever it finally reaches the server; a
        // refusal then silently restores a letter the sender believes is gone,
        // and the partner can open it. A transaction is never queued: offline
        // it fails, and it returns only once the server has deleted both.
        _ = try await db.runTransaction { transaction, _ -> Any? in
            transaction.deleteDocument(body)
            transaction.deleteDocument(envelope)
            return nil
        }
    }
}
