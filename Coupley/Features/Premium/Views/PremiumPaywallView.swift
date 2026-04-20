//
//  PremiumPaywallView.swift
//  Coupley
//
//  Couple-shared premium paywall. Shown from Settings → Premium or as a
//  gate when a user taps a premium-only feature.
//

import SwiftUI

struct PremiumPaywallView: View {

    @EnvironmentObject var premiumStore: PremiumStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPlan: PremiumPlan = .yearly

    var body: some View {
        ZStack {
            Brand.bgGradient.ignoresSafeArea(.all)

            ScrollView {
                VStack(spacing: 0) {
                    header
                        .padding(.top, 24)
                        .padding(.bottom, 24)

                    if premiumStore.isActive {
                        activeCard
                            .padding(.horizontal, 20)
                            .padding(.bottom, 16)
                    }

                    featureGrid
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)

                    planPicker
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)

                    purchaseButton
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)

                    fineprint
                        .padding(.horizontal, 32)
                        .padding(.bottom, 32)
                }
            }
        }
        .navigationTitle("Coupley Premium")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Restore") {
                    Task { await premiumStore.restorePurchases() }
                }
                .foregroundStyle(Brand.textSecondary)
            }
        }
        .alert("Purchase issue", isPresented: Binding(
            get: { premiumStore.lastError != nil },
            set: { if !$0 { premiumStore.lastError = nil } }
        )) {
            Button("OK", role: .cancel) { premiumStore.lastError = nil }
        } message: {
            Text(premiumStore.lastError ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Brand.accentStart.opacity(0.20))
                    .frame(width: 150, height: 150)
                    .blur(radius: 40)
                ZStack {
                    Circle()
                        .fill(Brand.surfaceLight)
                        .frame(width: 96, height: 96)
                        .overlay(Circle().strokeBorder(Brand.divider, lineWidth: 1))
                    Image(systemName: "sparkles")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(Brand.accentGradient)
                }
            }

            Text("Grow closer, together")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Brand.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Text("One subscription unlocks everything for **both** partners.")
                .font(.system(size: 15, design: .rounded))
                .foregroundStyle(Brand.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
    }

    // MARK: - Active Card

    private var activeCard: some View {
        GlassCard {
            HStack(spacing: 14) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color(red: 0.30, green: 0.80, blue: 0.55))
                VStack(alignment: .leading, spacing: 3) {
                    Text(activeTitle)
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
        }
    }

    private var activeTitle: String {
        switch premiumStore.source {
        case .partner: return "Premium — shared from your partner"
        case .self_:   return "Premium — active"
        case .none:    return "Premium — active"
        }
    }

    // MARK: - Feature Grid

    private var featureGrid: some View {
        VStack(spacing: 10) {
            ForEach(PremiumFeature.allCases, id: \.self) { feature in
                featureRow(feature)
            }
        }
    }

    private func featureRow(_ feature: PremiumFeature) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Brand.accentStart.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: feature.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Brand.accentStart)
            }
            Text(feature.label)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Brand.textPrimary)
            Spacer()
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color(red: 0.30, green: 0.80, blue: 0.55))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Brand.surfaceLight)
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Brand.divider, lineWidth: 1))
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

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(plan.label)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(Brand.textPrimary)
                        if let badge = plan.savingsBadge {
                            Text(badge)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .foregroundStyle(.white)
                                .background(Capsule().fill(Brand.accentGradient))
                        }
                    }
                    Text(plan.priceLabel)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)
                }
                Spacer()
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(selected ? Brand.accentStart.opacity(0.10) : Brand.surfaceLight)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(selected ? Brand.accentStart.opacity(0.5) : Brand.divider,
                                          lineWidth: selected ? 1.5 : 1)
                    )
            )
        }
        .buttonStyle(BouncyButtonStyle(scale: 0.98))
    }

    // MARK: - Purchase

    private var purchaseButton: some View {
        PrimaryButton(
            title: premiumStore.isActive ? "Manage subscription" : "Continue",
            isLoading: premiumStore.isPurchasing,
            isEnabled: !premiumStore.isActive
        ) {
            Task { await premiumStore.purchase(plan: selectedPlan) }
        }
    }

    // MARK: - Fine print

    private var fineprint: some View {
        Text("Payment is charged to your Apple ID. Subscription auto-renews unless turned off at least 24 h before the end of the period. Manage in Settings → Apple ID.")
            .font(.system(size: 11, design: .rounded))
            .foregroundStyle(Brand.textTertiary)
            .multilineTextAlignment(.center)
            .lineSpacing(2)
    }
}

#Preview {
    NavigationStack {
        PremiumPaywallView()
            .environmentObject(PremiumStore(service: MockPremiumService()))
    }
}
