//
//  ReactionService.swift
//  Coupley
//
//  Lets a partner react to a mood (❤️ hug / call me). Stored at
//  couples/{coupleId}/moods/{moodId}/reactions/{reactionId}. The Cloud Function
//  `onReactionCreated` picks it up and pushes an FCM notification to the mood author.
//

import Foundation
import FirebaseFirestore

// MARK: - Reaction Kind

enum ReactionKind: String, CaseIterable, Identifiable, Codable {
    case heart
    case hug
    case callMe = "callMe"
    case coffee

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .heart:  return "❤️"
        case .hug:    return "🫂"
        case .callMe: return "📞"
        case .coffee: return "☕"
        }
    }

    /// Caption under the emoji on the Home mood card's reaction buttons.
    /// Display only: Firestore and the push function use `rawValue`.
    var label: LocalizedStringResource {
        switch self {
        case .heart:
            return LocalizedStringResource("Love", comment: "Reaction button caption (noun): send your partner love")
        case .hug:
            return LocalizedStringResource("Hug", comment: "Reaction button caption (noun): send your partner a hug")
        case .callMe:
            return LocalizedStringResource("Call me", comment: "Reaction button caption: ask your partner to call you")
        case .coffee:
            return LocalizedStringResource("Coffee", comment: "Reaction button caption: invite your partner for coffee")
        }
    }
}

// MARK: - Reaction Record

struct MoodReaction: Identifiable, Codable, Equatable {
    @DocumentID var firestoreId: String?
    let userId: String
    let kind: String
    let createdAt: Date

    var id: String { firestoreId ?? UUID().uuidString }
    var kindValue: ReactionKind { ReactionKind(rawValue: kind) ?? .heart }
}

// MARK: - Reaction Service Protocol

protocol ReactionService {
    func sendReaction(
        coupleId: String,
        moodId: String,
        userId: String,
        kind: ReactionKind
    ) async throws

    func listenToReactions(
        coupleId: String,
        moodId: String,
        onUpdate: @escaping ([MoodReaction]) -> Void
    ) -> ListenerRegistration
}

// MARK: - Firestore Reaction Service

final class FirestoreReactionService: ReactionService {

    private let db = Firestore.firestore()

    func sendReaction(
        coupleId: String,
        moodId: String,
        userId: String,
        kind: ReactionKind
    ) async throws {
        guard !coupleId.isEmpty, !moodId.isEmpty, !userId.isEmpty else { return }

        let path = "couples/\(coupleId)/moods/\(moodId)/reactions"
        try await db.collection(path).addDocument(data: [
            "userId": userId,
            "kind": kind.rawValue,
            "createdAt": FieldValue.serverTimestamp()
        ])
    }

    func listenToReactions(
        coupleId: String,
        moodId: String,
        onUpdate: @escaping ([MoodReaction]) -> Void
    ) -> ListenerRegistration {
        let path = "couples/\(coupleId)/moods/\(moodId)/reactions"
        return db.collection(path)
            .order(by: "createdAt", descending: true)
            .limit(to: 20)
            .addSnapshotListener { snapshot, _ in
                let reactions = snapshot?.documents.compactMap { doc in
                    try? doc.data(as: MoodReaction.self)
                } ?? []
                onUpdate(reactions)
            }
    }
}

// MARK: - Mock

final class MockReactionService: ReactionService {
    func sendReaction(coupleId: String, moodId: String, userId: String, kind: ReactionKind) async throws {}
    func listenToReactions(coupleId: String, moodId: String, onUpdate: @escaping ([MoodReaction]) -> Void) -> ListenerRegistration {
        onUpdate([])
        return MockListenerRegistration {}
    }
}
