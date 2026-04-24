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
        // Solo: the user doc is the only source.
        guard let coupleId, !coupleId.isEmpty else {
            return db.collection(FirestorePath.users).document(userId)
                .addSnapshotListener { snapshot, _ in
                    let entitlement = Self.parseEntitlement(
                        data: snapshot?.data()?["premium"] as? [String: Any],
                        selfUserId: userId
                    )
                    onUpdate(entitlement)
                }
        }

        // Paired: observe both docs. The couple doc is the canonical shared
        // source, but we also watch the user doc so a purchaser who paid
        // while solo and then paired doesn't lose premium during the window
        // before the cloud function migrates their entitlement. Effective
        // entitlement = whichever side is active, with couple preferred.
        let merger = PairedEntitlementMerger(userId: userId, onUpdate: onUpdate)

        let coupleReg = db.collection(FirestorePath.couples).document(coupleId)
            .addSnapshotListener { snapshot, _ in
                merger.handleCouple(snapshot?.data()?["premium"] as? [String: Any])
            }
        let userReg = db.collection(FirestorePath.users).document(userId)
            .addSnapshotListener { snapshot, _ in
                merger.handleUser(snapshot?.data()?["premium"] as? [String: Any])
            }

        return MockListenerRegistration {
            coupleReg.remove()
            userReg.remove()
        }
    }

    // MARK: - Parsing

    fileprivate static func parseEntitlement(
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

// MARK: - Paired Entitlement Merger

/// Combines snapshots of the couple doc and the user doc into a single
/// effective `PremiumEntitlement`. Two reasons we need this:
///   1. If the user paid while solo and then paired, the couple doc may
///      briefly lack a `premium` field — we fall back to the user doc so
///      the paying user keeps their entitlement.
///   2. If either doc reports active, the effective entitlement is active;
///      couple wins tie-breaks so `source` is attributed correctly for
///      the non-purchasing partner.
private final class PairedEntitlementMerger {
    private let userId: String
    private let onUpdate: (PremiumEntitlement) -> Void
    private let queue = DispatchQueue(label: "com.coupley.premium.merger")
    private var coupleEnt: PremiumEntitlement = .inactive
    private var userEnt: PremiumEntitlement = .inactive

    init(userId: String, onUpdate: @escaping (PremiumEntitlement) -> Void) {
        self.userId = userId
        self.onUpdate = onUpdate
    }

    func handleCouple(_ data: [String: Any]?) {
        queue.async {
            self.coupleEnt = FirestorePremiumService.parseEntitlement(data: data, selfUserId: self.userId)
            self.emit()
        }
    }

    func handleUser(_ data: [String: Any]?) {
        queue.async {
            self.userEnt = FirestorePremiumService.parseEntitlement(data: data, selfUserId: self.userId)
            self.emit()
        }
    }

    private func emit() {
        if coupleEnt.isActive {
            onUpdate(coupleEnt)
        } else if userEnt.isActive {
            onUpdate(userEnt)
        } else {
            onUpdate(.inactive)
        }
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
