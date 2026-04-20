//
//  PremiumStore.swift
//  Coupley
//
//  Observable wrapper around PremiumService. Keeps a live entitlement for the
//  current session (couple-shared when paired, user-scoped when solo) and
//  drives feature gating via `hasAccess(to:)`.
//
//  Inject into the environment from CoupleyApp; call `bind(session:)` from
//  RootView whenever the session changes.
//

import Foundation
import FirebaseFirestore
import Combine

@MainActor
final class PremiumStore: ObservableObject {

    // MARK: - Published

    @Published private(set) var entitlement: PremiumEntitlement = .inactive
    @Published private(set) var isPurchasing: Bool = false
    @Published var lastError: String?

    // MARK: - Dependencies

    private let service: PremiumService
    private var listener: ListenerRegistration?
    private var boundUserId: String?
    private var boundCoupleId: String?

    // MARK: - Init

    init(service: PremiumService = FirestorePremiumService()) {
        self.service = service
    }

    deinit { listener?.remove() }

    // MARK: - Binding

    /// Attach to the current session. Safe to call repeatedly — no-op if already
    /// bound to the same (user, couple) pair.
    func bind(userId: String?, coupleId: String?) {
        guard userId != boundUserId || coupleId != boundCoupleId else { return }

        listener?.remove()
        listener = nil
        boundUserId = userId
        boundCoupleId = coupleId

        guard let userId, !userId.isEmpty else {
            entitlement = .inactive
            return
        }

        listener = service.observeEntitlement(
            userId: userId,
            coupleId: coupleId
        ) { [weak self] next in
            Task { @MainActor [weak self] in
                self?.entitlement = next
            }
        }
    }

    func unbind() {
        listener?.remove()
        listener = nil
        boundUserId = nil
        boundCoupleId = nil
        entitlement = .inactive
    }

    // MARK: - Gating

    var isActive: Bool { entitlement.isActive }

    var source: PremiumSource { entitlement.source }

    func hasAccess(to feature: PremiumFeature) -> Bool {
        // Every feature currently requires an active entitlement — keep the
        // switch explicit so we can carve out free tiers later without rewriting
        // call sites.
        _ = feature
        return isActive
    }

    // MARK: - Purchase (stubbed — swap for StoreKit 2 when products are wired)

    func purchase(plan: PremiumPlan) async {
        guard let userId = boundUserId else {
            lastError = "Not signed in."
            return
        }

        isPurchasing = true
        lastError = nil

        do {
            // TODO: Replace with StoreKit 2 `Product.purchase()` + transaction verification.
            try await Task.sleep(nanoseconds: 800_000_000)

            let expires: Date = {
                switch plan {
                case .monthly: return Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
                case .yearly:  return Calendar.current.date(byAdding: .year,  value: 1, to: Date()) ?? Date()
                }
            }()

            try await service.recordPurchase(
                userId: userId,
                coupleId: boundCoupleId,
                plan: plan,
                expiresAt: expires
            )
            // Snapshot listener will push the new entitlement back.
        } catch {
            lastError = error.localizedDescription
        }

        isPurchasing = false
    }

    func restorePurchases() async {
        // StoreKit 2 restore is a no-op for most users; leave a hook here so
        // the settings "Restore" button has something to call.
        // When StoreKit is wired, iterate `Transaction.currentEntitlements` and
        // re-post the newest to Firestore via `service.recordPurchase`.
    }

    func cancelForTesting() async {
        guard let userId = boundUserId else { return }
        try? await service.clearEntitlement(userId: userId, coupleId: boundCoupleId)
    }
}
