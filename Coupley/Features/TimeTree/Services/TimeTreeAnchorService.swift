//
//  TimeTreeAnchorService.swift
//  Coupley
//
//  Reads and writes the single RelationshipAnchor document at
//  couples/{coupleId}/timeTreeMeta/config. Both partners share this
//  anchor — last write wins, which is fine because anchor changes are
//  rare and intentional.
//

import Foundation
import FirebaseFirestore

// MARK: - Protocol

protocol TimeTreeAnchorService {
    func setAnchor(coupleId: String, anchor: RelationshipAnchor) async throws
    func observe(
        coupleId: String,
        onUpdate: @escaping (RelationshipAnchor?) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration
}

// MARK: - Firestore Path

extension FirestorePath {
    static func timeTreeMeta(coupleId: String) -> String {
        "\(couples)/\(coupleId)/timeTreeMeta"
    }

    static let timeTreeAnchorDocId = "config"
}

// MARK: - Firestore Implementation

final class FirestoreTimeTreeAnchorService: TimeTreeAnchorService {

    private let db = Firestore.firestore()

    // MARK: - Set / Update

    func setAnchor(coupleId: String, anchor: RelationshipAnchor) async throws {
        try await document(coupleId).setData(Self.payload(from: anchor), merge: true)
    }

    // MARK: - Observe

    func observe(
        coupleId: String,
        onUpdate: @escaping (RelationshipAnchor?) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        document(coupleId)
            .addSnapshotListener { snapshot, error in
                if let error {
                    onError(error)
                    return
                }
                guard let snapshot, snapshot.exists, let data = snapshot.data() else {
                    onUpdate(nil)
                    return
                }
                onUpdate(Self.decode(data))
            }
    }

    // MARK: - Helpers

    private func document(_ coupleId: String) -> DocumentReference {
        db.collection(FirestorePath.timeTreeMeta(coupleId: coupleId))
            .document(FirestorePath.timeTreeAnchorDocId)
    }

    private static func payload(from a: RelationshipAnchor) -> [String: Any] {
        var dict: [String: Any] = [
            "startDate": Timestamp(date: a.startDate),
            "setBy":     a.setBy,
            "setAt":     Timestamp(date: a.setAt),
            "updatedAt": Timestamp(date: Date())
        ]
        if let name = a.setByName, !name.isEmpty {
            dict["setByName"] = name
        } else {
            dict["setByName"] = FieldValue.delete()
        }
        return dict
    }

    private static func decode(_ data: [String: Any]) -> RelationshipAnchor? {
        guard
            let startDate = (data["startDate"] as? Timestamp)?.dateValue(),
            let setBy     = data["setBy"] as? String
        else { return nil }

        let setByName = (data["setByName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let setAt     = (data["setAt"] as? Timestamp)?.dateValue() ?? Date()
        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? setAt

        return RelationshipAnchor(
            startDate: startDate,
            setBy: setBy,
            setByName: setByName,
            setAt: setAt,
            updatedAt: updatedAt
        )
    }
}
