//
//  PremiumPaywallView.swift
//  Coupley
//
//  Couple-shared premium paywall. One purchase unlocks everything for both
//  partners. Disconnecting reverts both users to the free tier.
//
//  Apple Review compliance — Guideline 3.1.2(c) Auto-Renewable Subscriptions:
//
//    1. Every price/period is sourced from StoreKit's localized
//       `Product.displayPrice` (see `PremiumStore.priceWithPeriod`). Bundled
//       fallbacks are wired only for the brief window before products load.
//    2. The compliance disclosure line sits *directly above* the purchase
//       button and restates: trial length → post-trial price → cadence →
//       cancellation. Apple Review consistently approves this format.
//    3. CTA copy never says "Continue" or "Try now". It says
//       "Start 7-Day Free Trial" when a trial is offered, otherwise
//       "Subscribe — $3.99/month" so the price is in the action itself.
//    4. Restore Purchases, Manage Subscription, Privacy Policy and Terms of
//       Use links are visible on the same screen as the CTA.
//

import SwiftUI

struct PremiumPaywallView: View {

    @EnvironmentObject var premiumStore: PremiumStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPlan: PremiumPlan = .yearly

    /// `true` once the user taps the CTA, so the paywall only auto-dismisses
    /// after *this* purchase completes — not when a viewer who was already
    /// subscribed opens the sheet to inspect their status.
    @State private var didInitiatePurchase = false

    var body: some View {
        ZStack {
            Brand.bgGradient.ignoresSafeArea(.all)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    header
                        .padding(.top, 32)
                        .padding(.bottom, 24)

                    if premiumStore.isActive {
                        activeCard
                            .padding(.horizontal, 20)
                            .padding(.bottom, 18)
                    }

                    planPicker
                        .padding(.horizontal, 20)
                        .padding(.bottom, 22)

                    comparisonTable
                        .padding(.horizontal, 20)
                        .padding(.bottom, 18)

                    partnerBadge
                        .padding(.horizontal, 20)
                        .padding(.bottom, 22)

                    // Apple Guideline 3.1.2(c): the disclosure must be visible
                    // directly with the CTA — not hidden behind a link or
                    // buried in the footer. Pinning it above the button is the
                    // safest layout for Review.
                    if !premiumStore.isActive {
                        ctaDisclosure
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)
                    }

                    purchaseButton
                        .padding(.horizontal, 20)
                        .padding(.bottom, 14)

                    secondaryActions
                        .padding(.bottom, 18)

                    legalLinks
                        .padding(.bottom, 14)

                    fineprint
                        .padding(.horizontal, 28)
                        .padding(.bottom, 40)
                }
            }
        }
        .navigationTitle("Coupley Premium")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Purchase issue", isPresented: Binding(
            get: { premiumStore.lastError != nil },
            set: { if !$0 { premiumStore.lastError = nil } }
        )) {
            Button("OK", role: .cancel) { premiumStore.lastError = nil }
        } message: {
            Text(premiumStore.lastError ?? "")
        }
        .onChange(of: premiumStore.isActive) { _, nowActive in
            // Close the sheet once the Firestore listener reports the new
            // entitlement. Delayed briefly so the user sees the "active"
            // state flash in before the sheet animates away.
            guard didInitiatePurchase, nowActive else { return }
            Task {
                try? await Task.sleep(nanoseconds: 600_000_000)
                dismiss()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 1.0, green: 0.80, blue: 0.25).opacity(0.35),
                                Color(red: 0.95, green: 0.45, blue: 0.30).opacity(0.15),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 30,
                            endRadius: 90
                        )
                    )
                    .frame(width: 180, height: 180)
                    .blur(radius: 20)

                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.82, blue: 0.30),
                                    Color(red: 0.95, green: 0.55, blue: 0.20)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)
                        .shadow(color: Color(red: 1.0, green: 0.70, blue: 0.20).opacity(0.5), radius: 20, y: 6)

                    Image(systemName: "crown.fill")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                }
            }

            VStack(spacing: 8) {
                Text("Coupley Premium")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)

                Text("One subscription · Two hearts · Unlimited love")
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Active Card

    private var activeCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 28))
                .foregroundStyle(Color(red: 0.30, green: 0.80, blue: 0.55))
            VStack(alignment: .leading, spacing: 3) {
                Text(premiumStore.source.displayLabel)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                if let exp = premiumStore.entitlement.expiresAt {
                    Text("Renews \(exp.formatted(date: .abbreviated, time: .omitted))")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)
                }
            }
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.30, green: 0.80, blue: 0.55).opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color(red: 0.30, green: 0.80, blue: 0.55).opacity(0.30), lineWidth: 1)
                )
        )
    }

    // MARK: - Plan Picker

    private var planPicker: some View {
        VStack(spacing: 10) {
            ForEach(PremiumPlan.allCases) { plan in
                planCard(plan)
            }
        }
    }

    private func planCard(_ plan: PremiumPlan) -> some View {
        let selected = plan == selectedPlan
        let trial = premiumStore.introductoryOfferDescription(for: plan)
        let priceLine = premiumStore.priceWithPeriod(for: plan)

        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            selectedPlan = plan
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .strokeBorder(selected ? Brand.accentStart : Brand.divider, lineWidth: 2)
                        .frame(width: 22, height: 22)
                    if selected {
                        Circle()
                            .fill(Brand.accentStart)
                            .frame(width: 12, height: 12)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(plan.label)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(Brand.textPrimary)
                        if let badge = plan.savingsBadge {
                            Text(badge)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .foregroundStyle(.white)
                                .background(
                                    Capsule().fill(
                                        LinearGradient(
                                            colors: [Color(red: 1.0, green: 0.75, blue: 0.20), Color(red: 0.95, green: 0.50, blue: 0.15)],
                                            startPoint: .leading, endPoint: .trailing
                                        )
                                    )
                                )
                        }
                    }
                    if let trial {
                        Text("\(trial), then \(priceLine)")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(Brand.accentStart)
                    } else {
                        Text(priceLine)
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(Brand.textSecondary)
                    }
                }

                Spacer()

                Text(plan.perMonthLabel)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(selected ? Brand.accentStart : Brand.textTertiary)
                    .multilineTextAlignment(.trailing)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(selected ? Brand.accentStart.opacity(0.10) : Brand.surfaceLight)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(
                                selected ? Brand.accentStart.opacity(0.5) : Brand.divider,
                                lineWidth: selected ? 1.5 : 1
                            )
                    )
            )
        }
        .buttonStyle(BouncyButtonStyle(scale: 0.98))
    }

    // MARK: - Comparison Table

    private var comparisonTable: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Feature")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Free")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.textTertiary)
                    .frame(width: 70, alignment: .center)
                Text("Premium")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Brand.accentStart)
                    .frame(width: 80, alignment: .center)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider().opacity(0.5).padding(.horizontal, 14)

            ForEach(PremiumFeature.allCases, id: \.self) { feature in
                comparisonRow(feature)
                if feature != PremiumFeature.allCases.last {
                    Divider().opacity(0.3).padding(.horizontal, 14)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Brand.surfaceLight)
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Brand.divider, lineWidth: 1))
        )
    }

    private func comparisonRow(_ feature: PremiumFeature) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: feature.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Brand.accentStart)
                    .frame(width: 18)
                Text(shortLabel(for: feature))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(feature.freeLabel)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.35))
                .multilineTextAlignment(.center)
                .frame(width: 70, alignment: .center)

            HStack(spacing: 4) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(red: 0.25, green: 0.80, blue: 0.50))
                Text(premiumLabel(for: feature))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.25, green: 0.80, blue: 0.50))
            }
            .frame(width: 80, alignment: .center)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func shortLabel(for feature: PremiumFeature) -> String {
        switch feature {
        case .aiMoodSuggestions:           return "AI suggestions"
        case .anniversaryPhoto:            return "Memory photos"
        case .fullQuizAccess:              return "Quiz library"
        case .customQuizzes:               return "Custom quizzes"
        case .customAvatar:                return "Custom avatar"
        case .allThemes:                   return "All themes"
        case .dateIdeas:                   return "Date ideas"
        case .aiCoach:                     return "AI Coach"
        case .chatPhotos:                  return "Chat photos"
        case .memoryCapsule:               return "Memory Capsules"
        case .togetherGoalsUnlimited:      return "Shared goals"
        case .togetherChallengesUnlimited: return "Couple challenges"
        case .togetherDreamBoard:          return "Dream Board"
        case .togetherCoach:               return "Couple Coach"
        }
    }

    private func premiumLabel(for feature: PremiumFeature) -> String {
        switch feature {
        case .aiMoodSuggestions:           return "50/day"
        case .dateIdeas:                   return "25/day"
        case .chatPhotos:                  return "Unlimited"
        case .customQuizzes:               return "Unlimited"
        case .togetherGoalsUnlimited:      return "Unlimited"
        case .togetherChallengesUnlimited: return "Unlimited"
        case .togetherDreamBoard:          return "Unlimited"
        default:                           return "Unlocked"
        }
    }

    // MARK: - Partner Badge

    private var partnerBadge: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Brand.accentStart)
            VStack(alignment: .leading, spacing: 3) {
                Text("Both partners get Premium")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                Text("One purchase shares Premium with your partner. If you disconnect, you keep it — your partner returns to free.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Brand.accentStart.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Brand.accentStart.opacity(0.25), lineWidth: 1)
                )
        )
    }

    // MARK: - CTA Disclosure (Apple Guideline 3.1.2(c))

    /// Renders the trial-and-renewal disclosure that Apple Review expects to
    /// see inside the call-to-action area, NOT just in the footer fine print.
    /// The string itself lives in `PremiumStore.paywallDisclosure(for:)` so a
    /// single source of truth feeds both the CTA disclosure and the footer.
    private var ctaDisclosure: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Brand.accentStart)
                .padding(.top, 1)
            Text(premiumStore.paywallDisclosure(for: selectedPlan))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Brand.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Brand.accentStart.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Brand.accentStart.opacity(0.20), lineWidth: 1)
                )
        )
    }

    // MARK: - Purchase

    private var purchaseButton: some View {
        Button {
            handlePrimaryAction()
        } label: {
            Group {
                if premiumStore.isPurchasing {
                    ProgressView().tint(.white)
                } else {
                    Text(purchaseButtonLabel)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(AnyShapeStyle(Brand.accentGradient))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: Brand.accentStart.opacity(0.40), radius: 14, y: 5)
        }
        .buttonStyle(BouncyButtonStyle())
        .disabled(premiumStore.isPurchasing)
    }

    private func handlePrimaryAction() {
        if premiumStore.isActive {
            Task { await premiumStore.openManageSubscriptions() }
            return
        }
        didInitiatePurchase = true
        Task { await premiumStore.purchase(plan: selectedPlan) }
    }

    /// CTA label rules (Apple Guideline 3.1.2(c) — wording must be unambiguous):
    ///
    ///   • Active subscriber          → "Manage Subscription"
    ///   • Plan has a free trial      → "Start <N>-Day Free Trial"
    ///   • No trial (monthly)         → "Subscribe — <price>/<period>"
    ///
    /// Banned: "Continue", "Try now", "Get started" — all flagged in past
    /// rejections for hiding the recurring billing commitment.
    private var purchaseButtonLabel: String {
        if premiumStore.isActive { return "Manage Subscription" }
        if let trial = premiumStore.introductoryOfferDescription(for: selectedPlan) {
            return "Start \(trial.titleCasedForCTA)"
        }
        return "Subscribe — \(premiumStore.priceWithPeriod(for: selectedPlan))"
    }

    // MARK: - Secondary Actions (Restore, Manage)

    private var secondaryActions: some View {
        HStack(spacing: 24) {
            Button("Restore Purchases") {
                Task { await premiumStore.restorePurchases() }
            }
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(Brand.textSecondary)

            if premiumStore.isActive {
                Text("·").foregroundStyle(Brand.textTertiary)
                Button("Manage Subscription") {
                    Task { await premiumStore.openManageSubscriptions() }
                }
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Brand.textSecondary)
            }
        }
    }

    // MARK: - Legal links (Apple Guideline 3.1.2)

    private var legalLinks: some View {
        HStack(spacing: 6) {
            if let url = URL(string: "https://manhcuong5311-hue.github.io/Coupley/") {
                Link("Privacy Policy", destination: url)
            }
            Text("·").foregroundStyle(Brand.textTertiary)
            if let url = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/") {
                Link("Terms of Use (EULA)", destination: url)
            }
        }
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .foregroundStyle(Brand.textSecondary)
    }

    // MARK: - Fine print (Apple Guideline 3.1.2 — Auto-Renewable Subscriptions)

    private var fineprint: some View {
        let monthlyPrice = premiumStore.priceWithPeriod(for: .monthly)
        let yearlyPrice = premiumStore.priceWithPeriod(for: .yearly)
        let yearlyTrial = premiumStore.introductoryOfferDescription(for: .yearly) ?? "free trial"

        return Text(
            "Coupley Premium is an auto-renewable subscription. " +
            "Monthly plan: \(monthlyPrice) — charged immediately at purchase. " +
            "Yearly plan: \(yearlyPrice) — includes a \(yearlyTrial) for new subscribers. " +
            "Payment is charged to your Apple ID at the end of the trial (yearly) or at purchase (monthly). " +
            "Your subscription automatically renews at the same price unless auto-renew is turned off at least 24 hours before the end of the current period. " +
            "Manage or cancel your subscription in Settings → Apple ID → Subscriptions. " +
            "Any unused portion of a free trial is forfeited when you purchase a subscription."
        )
        .font(.system(size: 11, design: .rounded))
        .foregroundStyle(Brand.textTertiary)
        .multilineTextAlignment(.center)
        .lineSpacing(2)
    }
}

// MARK: - Title case helper

private extension String {
    /// Title-cases a phrase, capitalizing after both spaces *and* hyphens
    /// so `"7-day free trial"` → `"7-Day Free Trial"` for the CTA. Pure
    /// ASCII so it stays predictable across locales.
    var titleCasedForCTA: String {
        split(separator: " ", omittingEmptySubsequences: false)
            .map { word in
                word
                    .split(separator: "-", omittingEmptySubsequences: false)
                    .map { piece -> String in
                        guard let first = piece.first else { return String(piece) }
                        return first.uppercased() + piece.dropFirst()
                    }
                    .joined(separator: "-")
            }
            .joined(separator: " ")
    }
}

#Preview {
    NavigationStack {
        PremiumPaywallView()
            .environmentObject(PremiumStore(service: MockPremiumService()))
    }
}
