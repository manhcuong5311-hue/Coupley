//
//  NudgeService.swift
//  Coupley
//
//  Writes reaction and "Thinking of You" events to couples/{coupleId}/nudges
//  so both partners can see them in real time. Each nudge document lives at
//  couples/{coupleId}/nudges/{auto-id} and is deleted after 24 h by a Cloud Function.
//

import Foundation
import FirebaseFirestore

// MARK: - Nudge Kind

enum NudgeKind: String, Codable {
    case ping         // "Thinking of You"
    case reaction     // Love / Hug / Call me / Coffee
}

// MARK: - Nudge Model

struct Nudge: Identifiable, Codable {
    @DocumentID var firestoreId: String?
    let fromUserId: String
    let toUserId: String
    let kind: NudgeKind
    let reactionKind: String?   // only set when kind == .reaction
    let createdAt: Date

    var id: String { firestoreId ?? UUID().uuidString }

    var displayEmoji: String {
        if kind == .ping { return "💭" }
        guard let raw = reactionKind, let rk = ReactionKind(rawValue: raw) else { return "❤️" }
        return rk.emoji
    }

    var displayLabel: String {
        if kind == .ping { return "is thinking of you" }
        guard let raw = reactionKind, let rk = ReactionKind(rawValue: raw) else { return "sent a reaction" }
        switch rk {
        case .heart:  return "sent you love"
        case .hug:    return "sent you a hug"
        case .callMe: return "wants to call you"
        case .coffee: return "wants coffee with you"
        }
    }
}

// MARK: - Nudge Service Protocol

protocol NudgeServicing {
    func send(
        coupleId: String,
        fromUserId: String,
        toUserId: String,
        kind: NudgeKind,
        reactionKind: ReactionKind?
    ) async throws

    func listenForIncoming(
        coupleId: String,
        toUserId: String,
        onUpdate: @escaping ([Nudge]) -> Void
    ) -> ListenerRegistration
}

// MARK: - Firestore Nudge Service

final class FirestoreNudgeService: NudgeServicing {

    private let db = Firestore.firestore()

    func send(
        coupleId: String,
        fromUserId: String,
        toUserId: String,
        kind: NudgeKind,
        reactionKind: ReactionKind?
    ) async throws {
        guard !coupleId.isEmpty, !fromUserId.isEmpty, !toUserId.isEmpty else { return }
        var data: [String: Any] = [
            "fromUserId":   fromUserId,
            "toUserId":     toUserId,
            "kind":         kind.rawValue,
            "createdAt":    FieldValue.serverTimestamp()
        ]
        if let rk = reactionKind {
            data["reactionKind"] = rk.rawValue
        }
        try await db.collection("couples/\(coupleId)/nudges").addDocument(data: data)
    }

    func listenForIncoming(
        coupleId: String,
        toUserId: String,
        onUpdate: @escaping ([Nudge]) -> Void
    ) -> ListenerRegistration {
        let since = Date().addingTimeInterval(-300) // only show nudges from last 5 min
        return db.collection("couples/\(coupleId)/nudges")
            .whereField("toUserId", isEqualTo: toUserId)
            .whereField("createdAt", isGreaterThan: Timestamp(date: since))
            .order(by: "createdAt", descending: true)
            .limit(to: 10)
            .addSnapshotListener { snapshot, _ in
                let nudges = snapshot?.documents.compactMap { doc in
                    try? doc.data(as: Nudge.self)
                } ?? []
                onUpdate(nudges)
            }
    }
}
