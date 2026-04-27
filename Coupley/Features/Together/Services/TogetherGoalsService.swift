//
//  TogetherGoalsService.swift
//  Coupley
//
//  Firestore CRUD + observation for goals living at
//  couples/{coupleId}/togetherGoals/{goalId}.
//
//  Mirrors the TimeTreeMemoryService pattern intentionally — same payload
//  helper shape, same `forCreate`/`merge:true` distinction, same observe
//  semantics. The viewmodel doesn't have to learn a new convention to wire
//  this feature in.
//

import Foundation
import FirebaseFirestore

// MARK: - Protocol

protocol TogetherGoalsService {
    func create(coupleId: String, goal: TogetherGoal) async throws
    func update(coupleId: String, goal: TogetherGoal) async throws
    func delete(coupleId: String, id: String) async throws

    /// Add `delta` to the contribution map under the given user. Atomic via
    /// a Firestore transaction so concurrent partners can both write without
    /// stomping each other.
    func recordContribution(
        coupleId: String,
        goalId: String,
        userId: String,
        delta: Double
    ) async throws

    /// Mark a goal complete. Sets `completedAt = now`; does NOT delete the doc
    /// so it can later show up in a "milestones" timeline if we ever build one.
    func markComplete(coupleId: String, goalId: String) async throws

    func observe(
        coupleId: String,
        onUpdate: @escaping ([TogetherGoal]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration
}

// MARK: - Firestore Path

extension FirestorePath {
    static func togetherGoals(coupleId: String) -> String {
        "\(couples)/\(coupleId)/togetherGoals"
    }
}

// MARK: - Firestore Implementation

final class FirestoreTogetherGoalsService: TogetherGoalsService {

    private let db = Firestore.firestore()

    // MARK: - Create

    func create(coupleId: String, goal: TogetherGoal) async throws {
        try await collection(coupleId)
            .document(goal.id)
            .setData(Self.payload(from: goal, forCreate: true))
    }

    // MARK: - Update

    func update(coupleId: String, goal: TogetherGoal) async throws {
        var updated = goal
        updated.updatedAt = Date()
        try await collection(coupleId)
            .document(updated.id)
            .setData(Self.payload(from: updated, forCreate: false), merge: true)
    }

    // MARK: - Delete

    func delete(coupleId: String, id: String) async throws {
        try await collection(coupleId).document(id).delete()
    }

    // MARK: - Contribution

    func recordContribution(
        coupleId: String,
        goalId: String,
        userId: String,
        delta: Double
    ) async throws {
        let ref = collection(coupleId).document(goalId)
        _ = try await db.runTransaction({ txn, errorPointer in
            let snap: DocumentSnapshot
            do {
                snap = try txn.getDocument(ref)
            } catch let err as NSError {
                errorPointer?.pointee = err
                return nil
            }

            var amounts = (snap.data()?["contributionAmounts"] as? [String: Double]) ?? [:]
            amounts[userId, default: 0] += delta
            // Floor at zero so a buggy negative delta can't poison the doc.
            if amounts[userId, default: 0] < 0 {
                amounts[userId] = 0
            }

            txn.setData([
                "contributionAmounts": amounts,
                "updatedAt": Timestamp(date: Date())
            ], forDocument: ref, merge: true)
            return nil
        })
    }

    // MARK: - Mark Complete

    func markComplete(coupleId: String, goalId: String) async throws {
        try await collection(coupleId).document(goalId).setData([
            "completedAt": Timestamp(date: Date()),
            "updatedAt":   Timestamp(date: Date())
        ], merge: true)
    }

    // MARK: - Observe

    func observe(
        coupleId: String,
        onUpdate: @escaping ([TogetherGoal]) -> Void,
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
        db.collection(FirestorePath.togetherGoals(coupleId: coupleId))
    }

    private static func payload(from g: TogetherGoal, forCreate: Bool) -> [String: Any] {
        var dict: [String: Any] = [
            "id":                  g.id,
            "title":               g.title,
            "category":            g.category.rawValue,
            "colorway":            g.colorway.rawValue,
            "trackingMode":        g.trackingMode.rawValue,
            "target":              g.target,
            "contributionAmounts": g.contribution.amounts,
            "createdBy":           g.createdBy,
            "createdAt":           Timestamp(date: g.createdAt),
            "updatedAt":           Timestamp(date: g.updatedAt)
        ]

        if let due = g.dueDate {
            dict["dueDate"] = Timestamp(date: due)
        } else if !forCreate {
            dict["dueDate"] = FieldValue.delete()
        }

        if let note = g.note, !note.isEmpty {
            dict["note"] = note
        } else if !forCreate {
            dict["note"] = FieldValue.delete()
        }

        if let completed = g.completedAt {
            dict["completedAt"] = Timestamp(date: completed)
        } else if !forCreate {
            dict["completedAt"] = FieldValue.delete()
        }

        return dict
    }

    private static func decode(_ doc: QueryDocumentSnapshot) -> TogetherGoal? {
        let data = doc.data()
        guard
            let id           = data["id"] as? String,
            let title        = data["title"] as? String,
            let categoryRaw  = data["category"] as? String,
            let category     = GoalCategory(rawValue: categoryRaw),
            let colorwayRaw  = data["colorway"] as? String,
            let colorway     = TogetherColorway(rawValue: colorwayRaw),
            let trackingRaw  = data["trackingMode"] as? String,
            let tracking     = GoalTrackingMode(rawValue: trackingRaw),
            let target       = data["target"] as? Double,
            let createdBy    = data["createdBy"] as? String,
            let createdAt    = (data["createdAt"] as? Timestamp)?.dateValue()
        else { return nil }

        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? createdAt
        let amounts = (data["contributionAmounts"] as? [String: Double]) ?? [:]
        let note = (data["note"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let dueDate = (data["dueDate"] as? Timestamp)?.dateValue()
        let completedAt = (data["completedAt"] as? Timestamp)?.dateValue()

        var goal = TogetherGoal(
            id: id,
            title: title,
            category: category,
            colorway: colorway,
            trackingMode: tracking,
            target: target,
            contribution: TogetherContribution(amounts: amounts),
            dueDate: dueDate,
            note: note,
            createdBy: createdBy,
            createdAt: createdAt,
            updatedAt: updatedAt,
            completedAt: completedAt
        )
        goal.firestoreId = doc.documentID
        return goal
    }
}

// MARK: - Mock

final class MockTogetherGoalsService: TogetherGoalsService {
    func create(coupleId: String, goal: TogetherGoal) async throws {}
    func update(coupleId: String, goal: TogetherGoal) async throws {}
    func delete(coupleId: String, id: String) async throws {}
    func recordContribution(coupleId: String, goalId: String, userId: String, delta: Double) async throws {}
    func markComplete(coupleId: String, goalId: String) async throws {}
    func observe(
        coupleId: String,
        onUpdate: @escaping ([TogetherGoal]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        onUpdate(SampleTogetherData.goals)
        return MockListenerRegistration {}
    }
}
