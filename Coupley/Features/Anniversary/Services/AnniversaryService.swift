//
//  AnniversaryService.swift
//  Coupley
//

import Foundation
import FirebaseFirestore

// MARK: - Protocol

protocol AnniversaryService {
    func create(coupleId: String, anniversary: Anniversary) async throws
    func update(coupleId: String, anniversary: Anniversary) async throws
    func delete(coupleId: String, id: String) async throws
    func observe(
        coupleId: String,
        onUpdate: @escaping ([Anniversary]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration
}

// MARK: - Firestore Path

extension FirestorePath {
    static func anniversaries(coupleId: String) -> String {
        "\(couples)/\(coupleId)/anniversaries"
    }
}

// MARK: - Firestore Implementation

final class FirestoreAnniversaryService: AnniversaryService {

    private let db = Firestore.firestore()

    // MARK: - Create

    func create(coupleId: String, anniversary: Anniversary) async throws {
        try await collection(coupleId)
            .document(anniversary.id)
            .setData(Self.payload(from: anniversary))
    }

    // MARK: - Update

    func update(coupleId: String, anniversary: Anniversary) async throws {
        var updated = anniversary
        updated.updatedAt = Date()
        try await collection(coupleId)
            .document(updated.id)
            .setData(Self.payload(from: updated), merge: true)
    }

    // MARK: - Delete

    func delete(coupleId: String, id: String) async throws {
        try await collection(coupleId).document(id).delete()
    }

    // MARK: - Observe

    func observe(
        coupleId: String,
        onUpdate: @escaping ([Anniversary]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        collection(coupleId)
            .order(by: "date", descending: false)
            .addSnapshotListener { snapshot, error in
                if let error {
                    onError(error)
                    return
                }
                let items = snapshot?.documents.compactMap { Self.decode($0) } ?? []
                onUpdate(items)
            }
    }

    // MARK: - Helpers

    private func collection(_ coupleId: String) -> CollectionReference {
        db.collection(FirestorePath.anniversaries(coupleId: coupleId))
    }

    private static func payload(from a: Anniversary) -> [String: Any] {
        [
            "id":              a.id,
            "title":           a.title,
            "date":            Timestamp(date: a.date),
            "note":            a.note ?? "",
            "creatorTimezone": a.creatorTimezone,
            "createdBy":       a.createdBy,
            "createdAt":       Timestamp(date: a.createdAt),
            "updatedAt":       Timestamp(date: a.updatedAt)
        ]
    }

    private static func decode(_ doc: QueryDocumentSnapshot) -> Anniversary? {
        let data = doc.data()
        guard
            let id         = data["id"] as? String,
            let title      = data["title"] as? String,
            let date       = (data["date"] as? Timestamp)?.dateValue(),
            let createdBy  = data["createdBy"] as? String
        else { return nil }

        let note      = (data["note"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let tz        = (data["creatorTimezone"] as? String) ?? TimeZone.current.identifier
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? date
        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? createdAt

        var item = Anniversary(
            id: id,
            title: title,
            date: date,
            note: note,
            creatorTimezone: tz,
            createdBy: createdBy,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        item.firestoreId = doc.documentID
        return item
    }
}
