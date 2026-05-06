//
//  OnboardingFlowView.swift
//  Coupley
//
//  Container for the post-login onboarding flow. Owns a single
//  `OnboardingViewModel` and routes to the right step view based on
//  `viewModel.step`. Each step renders inside `OnboardingStepScaffold`,
//  so this view only handles step→step transitions and final completion.
//
//  Completion: when `viewModel.complete()` succeeds, it calls
//  `onCompleted`, which is wired to flip
//  `@AppStorage("hasCompletedOnboarding")` in RootView. The session state
//  is otherwise unchanged — pairing / premium / Firebase data are all
//  untouched, so the 5-tap reset gesture in Settings is safe.
//

import SwiftUI

struct OnboardingFlowView: View {

    @StateObject private var viewModel: OnboardingViewModel

    /// Closure RootView passes to flip `hasCompletedOnboarding` once the
    /// terminal Firestore write lands. Kept on the view (instead of
    /// `@AppStorage` directly inside the VM) so the VM is testable without
    /// SwiftUI environment dependencies.
    let onCompleted: () -> Void

    init(userId: String,
         initialName: String = "",
         onCompleted: @escaping () -> Void) {
        _viewModel = StateObject(
            wrappedValue: OnboardingViewModel(userId: userId, initialName: initialName)
        )
        self.onCompleted = onCompleted
    }

    var body: some View {
        ZStack {
            currentStep
                .id(viewModel.step)
                .transition(transition(for: viewModel.step))
        }
        .brandBackground()
        .onAppear { viewModel.onCompleted = onCompleted }
        .onChange(of: viewModel.step) { _, _ in
            // Persist after every transition. The VM debounces internally,
            // so rapid taps coalesce into a single Firestore write.
        }
        .task {
            // Mirror the closure on every render; `onAppear` covers cold
            // starts but not preview/SwiftUI re-inits.
            viewModel.onCompleted = onCompleted
        }
    }

    // MARK: - Step routing

    @ViewBuilder
    private var currentStep: some View {
        switch viewModel.step {
        // Why
        case .welcome:           WelcomeStepView(viewModel: viewModel)
        case .benefits:          BenefitsStepView(viewModel: viewModel)
        case .moodSync:          MoodSyncStepView(viewModel: viewModel)
        case .memories:          MemoriesStepView(viewModel: viewModel)
        case .communication:     CommunicationStepView(viewModel: viewModel)
        case .aiAssistance:      AIAssistanceStepView(viewModel: viewModel)
        case .dailyConnection:   DailyConnectionStepView(viewModel: viewModel)
        // Setup
        case .nameInput:         NameInputStepView(viewModel: viewModel)
        case .partnerInput:      PartnerInputStepView(viewModel: viewModel)
        case .goals:             GoalsStepView(viewModel: viewModel)
        case .communicationStyle:CommunicationStyleStepView(viewModel: viewModel)
        case .dailyHabit:        DailyHabitStepView(viewModel: viewModel)
        case .notifications:     NotificationsStepView(viewModel: viewModel)
        case .widget:            WidgetStepView(viewModel: viewModel)
        case .partnerExpectation:PartnerExpectationStepView(viewModel: viewModel)
        // Pay
        case .paywall:           OnboardingPaywallStepView(viewModel: viewModel)
        }
    }

    /// Slide steps in from the trailing edge when moving forward, leading
    /// when moving back. We approximate "direction" from step rawValue
    /// changes elsewhere; here we always animate forward since the VM owns
    /// the state and back-taps re-render the previous step's view.
    private func transition(for step: OnboardingStep) -> AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal:   .move(edge: .leading).combined(with: .opacity)
        )
    }
}

// MARK: - Onboarding-flavored Paywall

/// Final step of onboarding. Visually the same product as
/// `PremiumPaywallView`, but wired to `OnboardingViewModel.complete()`
/// rather than dismissing a sheet — onboarding doesn't live in a sheet.
///
/// "Maybe Later" still completes onboarding; we don't want to gate the
/// app behind a purchase. The paywall reappears whenever a premium feature
/// is tapped post-onboarding.
struct OnboardingPaywallStepView: View {

    @ObservedObject var viewModel: OnboardingViewModel
    @EnvironmentObject var premiumStore: PremiumStore

    @State private var selectedPlan: PremiumPlan = .yearly
    @State private var didInitiatePurchase = false

    var body: some View {
        VStack(spacing: 0) {
            // No top bar / progress on the paywall — clean, focused screen.
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    header
                        .padding(.top, 32)
                        .padding(.bottom, 24)

                    planPicker
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)

                    valueRows
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)

                    sharedBadge
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                }
            }
            .scrollBounceBehavior(.basedOnSize)

            bottomCTA
        }
        .alert("Purchase issue", isPresented: Binding(
            get: { premiumStore.lastError != nil },
            set: { if !$0 { premiumStore.lastError = nil } }
        )) {
            Button("OK", role: .cancel) { premiumStore.lastError = nil }
        } message: {
            Text(premiumStore.lastError ?? "")
        }
        .onChange(of: premiumStore.isActive) { _, nowActive in
            // Once StoreKit + Firestore agree the purchase landed, complete
            // onboarding. Brief delay so the user sees state confirm before
            // we move on.
            guard didInitiatePurchase, nowActive else { return }
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000)
                await viewModel.complete()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 14) {
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
                        .frame(width: 96, height: 96)
                        .shadow(color: Color(red: 1.0, green: 0.70, blue: 0.20).opacity(0.5), radius: 18, y: 6)

                    Image(systemName: "crown.fill")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                }
            }

            VStack(spacing: 8) {
                Text("Try Coupley Premium")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                    .multilineTextAlignment(.center)

                Text("One subscription · Two hearts · 7 days free")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
    }

    // MARK: - Plan picker

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
                        Circle().fill(Brand.accentStart).frame(width: 12, height: 12)
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
                                .background(
                                    Capsule().fill(
                                        LinearGradient(
                                            colors: [Color(red: 1.0, green: 0.75, blue: 0.20),
                                                     Color(red: 0.95, green: 0.50, blue: 0.15)],
                                            startPoint: .leading, endPoint: .trailing
                                        )
                                    )
                                )
                        }
                    }
                    if let trial = premiumStore.introductoryOfferDescription(for: plan) {
                        Text("\(trial), then \(premiumStore.priceWithPeriod(for: plan))")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(Brand.accentStart)
                    } else {
                        Text(premiumStore.priceWithPeriod(for: plan))
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

    // MARK: - Value rows

    private var valueRows: some View {
        VStack(spacing: 10) {
            valueRow(icon: "sparkles",
                     tint: Color(red: 0.65, green: 0.45, blue: 1.0),
                     title: "AI coach + suggestions",
                     subtitle: "Personalized prompts and date ideas, daily.")
            valueRow(icon: "heart.fill",
                     tint: Color(red: 1.0, green: 0.42, blue: 0.55),
                     title: "Unlock the full quiz library",
                     subtitle: "Hundreds of conversation starters.")
            valueRow(icon: "calendar.badge.clock",
                     tint: Color(red: 0.95, green: 0.65, blue: 0.20),
                     title: "Cover photos for memories",
                     subtitle: "Make your shared moments feel real.")
            valueRow(icon: "paintbrush.fill",
                     tint: Color(red: 0.45, green: 0.62, blue: 1.0),
                     title: "Custom themes + avatars",
                     subtitle: "Make Coupley feel like *yours*.")
        }
    }

    private func valueRow(icon: String, tint: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(tint.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Brand.surfaceLight)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Brand.divider, lineWidth: 1)
                )
        )
    }

    // MARK: - Shared badge

    private var sharedBadge: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Brand.accentStart)
            Text("One purchase, both partners get Premium.")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Brand.textPrimary)
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Brand.accentStart.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Brand.accentStart.opacity(0.25), lineWidth: 1)
                )
        )
    }

    // MARK: - Bottom CTA

    /// Apple Guideline 3.1.2(c)-compliant CTA stack:
    ///   • Disclosure line (trial + post-trial price + cadence + cancel)
    ///     pinned directly above the button.
    ///   • CTA copy switches between "Start <N>-Day Free Trial" (when an
    ///     intro offer exists for the selected plan) and
    ///     "Subscribe — $X.XX/period" (no trial). Never says "Continue".
    ///   • Price comes from StoreKit via `PremiumStore.priceWithPeriod` so
    ///     localized currency / store regional prices are honored.
    private var bottomCTA: some View {
        VStack(spacing: 10) {
            ctaDisclosure

            Button {
                guard !premiumStore.isActive else { return }
                didInitiatePurchase = true
                Task { await premiumStore.purchase(plan: selectedPlan) }
            } label: {
                Group {
                    if premiumStore.isPurchasing || viewModel.isCompleting {
                        ProgressView().tint(.white)
                    } else {
                        Text(premiumStore.isActive
                             ? "You're already Premium"
                             : ctaButtonLabel)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    premiumStore.isActive
                        ? AnyShapeStyle(Brand.surfaceLight)
                        : AnyShapeStyle(Brand.accentGradient)
                )
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .shadow(color: premiumStore.isActive ? .clear : Brand.accentStart.opacity(0.40),
                        radius: 14, y: 5)
            }
            .buttonStyle(BouncyButtonStyle())
            .disabled(premiumStore.isPurchasing || viewModel.isCompleting)

            Button("Maybe later") {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                Task { await viewModel.complete() }
            }
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(Brand.textSecondary)
            .padding(.top, 4)

            HStack(spacing: 14) {
                Button("Restore") {
                    Task { await premiumStore.restorePurchases() }
                }
                Text("·").foregroundStyle(Brand.textTertiary)
                if let url = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/") {
                    Link("Terms (EULA)", destination: url)
                }
                Text("·").foregroundStyle(Brand.textTertiary)
                if let url = URL(string: "https://manhcuong5311-hue.github.io/Coupley/") {
                    Link("Privacy", destination: url)
                }
            }
            .font(.system(size: 11, design: .rounded))
            .foregroundStyle(Brand.textTertiary)
            .padding(.top, 6)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 22)
        .padding(.top, 10)
    }

    /// Disclosure block sourced from `PremiumStore.paywallDisclosure(for:)`
    /// so onboarding and the standalone paywall stay in lockstep.
    private var ctaDisclosure: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Brand.accentStart)
                .padding(.top, 1)
            Text(premiumStore.paywallDisclosure(for: selectedPlan))
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(Brand.textSecondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Brand.accentStart.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Brand.accentStart.opacity(0.20), lineWidth: 1)
                )
        )
    }

    private var ctaButtonLabel: String {
        if let trial = premiumStore.introductoryOfferDescription(for: selectedPlan) {
            return "Start \(trial.titleCasedForCTA)"
        }
        return "Subscribe — \(premiumStore.priceWithPeriod(for: selectedPlan))"
    }
}

// MARK: - Title case helper (mirror of PremiumPaywallView's helper)

private extension String {
    /// Title-cases a phrase, capitalizing after both spaces *and* hyphens
    /// so `"7-day free trial"` → `"7-Day Free Trial"` for the CTA.
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
