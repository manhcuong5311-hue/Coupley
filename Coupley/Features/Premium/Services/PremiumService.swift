//
//  PremiumService.swift
//  Coupley
//
//  Ownership-based premium entitlement.
//
//  Firestore contract:
//    /users/{uid}.premium = {                      // the user's OWN subscription
//      active: Bool,
//      plan: "monthly" | "yearly",
//      purchaserId: String,                         // MUST == uid when valid
//      purchasedAt: Timestamp,
//      expiresAt: Timestamp
//    }
//    /couples/{coupleId}.premium = {                // shared access slot —
//      active: Bool,                                 // mirror of whichever
//      plan: "monthly" | "yearly",                   // partner is paid
//      purchaserId: String,                          // the paying partner's uid
//      purchasedAt: Timestamp,
//      expiresAt: Timestamp
//    }
//
//  Ownership rule:
//    Only the `purchaserId` keeps premium after disconnect. The couple doc is
//    wiped as part of the disconnect batch; the purchaser's user doc is
//    never touched by the disconnect flow. A non-paying partner therefore
//    drops to free immediately because (a) they have no valid entry on their
//    own user doc (client-side parse ignores foreign purchaserIds) and (b)
//    the couple doc is no longer active for them to read.
//
//  Parser invariants:
//    • `/users/{uid}.premium` is only honored when `purchaserId == uid`.
//      Any other state is treated as invalid/free — defensive guard against
//      stale writes, rule-violations, or corrupted migrations.
//    • `/couples/{cid}.premium` is honored for either partner's purchaserId,
//      since both partners legitimately share that slot.
//

import Foundation
import FirebaseFirestore

// MARK: - Premium Service Protocol

protocol PremiumService {
    /// Write a purchase server-side after a successful StoreKit transaction.
    /// Writes to `/users/{userId}.premium` with `purchaserId = userId` and,
    /// if paired, mirrors the same payload onto `/couples/{coupleId}.premium`
    /// so the partner inherits shared access.
    func recordPurchase(
        userId: String,
        coupleId: String?,
        plan: PremiumPlan,
        expiresAt: Date
    ) async throws

    /// Clear this user's *own* entitlement (cancellation / refund / testing).
    /// Never touches the partner's user doc. Also clears the couple slot when
    /// paired so the partner doesn't continue reading a stale shared entry.
    func clearEntitlement(userId: String, coupleId: String?) async throws

    /// Clear ONLY the shared couple slot (used by the disconnect flow so the
    /// non-paying partner loses access immediately). Intentionally does not
    /// touch either user's own `/users/{uid}.premium` — the purchaser's real
    /// subscription must survive a disconnect.
    func clearCouplePremium(coupleId: String) async throws

    /// Live-observe the effective entitlement for a user + their couple.
    /// If paired, watches both docs and merges with self-paid winning.
    func observeEntitlement(
        userId: String,
        coupleId: String?,
        onUpdate: @escaping (PremiumEntitlement) -> Void
    ) -> ListenerRegistration
}

// MARK: - Firestore Premium Service

final class FirestorePremiumService: PremiumService {

    private let db = Firestore.firestore()

    // MARK: - Record Purchase

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

        // Write the user's OWN subscription on their user doc. purchaserId
        // always == userId here, which is the only legitimate shape for
        // /users/{uid}.premium under the ownership model.
        try await db.collection(FirestorePath.users).document(userId).setData([
            "premium": payload
        ], merge: true)

        // If paired, mirror into the couple slot in a transaction so we only
        // overwrite when it's safe:
        //   • no existing slot, or it's inactive / expired   → take it
        //   • existing slot is ours (same purchaserId)       → refresh it
        //   • existing slot belongs to the partner AND is
        //     still active with a later expiry               → leave it
        //     (both users are self-paid; couple slot is
        //     irrelevant for us, both read selfPaid from
        //     their own user docs)
        guard let coupleId, !coupleId.isEmpty else { return }

        let coupleRef = db.collection(FirestorePath.couples).document(coupleId)
        _ = try await db.runTransaction({ txn, errorPointer in
            let snap: DocumentSnapshot
            do {
                snap = try txn.getDocument(coupleRef)
            } catch let err as NSError {
                errorPointer?.pointee = err
                return nil
            }

            let existing = snap.data()?["premium"] as? [String: Any]
            let existingActive = (existing?["active"] as? Bool) ?? false
            let existingPurchaser = existing?["purchaserId"] as? String
            let existingExpiry = (existing?["expiresAt"] as? Timestamp)?.dateValue()
            let existingStillValid = existingActive
                && (existingExpiry.map { $0 > Date() } ?? true)

            let shouldOverwrite: Bool
            if !existingStillValid {
                shouldOverwrite = true
            } else if existingPurchaser == userId {
                shouldOverwrite = true
            } else {
                // Couple slot is held by the partner. Refuse to overwrite —
                // their valid subscription must not get steamrolled.
                shouldOverwrite = false
            }

            if shouldOverwrite {
                txn.setData(["premium": payload], forDocument: coupleRef, merge: true)
            }
            return nil
        })
    }

    // MARK: - Clear (self)

    func clearEntitlement(userId: String, coupleId: String?) async throws {
        // Clear the caller's own subscription. Never touches the partner's
        // user doc — they own their subscription independently.
        try await db.collection(FirestorePath.users).document(userId).setData([
            "premium": ["active": false]
        ], merge: true)

        // Clear the couple slot IFF we're the current occupant. Otherwise
        // the partner's paid entitlement still lives there and we shouldn't
        // touch it.
        if let coupleId, !coupleId.isEmpty {
            let coupleRef = db.collection(FirestorePath.couples).document(coupleId)
            _ = try await db.runTransaction({ txn, errorPointer in
                let snap: DocumentSnapshot
                do {
                    snap = try txn.getDocument(coupleRef)
                } catch let err as NSError {
                    errorPointer?.pointee = err
                    return nil
                }
                let existing = snap.data()?["premium"] as? [String: Any]
                let existingPurchaser = existing?["purchaserId"] as? String
                if existingPurchaser == userId {
                    txn.setData(
                        ["premium": ["active": false]],
                        forDocument: coupleRef,
                        merge: true
                    )
                }
                return nil
            })
        }
    }

    // MARK: - Clear (couple slot only)

    func clearCouplePremium(coupleId: String) async throws {
        guard !coupleId.isEmpty else { return }
        try await db.collection(FirestorePath.couples).document(coupleId).setData([
            "premium": ["active": false]
        ], merge: true)
    }

    // MARK: - Observe

    func observeEntitlement(
        userId: String,
        coupleId: String?,
        onUpdate: @escaping (PremiumEntitlement) -> Void
    ) -> ListenerRegistration {
        // Solo: only the user doc matters. (If their user doc somehow has
        // a foreign purchaserId, the parser treats it as inactive.)
        guard let coupleId, !coupleId.isEmpty else {
            return db.collection(FirestorePath.users).document(userId)
                .addSnapshotListener { snapshot, _ in
                    let entitlement = Self.parseUserEntitlement(
                        data: snapshot?.data()?["premium"] as? [String: Any],
                        selfUserId: userId
                    )
                    onUpdate(entitlement)
                }
        }

        // Paired: watch both docs. Self-paid always wins over partner-shared
        // so a real purchaser keeps `.selfPaid` even if the couple slot is
        // held by the other partner. See `PairedEntitlementMerger.emit`.
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

    /// Parses `/users/{selfUserId}.premium`. Entries that don't own themselves
    /// (`purchaserId != selfUserId`) are rejected as invalid — belt-and-
    /// suspenders defense so that a compromised write, a stale migration, or
    /// a future schema change can never grant premium from a foreign
    /// purchase slot.
    fileprivate static func parseUserEntitlement(
        data: [String: Any]?,
        selfUserId: String
    ) -> PremiumEntitlement {
        guard let data, let active = data["active"] as? Bool, active else {
            return .inactive
        }
        let purchaser = data["purchaserId"] as? String
        guard purchaser == selfUserId else { return .inactive }

        return PremiumEntitlement(
            active: true,
            plan: (data["plan"] as? String).flatMap { PremiumPlan(rawValue: $0) },
            source: .selfPaid,
            expiresAt: (data["expiresAt"] as? Timestamp)?.dateValue()
        )
    }

    /// Parses `/couples/{coupleId}.premium`. Either partner's `purchaserId`
    /// is valid here — that's the point of the shared slot. Source is
    /// attributed against `selfUserId` so the caller sees `.selfPaid` when
    /// they're the payer and `.partnerShared` when their partner is.
    fileprivate static func parseCoupleEntitlement(
        data: [String: Any]?,
        selfUserId: String
    ) -> PremiumEntitlement {
        guard let data, let active = data["active"] as? Bool, active else {
            return .inactive
        }
        let purchaser = data["purchaserId"] as? String
        let source: PremiumSource
        if purchaser == selfUserId {
            source = .selfPaid
        } else if let purchaser, !purchaser.isEmpty {
            source = .partnerShared
        } else {
            // Active flag without a purchaserId = malformed. Treat as invalid
            // so a broken seed can't grant shared access forever.
            return .inactive
        }

        return PremiumEntitlement(
            active: true,
            plan: (data["plan"] as? String).flatMap { PremiumPlan(rawValue: $0) },
            source: source,
            expiresAt: (data["expiresAt"] as? Timestamp)?.dateValue()
        )
    }
}

// MARK: - Paired Entitlement Merger

/// Combines snapshots of the couple doc and the user doc into a single
/// effective `PremiumEntitlement`.
///
/// Merge policy (self-paid wins):
///   1. If the user's own doc reports `.selfPaid`, emit that. A real
///      purchaser must keep `.selfPaid` attribution even when the couple
///      slot is held by the partner (case: both partners purchased
///      independently), so their subscription survives disconnect.
///   2. Otherwise, if the couple doc is active, emit the couple entitlement
///      (which will be `.partnerShared` for the non-paying partner).
///   3. Else inactive.
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
            self.coupleEnt = FirestorePremiumService.parseCoupleEntitlement(
                data: data,
                selfUserId: self.userId
            )
            self.emit()
        }
    }

    func handleUser(_ data: [String: Any]?) {
        queue.async {
            self.userEnt = FirestorePremiumService.parseUserEntitlement(
                data: data,
                selfUserId: self.userId
            )
            self.emit()
        }
    }

    private func emit() {
        if userEnt.isActive && userEnt.source == .selfPaid {
            onUpdate(userEnt)
        } else if coupleEnt.isActive {
            onUpdate(coupleEnt)
        } else {
            onUpdate(.inactive)
        }
    }
}

// MARK: - Mock

final class MockPremiumService: PremiumService {
    func recordPurchase(userId: String, coupleId: String?, plan: PremiumPlan, expiresAt: Date) async throws {}
    func clearEntitlement(userId: String, coupleId: String?) async throws {}
    func clearCouplePremium(coupleId: String) async throws {}
    func observeEntitlement(
        userId: String,
        coupleId: String?,
        onUpdate: @escaping (PremiumEntitlement) -> Void
    ) -> ListenerRegistration {
        onUpdate(.inactive)
        return MockListenerRegistration {}
    }
}
