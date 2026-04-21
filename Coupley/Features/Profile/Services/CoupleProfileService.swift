//
//  CoupleProfileService.swift
//  Coupley
//

import Foundation
import FirebaseFirestore

// MARK: - Profile

struct CouplePersonProfile: Equatable {
    var displayName: String
    var avatar: AvatarOption

    static let placeholderSelf = CouplePersonProfile(
        displayName: "You",
        avatar: .placeholderSelf
    )
    static let placeholderPartner = CouplePersonProfile(
        displayName: "Partner",
        avatar: .placeholderPartner
    )
}

// MARK: - Service

protocol CoupleProfileService {
    func loadProfile(userId: String) async throws -> CouplePersonProfile?
    func saveAvatar(userId: String, avatar: AvatarOption) async throws
    func observeProfile(
        userId: String,
        onUpdate: @escaping (CouplePersonProfile?) -> Void
    ) -> ListenerRegistration
}

// MARK: - Firestore Implementation

final class FirestoreCoupleProfileService: CoupleProfileService {

    private let db = Firestore.firestore()

    func loadProfile(userId: String) async throws -> CouplePersonProfile? {
        let snap = try await db.collection(FirestorePath.users).document(userId).getDocument()
        guard let data = snap.data() else { return nil }
        return Self.profile(from: data)
    }

    func saveAvatar(userId: String, avatar: AvatarOption) async throws {
        var payload: [String: Any] = ["avatarId": avatar.firestoreId]
        if case .custom(let b64) = avatar {
            payload["avatarPhoto"] = b64
        } else {
            payload["avatarPhoto"] = FieldValue.delete()
        }
        try await db.collection(FirestorePath.users)
            .document(userId)
            .setData(payload, merge: true)
    }

    func observeProfile(
        userId: String,
        onUpdate: @escaping (CouplePersonProfile?) -> Void
    ) -> ListenerRegistration {
        db.collection(FirestorePath.users)
            .document(userId)
            .addSnapshotListener { snap, _ in
                guard let data = snap?.data() else {
                    onUpdate(nil)
                    return
                }
                onUpdate(Self.profile(from: data))
            }
    }

    // MARK: - Mapping

    private static func profile(from data: [String: Any]) -> CouplePersonProfile {
        let name = (data["displayName"] as? String) ?? "Partner"
        let avatarId = (data["avatarId"] as? String) ?? ""
        let custom = data["avatarPhoto"] as? String
        let avatar = AvatarOption(firestoreId: avatarId, customBase64: custom)
            ?? .placeholderPartner
        return CouplePersonProfile(displayName: name, avatar: avatar)
    }
}
