//
//  DreamBoardService.swift
//  Coupley
//
//  Firestore CRUD + observation for dreams at
//  couples/{coupleId}/dreams/{dreamId}.
//
//  Dreams don't track progress, contributions, or streaks — they're just an
//  emotional placeholder. The service is therefore the simplest of the three.
//

import Foundation
import FirebaseFirestore

// MARK: - Protocol

protocol DreamBoardService {
    func create(coupleId: String, dream: Dream) async throws
    func update(coupleId: String, dream: Dream) async throws
    func delete(coupleId: String, id: String) async throws

    func observe(
        coupleId: String,
        onUpdate: @escaping ([Dream]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration
}

// MARK: - Firestore Path

extension FirestorePath {
    static func dreams(coupleId: String) -> String {
        "\(couples)/\(coupleId)/dreams"
    }
}

// MARK: - Firestore Implementation

final class FirestoreDreamBoardService: DreamBoardService {

    private let db = Firestore.firestore()

    func create(coupleId: String, dream: Dream) async throws {
        try await collection(coupleId)
            .document(dream.id)
            .setData(Self.payload(from: dream, forCreate: true))
    }

    func update(coupleId: String, dream: Dream) async throws {
        var updated = dream
        updated.updatedAt = Date()
        try await collection(coupleId)
            .document(updated.id)
            .setData(Self.payload(from: updated, forCreate: false), merge: true)
    }

    func delete(coupleId: String, id: String) async throws {
        try await collection(coupleId).document(id).delete()
    }

    func observe(
        coupleId: String,
        onUpdate: @escaping ([Dream]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        collection(coupleId)
            .order(by: "createdAt", descending: true)
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
        db.collection(FirestorePath.dreams(coupleId: coupleId))
    }

    private static func payload(from d: Dream, forCreate: Bool) -> [String: Any] {
        var dict: [String: Any] = [
            "id":        d.id,
            "title":     d.title,
            "category":  d.category.rawValue,
            "colorway":  d.colorway.rawValue,
            "horizon":   d.horizon.rawValue,
            "createdBy": d.createdBy,
            "createdAt": Timestamp(date: d.createdAt),
            "updatedAt": Timestamp(date: d.updatedAt)
        ]

        if let url = d.photoURL, !url.isEmpty {
            dict["photoURL"] = url
        } else if !forCreate {
            dict["photoURL"] = FieldValue.delete()
        }

        if let note = d.note, !note.isEmpty {
            dict["note"] = note
        } else if !forCreate {
            dict["note"] = FieldValue.delete()
        }

        if let inspiration = d.inspiration, !inspiration.isEmpty {
            dict["inspiration"] = inspiration
        } else if !forCreate {
            dict["inspiration"] = FieldValue.delete()
        }

        if let firstStep = d.firstStep, !firstStep.isEmpty {
            dict["firstStep"] = firstStep
        } else if !forCreate {
            dict["firstStep"] = FieldValue.delete()
        }

        return dict
    }

    private static func decode(_ doc: QueryDocumentSnapshot) -> Dream? {
        let data = doc.data()
        guard
            let id          = data["id"] as? String,
            let title       = data["title"] as? String,
            let categoryRaw = data["category"] as? String,
            let category    = DreamCategory(rawValue: categoryRaw),
            let colorwayRaw = data["colorway"] as? String,
            let colorway    = TogetherColorway(rawValue: colorwayRaw),
            let horizonRaw  = data["horizon"] as? String,
            let horizon     = DreamHorizon(rawValue: horizonRaw),
            let createdBy   = data["createdBy"] as? String,
            let createdAt   = (data["createdAt"] as? Timestamp)?.dateValue()
        else { return nil }

        let updatedAt   = (data["updatedAt"] as? Timestamp)?.dateValue() ?? createdAt
        let photoURL    = (data["photoURL"]    as? String).flatMap { $0.isEmpty ? nil : $0 }
        let note        = (data["note"]        as? String).flatMap { $0.isEmpty ? nil : $0 }
        let inspiration = (data["inspiration"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let firstStep   = (data["firstStep"]   as? String).flatMap { $0.isEmpty ? nil : $0 }

        var d = Dream(
            id: id,
            title: title,
            category: category,
            colorway: colorway,
            horizon: horizon,
            photoURL: photoURL,
            note: note,
            inspiration: inspiration,
            firstStep: firstStep,
            createdBy: createdBy,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        d.firestoreId = doc.documentID
        return d
    }
}

// MARK: - Mock

final class MockDreamBoardService: DreamBoardService {
    func create(coupleId: String, dream: Dream) async throws {}
    func update(coupleId: String, dream: Dream) async throws {}
    func delete(coupleId: String, id: String) async throws {}
    func observe(
        coupleId: String,
        onUpdate: @escaping ([Dream]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        onUpdate(SampleTogetherData.dreams)
        return MockListenerRegistration {}
    }
}
