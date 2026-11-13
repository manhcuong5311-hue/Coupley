//
//  TimeTreeMemoryService.swift
//  Coupley
//
//  Firestore CRUD + real-time observation for the memory collection at
//  couples/{coupleId}/memories. The Anniversary subcollection is left
//  untouched — those still drive countdowns. Memories are the past-tense
//  emotional ledger; capsules are memories with a future unlock date.
//
//  Writes use the confirmed helpers (Core/FirestoreConfirmedWrite.swift): a
//  server rejection throws, and offline the write is queued and the call
//  returns after a short wait instead of hanging until reconnection.
//

import Foundation
import FirebaseFirestore

// MARK: - Protocol

protocol TimeTreeMemoryService {
    func create(coupleId: String, memory: TimeMemory) async throws
    func update(coupleId: String, memory: TimeMemory) async throws
    func delete(coupleId: String, id: String) async throws
    func observe(
        coupleId: String,
        onUpdate: @escaping ([TimeMemory]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration
}

// MARK: - Firestore Path

extension FirestorePath {
    static func memories(coupleId: String) -> String {
        "\(couples)/\(coupleId)/memories"
    }
}

// MARK: - Firestore Implementation

final class FirestoreTimeTreeMemoryService: TimeTreeMemoryService {

    private let db = Firestore.firestore()

    // MARK: - Create

    func create(coupleId: String, memory: TimeMemory) async throws {
        try await collection(coupleId)
            .document(memory.id)
            .setDataConfirmed(Self.payload(from: memory, forCreate: true), merge: false)
    }

    // MARK: - Update

    /// Writes every field of `memory`, including `id` and `createdBy`
    /// unchanged: the rules for /memories require both to stay as they are.
    /// An update, never a merging set: a memory deleted on the other phone
    /// (even while this write waited offline) fails (NOT_FOUND, or
    /// PERMISSION_DENIED under the hardened rules) instead
    /// of coming back.
    func update(coupleId: String, memory: TimeMemory) async throws {
        var updated = memory
        updated.updatedAt = Date()
        try await collection(coupleId)
            .document(updated.id)
            .updateDataConfirmed(Self.payload(from: updated, forCreate: false))
    }

    // MARK: - Delete

    func delete(coupleId: String, id: String) async throws {
        try await collection(coupleId).document(id).deleteConfirmed()
    }

    // MARK: - Observe

    func observe(
        coupleId: String,
        onUpdate: @escaping ([TimeMemory]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        collection(coupleId)
            .order(by: "date", descending: true)
            .addSnapshotListener { snapshot, error in
                if let error {
                    onError(error)
                    return
                }
                // No snapshot says nothing; it must not read as "no memories".
                guard let snapshot else { return }
                onUpdate(snapshot.documents.compactMap { Self.decode($0) })
            }
    }

    // MARK: - Helpers

    private func collection(_ coupleId: String) -> CollectionReference {
        db.collection(FirestorePath.memories(coupleId: coupleId))
    }

    /// Builds the Firestore payload for a memory.
    ///
    /// `forCreate == true`: nil optional fields are omitted entirely
    /// (`setData` without merge would reject `FieldValue.delete()`).
    /// `forCreate == false`: nil optional fields use `FieldValue.delete()`
    /// so the `updateData` write explicitly removes them.
    private static func payload(from m: TimeMemory, forCreate: Bool) -> [String: Any] {
        var dict: [String: Any] = [
            "id":          m.id,
            "kind":        m.kind.rawValue,
            "title":       m.title,
            "date":        Timestamp(date: m.date),
            "note":        m.note ?? "",
            "emotions":    m.emotions.map(\.rawValue),
            "attribution": m.attribution ?? "",
            "createdBy":   m.createdBy,
            "createdAt":   Timestamp(date: m.createdAt),
            "updatedAt":   Timestamp(date: m.updatedAt)
        ]

        if let url = m.photoURL {
            dict["photoURL"] = url
        } else if !forCreate {
            dict["photoURL"] = FieldValue.delete()
        }

        if let unlockDate = m.unlockDate {
            dict["unlockDate"] = Timestamp(date: unlockDate)
        } else if !forCreate {
            dict["unlockDate"] = FieldValue.delete()
        }

        if let anniversaryId = m.anniversaryId {
            dict["anniversaryId"] = anniversaryId
        } else if !forCreate {
            dict["anniversaryId"] = FieldValue.delete()
        }

        return dict
    }

    private static func decode(_ doc: QueryDocumentSnapshot) -> TimeMemory? {
        let data = doc.data()
        guard
            let id        = data["id"] as? String,
            let kindRaw   = data["kind"] as? String,
            let kind      = MemoryKind(rawValue: kindRaw),
            let title     = data["title"] as? String,
            let date      = (data["date"] as? Timestamp)?.dateValue(),
            let createdBy = data["createdBy"] as? String
        else { return nil }

        let note      = (data["note"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let photoURL  = (data["photoURL"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let attribution = (data["attribution"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let anniversaryId = (data["anniversaryId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let unlockDate = (data["unlockDate"] as? Timestamp)?.dateValue()
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? date
        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? createdAt

        let emotions: [MemoryEmotion] = ((data["emotions"] as? [String]) ?? [])
            .compactMap(MemoryEmotion.init(rawValue:))

        var item = TimeMemory(
            id: id,
            kind: kind,
            title: title,
            date: date,
            note: note,
            photoURL: photoURL,
            emotions: emotions,
            attribution: attribution,
            anniversaryId: anniversaryId,
            unlockDate: unlockDate,
            createdBy: createdBy,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        item.firestoreId = doc.documentID
        return item
    }
}
