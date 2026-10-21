//
//  PremiumStore.swift
//  Coupley
//
//  Observable wrapper around PremiumService + StoreKit 2.
//
//  Since 1.1 every feature is free. This store now:
//    • sells the one-time "Remove Ads" (shared with the partner when paired),
//    • decides `isAdFree` (Remove Ads, an active legacy subscription, or any
//      past purchase — former subscribers stay ad-free forever),
//    • tracks the daily fair-use limits of the AI features.
//
//  Inject into the environment from CoupleyApp; call `bind(session:)` from
//  RootView whenever the session changes.
//

import Foundation
import FirebaseFirestore
import Combine
import StoreKit
import UIKit

// Resolve StoreKit.SKTransaction vs FirebaseFirestore.SKTransaction ambiguity
private typealias SKTransaction = StoreKit.Transaction

@MainActor
final class PremiumStore: ObservableObject {

    // MARK: - Published

    @Published private(set) var entitlement: PremiumEntitlement = .inactive {
        didSet { refreshAdFree() }
    }
    /// Drives AdsManager: no ads while true.
    @Published private(set) var isAdFree: Bool = false
    @Published private(set) var isPurchasing: Bool = false
    @Published private(set) var removeAdsProduct: Product?
    @Published var lastError: String?

    // MARK: - Dependencies

    private let service: PremiumService
    private var listener: ListenerRegistration?
    private var boundUserId: String?
    private var boundCoupleId: String?
    private var transactionListenerTask: Task<Void, Never>?

    private let defaults = UserDefaults.standard

    private enum Keys {
        /// Set once this device saw any Coupley purchase (Remove Ads or a
        /// legacy subscription) — ad-free forever, even signed out.
        static let everPurchased = "coupley_everPurchased"
    }

    private var everPurchased: Bool {
        get { defaults.bool(forKey: Keys.everPurchased) }
        set {
            defaults.set(newValue, forKey: Keys.everPurchased)
            refreshAdFree()
        }
    }

    // MARK: - Init

    init(service: PremiumService? = nil) {
        self.service = service ?? FirestorePremiumService()
        refreshAdFree()
        transactionListenerTask = Task { await listenForSKTransactions() }
        Task {
            await loadProducts()
            await scanPurchaseHistory()
        }
    }

    deinit {
        listener?.remove()
        transactionListenerTask?.cancel()
    }

    // MARK: - Product Loading

    func loadProducts() async {
        do {
            removeAdsProduct = try await Product.products(for: [PremiumPlan.removeAds.productID]).first
        } catch {
            print("[PremiumStore] Failed to load products: \(error)")
        }
    }

    /// Any verified transaction for a Coupley product (including expired
    /// subscriptions) means this Apple ID paid at some point → ad-free.
    private func scanPurchaseHistory() async {
        let ids = Set(PremiumPlan.allCases.map(\.productID))
        for await result in SKTransaction.all {
            if case .verified(let tx) = result, ids.contains(tx.productID), tx.revocationDate == nil {
                everPurchased = true
                return
            }
        }
    }

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

        Task {
            if await service.hasEverPurchased(userId: userId) {
                everPurchased = true
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

    // MARK: - State

    var source: PremiumSource { entitlement.source }

    private func refreshAdFree() {
        let adFree = entitlement.isActive || everPurchased
        if adFree != isAdFree { isAdFree = adFree }
    }

    /// The user (not the partner) still pays for a legacy subscription.
    /// Shown a "Coupley is free now — you can cancel" notice in Settings.
    var hasActiveSubscription: Bool {
        entitlement.isActive
            && entitlement.source == .selfPaid
            && (entitlement.plan?.isSubscription ?? false)
    }

    /// Legacy subscribers (self or via partner) keep their higher AI limits.
    private var isLegacySubscriber: Bool {
        entitlement.isActive && (entitlement.plan?.isSubscription ?? false)
    }

    // MARK: - Fair-use limits

    /// Every feature is free; only the daily fair-use limits can say no.
    func hasAccess(to feature: PremiumFeature) -> Bool {
        guard let limit = dailyLimit(for: feature) else { return true }
        return dailyUsage(for: feature) < limit
    }

    func dailyLimit(for feature: PremiumFeature) -> Int? {
        isLegacySubscriber ? feature.subscriberDailyLimit : feature.dailyLimit
    }

    func dailyUsage(for feature: PremiumFeature) -> Int {
        let today = Calendar.current.startOfDay(for: Date())
        if let storedDate = defaults.object(forKey: dailyDateKey(for: feature)) as? Date,
           Calendar.current.isDate(storedDate, inSameDayAs: today) {
            return defaults.integer(forKey: dailyCountKey(for: feature))
        }
        return 0
    }

    func recordUsage(for feature: PremiumFeature) {
        guard feature.dailyLimit != nil else { return }
        let today = Calendar.current.startOfDay(for: Date())
        let currentCount: Int
        if let storedDate = defaults.object(forKey: dailyDateKey(for: feature)) as? Date,
           Calendar.current.isDate(storedDate, inSameDayAs: today) {
            currentCount = defaults.integer(forKey: dailyCountKey(for: feature))
        } else {
            currentCount = 0
            defaults.set(today, forKey: dailyDateKey(for: feature))
        }
        defaults.set(currentCount + 1, forKey: dailyCountKey(for: feature))
    }

    func remainingUsage(for feature: PremiumFeature) -> Int {
        guard let limit = dailyLimit(for: feature) else { return Int.max }
        return max(0, limit - dailyUsage(for: feature))
    }

    private func dailyDateKey(for feature: PremiumFeature) -> String {
        "coupley_daily_date_\(feature.rawValue)"
    }
    private func dailyCountKey(for feature: PremiumFeature) -> String {
        "coupley_daily_count_\(feature.rawValue)"
    }

    // MARK: - Remove Ads (StoreKit 2)

    var removeAdsDisplayPrice: String {
        removeAdsProduct?.displayPrice ?? PremiumPlan.removeAdsFallbackPrice
    }

    func purchaseRemoveAds() async {
        if removeAdsProduct == nil { await loadProducts() }
        guard let product = removeAdsProduct else {
            lastError = "Product not available. Check your connection and try again."
            return
        }

        isPurchasing = true
        lastError = nil

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await fulfill(plan: .removeAds, transaction: transaction)
                await transaction.finish()
            case .pending:
                break  // Awaiting approval (e.g. Ask to Buy)
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            lastError = error.localizedDescription
        }

        isPurchasing = false
    }

    func restorePurchases() async {
        isPurchasing = true
        do {
            try await AppStore.sync()
            for await result in SKTransaction.currentEntitlements {
                if case .verified(let tx) = result,
                   let plan = PremiumPlan.allCases.first(where: { $0.productID == tx.productID }) {
                    await fulfill(plan: plan, transaction: tx)
                    await tx.finish()
                }
            }
            await scanPurchaseHistory()
            if !isAdFree {
                lastError = "No previous purchase was found for this Apple ID."
            }
        } catch {
            lastError = error.localizedDescription
        }
        isPurchasing = false
    }

    // MARK: - Private

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error): throw error
        case .verified(let value): return value
        }
    }

    private func fulfill(plan: PremiumPlan, transaction: SKTransaction) async {
        everPurchased = true
        guard let userId = boundUserId else { return }

        // Remove Ads never expires; legacy subscriptions carry their period end.
        let expires: Date? = plan.isSubscription ? transaction.expirationDate : nil
        do {
            try await service.recordPurchase(
                userId: userId,
                coupleId: boundCoupleId,
                plan: plan,
                expiresAt: expires
            )
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func listenForSKTransactions() async {
        for await result in SKTransaction.updates {
            if case .verified(let tx) = result,
               let plan = PremiumPlan.allCases.first(where: { $0.productID == tx.productID }) {
                // A Remove Ads buyer must not be downgraded by a late renewal
                // of an old subscription.
                if plan.isSubscription, entitlement.isActive, entitlement.plan == .removeAds {
                    await tx.finish()
                    continue
                }
                await fulfill(plan: plan, transaction: tx)
                await tx.finish()
            }
        }
    }

    // MARK: - Manage Subscription
    //
    // Legacy subscribers can cancel from Settings. Opens the StoreKit 2 sheet,
    // or the App Store deep link if that fails (e.g. simulator).
    @MainActor
    func openManageSubscriptions() async {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first

        if let scene {
            do {
                try await AppStore.showManageSubscriptions(in: scene)
                return
            } catch {
                // Fall through to deep link.
            }
        }

        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
            await UIApplication.shared.open(url)
        }
    }
}
