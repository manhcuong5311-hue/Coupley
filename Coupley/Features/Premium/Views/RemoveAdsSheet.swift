//
//  RemoveAdsSheet.swift
//  Coupley
//
//  The only purchase in Coupley: a one-time "Remove Ads". Every feature is
//  already free; buying turns ads off for the buyer and, when paired, for
//  their partner too (shared through the couple doc).
//
//  Also hosts:
//    • `RemoveAdsRow`        — Settings entry point / status row.
//    • `LegacySubscriberNotice` — tells former Premium subscribers that the
//      app is free now and they can cancel (they stay ad-free forever).
//

import SwiftUI

struct RemoveAdsSheet: View {

    @EnvironmentObject var premiumStore: PremiumStore
    @Environment(\.dismiss) private var dismiss

    /// False when pushed inside an existing navigation stack (Settings).
    var showsCloseButton = true

    @State private var didInitiatePurchase = false

    var body: some View {
        ZStack {
            Brand.bgGradient.ignoresSafeArea(.all)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    header
                        .padding(.top, 32)
                        .padding(.bottom, 26)

                    benefits
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)

                    if premiumStore.isAdFree {
                        adFreeCard
                            .padding(.horizontal, 20)
                            .padding(.bottom, 16)
                    } else {
                        purchaseButton
                            .padding(.horizontal, 20)
                            .padding(.bottom, 14)
                    }

                    Button("Restore Purchases") {
                        Task { await premiumStore.restorePurchases() }
                    }
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
                    .disabled(premiumStore.isPurchasing)
                    .padding(.bottom, 18)

                    footer
                        .padding(.horizontal, 28)
                        .padding(.bottom, 40)
                }
            }
        }
        .navigationTitle("Remove Ads")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Brand.accentStart)
                }
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
        .onChange(of: premiumStore.isAdFree) { _, adFree in
            guard didInitiatePurchase, adFree else { return }
            Task {
                try? await Task.sleep(nanoseconds: 700_000_000)
                dismiss()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Brand.accentStart.opacity(0.18))
                    .frame(width: 150, height: 150)
                    .blur(radius: 24)

                Circle()
                    .fill(Brand.accentGradient)
                    .frame(width: 92, height: 92)
                    .shadow(color: Brand.accentStart.opacity(0.45), radius: 18, y: 6)

                Image(systemName: "nosign")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 8) {
                Text("Remove Ads")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)

                Text("Every Coupley feature is free for both of you.\nRemove ads once — for you and your partner.")
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
    }

    // MARK: - Benefits

    private var benefits: some View {
        VStack(spacing: 0) {
            benefitRow(icon: "eye.slash.fill", text: "No banner or full-screen ads")
            Divider().overlay(Brand.divider).padding(.leading, 60)
            benefitRow(icon: "heart.circle.fill", text: "Ad-free for your partner too")
            Divider().overlay(Brand.divider).padding(.leading, 60)
            benefitRow(icon: "infinity", text: "One-time purchase, yours forever")
            Divider().overlay(Brand.divider).padding(.leading, 60)
            benefitRow(icon: "hand.thumbsup.fill", text: "Supports an indie developer")
        }
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: Brand.cardCornerRadius)
                .fill(Brand.surfaceLight)
                .overlay(
                    RoundedRectangle(cornerRadius: Brand.cardCornerRadius)
                        .strokeBorder(Brand.divider, lineWidth: 1)
                )
        )
    }

    private func benefitRow(icon: String, text: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Brand.accentStart.opacity(0.14))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Brand.accentStart)
            }
            Text(text)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Brand.textPrimary)
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Brand.accentStart)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Purchase / status

    private var purchaseButton: some View {
        Button {
            didInitiatePurchase = true
            Task { await premiumStore.purchaseRemoveAds() }
        } label: {
            Group {
                if premiumStore.isPurchasing {
                    ProgressView().tint(.white)
                } else {
                    Label("Remove Ads — \(premiumStore.removeAdsDisplayPrice)", systemImage: "nosign")
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

    private var adFreeCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 22))
                .foregroundStyle(Brand.accentStart)
            VStack(alignment: .leading, spacing: 2) {
                Text("You're ad-free")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                Text(premiumStore.source == .partnerShared
                     ? "Shared from your partner. Enjoy!"
                     : "Thanks for supporting Coupley.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
            }
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Brand.accentStart.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Brand.accentStart.opacity(0.25), lineWidth: 1)
                )
        )
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 10) {
            Text("One-time payment charged to your Apple ID. No subscription.")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(Brand.textTertiary)
                .multilineTextAlignment(.center)

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
    }
}

// MARK: - Settings row

/// Settings entry point: "Remove Ads · $9.99" or the ad-free status.
struct RemoveAdsRow: View {

    @EnvironmentObject var premiumStore: PremiumStore

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Brand.accentGradient)
                    .frame(width: 34, height: 34)
                Image(systemName: premiumStore.isAdFree ? "checkmark.seal.fill" : "nosign")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(premiumStore.isAdFree ? "Ad-free" : "Remove Ads")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
            }
        }
    }

    private var subtitle: String {
        guard premiumStore.isAdFree else {
            return "One-time purchase · \(premiumStore.removeAdsDisplayPrice) · for both of you"
        }
        return premiumStore.source == .partnerShared
            ? "Shared from your partner"
            : "Thanks for supporting Coupley"
    }
}

// MARK: - Legacy subscriber notice

/// Shown to people who still pay for the old Premium subscription.
struct LegacySubscriberNotice: View {

    @EnvironmentObject var premiumStore: PremiumStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Coupley is free now", systemImage: "gift.fill")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Brand.textPrimary)

            Text("Every feature is free for everyone. As a Premium subscriber you stay ad-free forever, so you can cancel your subscription whenever you like.")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Brand.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Task { await premiumStore.openManageSubscriptions() }
            } label: {
                Text("Manage Subscription")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.accentStart)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        RemoveAdsSheet()
            .environmentObject(PremiumStore(service: MockPremiumService()))
    }
}
