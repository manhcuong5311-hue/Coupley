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
import UIKit

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
        case .customAvatar, .anniversaryPhoto, .allThemes, .fullQuizAccess:
            return isActive
        case .customQuizzes:
            // Custom chat quizzes: free users get 1/day, premium unlimited.
            if isActive { return true }
            return dailyUsage(for: .customQuizzes) < 1
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

    // MARK: - Display Helpers (Apple Guideline 3.1.2(c))
    //
    // Every price the paywall shows must come from StoreKit's localized
    // `Product.displayPrice` so the storefront's currency / tax rules are
    // honored. The fallbacks below are read only when products haven't loaded
    // yet (network blip, first launch); StoreKit overrides them the moment
    // `loadProducts()` resolves.

    /// The loaded `Product` for a plan, if available.
    func product(for plan: PremiumPlan) -> Product? {
        products.first { $0.id == plan.productID }
    }

    /// Localized base price (e.g. "$3.99"). Live → fallback in that order.
    func displayPrice(for plan: PremiumPlan) -> String {
        product(for: plan)?.displayPrice ?? plan.fallbackDisplayPrice
    }

    /// Spelled-out period unit ("month" / "year") — sourced from the
    /// StoreKit subscription period when loaded.
    func displayPeriod(for plan: PremiumPlan) -> String {
        if let unit = product(for: plan)?.subscription?.subscriptionPeriod.unit {
            switch unit {
            case .day:   return "day"
            case .week:  return "week"
            case .month: return "month"
            case .year:  return "year"
            @unknown default: return plan.fallbackPeriodLabel
            }
        }
        return plan.fallbackPeriodLabel
    }

    /// "$3.99 / month" — used in plan rows and the disclosure line.
    func priceWithPeriod(for plan: PremiumPlan) -> String {
        "\(displayPrice(for: plan)) / \(displayPeriod(for: plan))"
    }

    /// "7-day free trial" / "3-day free trial" — composed from StoreKit's
    /// `IntroductoryOffer` if the product has one configured. Returns `nil`
    /// when no intro offer is attached, which is the signal the paywall uses
    /// to render the no-trial CTA copy.
    func introductoryOfferDescription(for plan: PremiumPlan) -> String? {
        guard let offer = product(for: plan)?.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else {
            // Fallback to the bundled trial only on the yearly plan, so the
            // disclosure is still present pre-StoreKit-load. Apple Review
            // network is reliable but the safety net stops a "no trial copy"
            // flash on slow launches.
            return plan == .yearly ? "7-day free trial" : nil
        }
        let unit: String
        switch offer.period.unit {
        case .day:   unit = offer.period.value == 1 ? "day"   : "days"
        case .week:  unit = offer.period.value == 1 ? "week"  : "weeks"
        case .month: unit = offer.period.value == 1 ? "month" : "months"
        case .year:  unit = offer.period.value == 1 ? "year"  : "years"
        @unknown default: unit = "days"
        }
        return "\(offer.period.value)-\(unit) free trial"
    }

    func hasIntroductoryOffer(for plan: PremiumPlan) -> Bool {
        introductoryOfferDescription(for: plan) != nil
    }

    /// Compliance disclosure shown directly above the CTA. Mirrors the format
    /// Apple's review team consistently approves: trial length → renewal price
    /// → renewal cadence → cancellation instructions, with no hedging copy.
    func paywallDisclosure(for plan: PremiumPlan) -> String {
        let priceLine = priceWithPeriod(for: plan)
        if let trial = introductoryOfferDescription(for: plan) {
            return "\(trial), then \(priceLine), auto-renewing. " +
                   "Cancel anytime in Settings at least 24 hours before the period ends."
        }
        return "\(priceLine), auto-renewing. " +
               "Cancel anytime in Settings at least 24 hours before the period ends."
    }

    // MARK: - Manage Subscription
    //
    // Opens the in-app Manage Subscriptions sheet StoreKit 2 provides. If
    // the API fails (e.g. simulator without a sandbox account), fall back to
    // the App Store deep link that always works.
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
