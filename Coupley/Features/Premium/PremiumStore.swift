//
//  PremiumStore.swift
//  Coupley
//
//  Observable wrapper around PremiumService + StoreKit 2. Keeps a live
//  entitlement for the current session (couple-shared when paired, user-scoped
//  when solo) and drives feature gating via `hasAccess(to:)`. Also tracks daily
//  usage for rate-limited free-tier features.
//
//  Inject into the environment from CoupleyApp; call `bind(session:)` from
//  RootView whenever the session changes.
//

import Foundation
import FirebaseFirestore
import Combine
import StoreKit

// Resolve StoreKit.SKTransaction vs FirebaseFirestore.SKTransaction ambiguity
private typealias SKTransaction = StoreKit.Transaction

@MainActor
final class PremiumStore: ObservableObject {

    // MARK: - Published

    @Published private(set) var entitlement: PremiumEntitlement = .inactive
    @Published private(set) var isPurchasing: Bool = false
    @Published private(set) var products: [Product] = []
    @Published var lastError: String?

    // MARK: - Dependencies

    private let service: PremiumService
    private var listener: ListenerRegistration?
    private var boundUserId: String?
    private var boundCoupleId: String?
    private var transactionListenerTask: Task<Void, Never>?

    // MARK: - Daily Usage

    private let defaults = UserDefaults.standard

    // MARK: - Init

    init(service: PremiumService? = nil) {
        self.service = service ?? FirestorePremiumService()
        transactionListenerTask = Task { await listenForSKTransactions() }
        Task { await loadProducts() }
    }

    deinit {
        listener?.remove()
        transactionListenerTask?.cancel()
    }

    // MARK: - Product Loading

    func loadProducts() async {
        let ids = PremiumPlan.allCases.map { $0.productID }
        do {
            let loaded = try await Product.products(for: ids)
            products = loaded.sorted { $0.price < $1.price }
        } catch {
            print("[PremiumStore] Failed to load products: \(error)")
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
        switch feature {
        case .customAvatar, .anniversaryPhoto, .allThemes, .fullQuizAccess, .customQuizzes:
            return isActive
        case .memoryCapsule:
            // Free: locked. Capsules are an emotional premium hook.
            return isActive
        case .dateIdeas:
            // Free: totally locked
            return isActive
        case .aiMoodSuggestions:
            if isActive { return true }
            // Free: 1 use per day
            return dailyUsage(for: .aiMoodSuggestions) < 1
        case .aiCoach:
            if isActive { return true }
            // Free: 1 coaching session per day (opens the coach, deep features still premium)
            return dailyUsage(for: .aiCoach) < 1
        case .chatPhotos:
            if isActive { return true }
            // Free: 1 photo per day
            return dailyUsage(for: .chatPhotos) < 1
        case .togetherGoalsUnlimited,
             .togetherChallengesUnlimited,
             .togetherDreamBoard,
             .togetherCoach:
            // Together features are binary — quotas are enforced inside the
            // tab's view model rather than as daily-counter rate limits.
            return isActive
        }
    }

    // MARK: - Daily Usage Tracking

    func dailyUsage(for feature: PremiumFeature) -> Int {
        let today = Calendar.current.startOfDay(for: Date())
        if let storedDate = defaults.object(forKey: dailyDateKey(for: feature)) as? Date,
           Calendar.current.isDate(storedDate, inSameDayAs: today) {
            return defaults.integer(forKey: dailyCountKey(for: feature))
        }
        return 0
    }

    func recordUsage(for feature: PremiumFeature) {
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
        let limit: Int
        if isActive {
            limit = feature.premiumDailyLimit ?? Int.max
        } else {
            limit = feature.freeDailyLimit ?? 0
        }
        return max(0, limit - dailyUsage(for: feature))
    }

    private func dailyDateKey(for feature: PremiumFeature) -> String {
        "coupley_daily_date_\(feature.rawValue)"
    }
    private func dailyCountKey(for feature: PremiumFeature) -> String {
        "coupley_daily_count_\(feature.rawValue)"
    }

    // MARK: - Purchase (StoreKit 2)

    func purchase(plan: PremiumPlan) async {
        guard let userId = boundUserId else {
            lastError = "Not signed in."
            return
        }

        guard let product = products.first(where: { $0.id == plan.productID }) else {
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
                await fulfillPurchase(userId: userId, plan: plan, transaction: transaction)
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
        guard let userId = boundUserId else { return }
        isPurchasing = true
        do {
            try await AppStore.sync()
            for await result in SKTransaction.currentEntitlements {
                if case .verified(let tx) = result,
                   let plan = PremiumPlan.allCases.first(where: { $0.productID == tx.productID }) {
                    await fulfillPurchase(userId: userId, plan: plan, transaction: tx)
                    await tx.finish()
                }
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

    private func fulfillPurchase(userId: String, plan: PremiumPlan, transaction: SKTransaction) async {
        let expires: Date = transaction.expirationDate ?? {
            switch plan {
            case .monthly: return Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
            case .yearly:  return Calendar.current.date(byAdding: .year,  value: 1, to: Date()) ?? Date()
            }
        }()
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
            guard let userId = boundUserId else { continue }
            if case .verified(let tx) = result,
               let plan = PremiumPlan.allCases.first(where: { $0.productID == tx.productID }) {
                await fulfillPurchase(userId: userId, plan: plan, transaction: tx)
                await tx.finish()
            }
        }
    }

    func cancelForTesting() async {
        guard let userId = boundUserId else { return }
        try? await service.clearEntitlement(userId: userId, coupleId: boundCoupleId)
    }
}
