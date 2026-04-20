//
//  PremiumService.swift
//  Coupley
//
//  Couple-shared premium entitlement.
//
//  Firestore contract:
//    /couples/{coupleId}.premium = {
//      active: Bool,
//      plan: "monthly" | "yearly",
//      purchaserId: String,            // user who paid
//      purchasedAt: Timestamp,
//      expiresAt: Timestamp
//    }
//
//  While paired, both partners read the couple's `premium` field → partner
//  inherits. If a user is solo (no coupleId yet), they read `/users/{uid}.premium`
//  instead. On pairing, the cloud function copies individual entitlement into the
//  couple doc.
//

import Foundation
import FirebaseFirestore

// MARK: - Premium Service Protocol

protocol PremiumService {
    /// Write a purchase server-side after a successful StoreKit transaction.
    func recordPurchase(
        userId: String,
        coupleId: String?,
        plan: PremiumPlan,
        expiresAt: Date
    ) async throws

    /// Clear entitlement (cancellation / refund).
    func clearEntitlement(userId: String, coupleId: String?) async throws

    /// Live-observe the effective entitlement for a user + their couple.
    /// If paired, the couple doc is the source of truth; otherwise the user doc.
    func observeEntitlement(
        userId: String,
        coupleId: String?,
        onUpdate: @escaping (PremiumEntitlement) -> Void
    ) -> ListenerRegistration
}

// MARK: - Firestore Premium Service

final class FirestorePremiumService: PremiumService {

    private let db = Firestore.firestore()

    func recordPurchase(
        userId: String,
        coupleId: String?,
        plan: PremiumPlan,
        expiresAt: Date
    ) async throws {
        let payload: [String: Any] = [
            "active": true,
            "plan": plan.rawValue,
            "purchaserId": userId,
            "purchasedAt": FieldValue.serverTimestamp(),
            "expiresAt": Timestamp(date: expiresAt)
        ]

        // Always record on the user (source of truth for solo users)
        try await db.collection(FirestorePath.users).document(userId).setData([
            "premium": payload
        ], merge: true)

        // If paired, also set on couple so partner inherits immediately.
        if let coupleId, !coupleId.isEmpty {
            try await db.collection(FirestorePath.couples).document(coupleId).setData([
                "premium": payload
            ], merge: true)
        }
    }

    func clearEntitlement(userId: String, coupleId: String?) async throws {
        try await db.collection(FirestorePath.users).document(userId).setData([
            "premium": ["active": false]
        ], merge: true)

        if let coupleId, !coupleId.isEmpty {
            try await db.collection(FirestorePath.couples).document(coupleId).setData([
                "premium": ["active": false]
            ], merge: true)
        }
    }

    func observeEntitlement(
        userId: String,
        coupleId: String?,
        onUpdate: @escaping (PremiumEntitlement) -> Void
    ) -> ListenerRegistration {
        // Prefer couple-level if paired. Cloud function keeps it in sync with user.
        if let coupleId, !coupleId.isEmpty {
            return db.collection(FirestorePath.couples).document(coupleId)
                .addSnapshotListener { snapshot, _ in
                    let entitlement = Self.parseEntitlement(
                        data: snapshot?.data()?["premium"] as? [String: Any],
                        selfUserId: userId
                    )
                    onUpdate(entitlement)
                }
        } else {
            return db.collection(FirestorePath.users).document(userId)
                .addSnapshotListener { snapshot, _ in
                    let entitlement = Self.parseEntitlement(
                        data: snapshot?.data()?["premium"] as? [String: Any],
                        selfUserId: userId
                    )
                    onUpdate(entitlement)
                }
        }
    }

    // MARK: - Parsing

    private static func parseEntitlement(
        data: [String: Any]?,
        selfUserId: String
    ) -> PremiumEntitlement {
        guard let data, let active = data["active"] as? Bool, active else {
            return .inactive
        }

        let plan = (data["plan"] as? String).flatMap { PremiumPlan(rawValue: $0) }
        let purchaser = data["purchaserId"] as? String
        let expiresAt = (data["expiresAt"] as? Timestamp)?.dateValue()

        let source: PremiumSource
        if purchaser == selfUserId {
            source = .self_
        } else if purchaser != nil {
            source = .partner
        } else {
            source = .none
        }

        return PremiumEntitlement(
            active: true,
            plan: plan,
            source: source,
            expiresAt: expiresAt
        )
    }
}

// MARK: - Mock

final class MockPremiumService: PremiumService {
    func recordPurchase(userId: String, coupleId: String?, plan: PremiumPlan, expiresAt: Date) async throws {}
    func clearEntitlement(userId: String, coupleId: String?) async throws {}
    func observeEntitlement(
        userId: String,
        coupleId: String?,
        onUpdate: @escaping (PremiumEntitlement) -> Void
    ) -> ListenerRegistration {
        onUpdate(.inactive)
        return MockListenerRegistration {}
    }
}
