//
//  PartnerProfileDetailService.swift
//  Coupley
//
//  Reads / writes PartnerProfileDetail on the user document. Includes a
//  simple in-memory cache for offline-warmth and last-write-wins conflict
//  resolution via profileUpdatedAt.
//

import Foundation
import FirebaseFirestore

// MARK: - Service Protocol

protocol PartnerProfileDetailService {
    func fetchProfile(userId: String) async throws -> PartnerProfileDetail
    func updateProfile(_ profile: PartnerProfileDetail) async throws
    func observeProfile(
        userId: String,
        onUpdate: @escaping (PartnerProfileDetail) -> Void
    ) -> ListenerRegistration
}

// MARK: - Firestore Implementation

final class FirestorePartnerProfileDetailService: PartnerProfileDetailService {

    private let db = Firestore.firestore()

    // Tiny in-memory cache keyed by userId — survives tab switches but not
    // process restarts. Good enough to avoid a flash of empty-state.
    nonisolated(unsafe) private static var cache: [String: PartnerProfileDetail] = [:]
    private static let cacheQueue = DispatchQueue(label: "PartnerProfileDetailService.cache")

    static func cached(userId: String) -> PartnerProfileDetail? {
        cacheQueue.sync { cache[userId] }
    }

    private static func setCache(_ profile: PartnerProfileDetail) {
        cacheQueue.sync { cache[profile.userId] = profile }
    }

    // MARK: - Fetch

    func fetchProfile(userId: String) async throws -> PartnerProfileDetail {
        let snap = try await db.collection(FirestorePath.users).document(userId).getDocument()
        let profile = PartnerProfileDetail(userId: userId, data: snap.data() ?? [:])
        Self.setCache(profile)
        return profile
    }

    // MARK: - Update

    func updateProfile(_ profile: PartnerProfileDetail) async throws {
        // Last-write-wins: the server timestamp replaces any older value.
        try await db.collection(FirestorePath.users)
            .document(profile.userId)
            .setData(profile.firestorePayload(), merge: true)
        Self.setCache(profile)
    }

    // MARK: - Observe

    func observeProfile(
        userId: String,
        onUpdate: @escaping (PartnerProfileDetail) -> Void
    ) -> ListenerRegistration {
        db.collection(FirestorePath.users)
            .document(userId)
            .addSnapshotListener { snap, _ in
                let data = snap?.data() ?? [:]
                let profile = PartnerProfileDetail(userId: userId, data: data)
                Self.setCache(profile)
                onUpdate(profile)
            }
    }
}
