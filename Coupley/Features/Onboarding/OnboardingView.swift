//
//  OnboardingView.swift
//  Coupley
//
//  Full-screen onboarding → paywall → auth entry point.
//  Flow: 3 emotional slides → paywall → AuthView
//

import SwiftUI

// MARK: - Onboarding Slide Model

private struct Slide {
    let icon: String
    let emoji: String
    let gradient: LinearGradient
    let glowColor: Color
    let buttonForeground: Color
    let title: String
    let subtitle: String
}

private let slides: [Slide] = [
    Slide(
        icon: "heart.fill",
        emoji: "💞",
        gradient: LinearGradient(
            colors: [
                Color(red: 0.80, green: 0.18, blue: 0.42),
                Color(red: 0.50, green: 0.08, blue: 0.28),
                Color(red: 0.12, green: 0.04, blue: 0.18),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        ),
        glowColor: Color(red: 1.0, green: 0.38, blue: 0.60),
        buttonForeground: Color(red: 0.55, green: 0.08, blue: 0.28),
        title: "Your love,\nalways in sync",
        subtitle: "Know how your partner feels — even when you're miles apart."
    ),
    Slide(
        icon: "moon.stars.fill",
        emoji: "✨",
        gradient: LinearGradient(
            colors: [
                Color(red: 0.24, green: 0.14, blue: 0.70),
                Color(red: 0.12, green: 0.08, blue: 0.50),
                Color(red: 0.05, green: 0.04, blue: 0.22),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        ),
        glowColor: Color(red: 0.50, green: 0.35, blue: 1.0),
        buttonForeground: Color(red: 0.18, green: 0.08, blue: 0.55),
        title: "Feel each other,\nevery single day",
        subtitle: "Share your mood and energy.\nLet them know you're thinking of them."
    ),
    Slide(
        icon: "flame.fill",
        emoji: "🔥",
        gradient: LinearGradient(
            colors: [
                Color(red: 0.92, green: 0.48, blue: 0.14),
                Color(red: 0.75, green: 0.22, blue: 0.22),
                Color(red: 0.22, green: 0.06, blue: 0.12),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        ),
        glowColor: Color(red: 1.0, green: 0.60, blue: 0.20),
        buttonForeground: Color(red: 0.45, green: 0.10, blue: 0.08),
        title: "Grow your\nbond every day",
        subtitle: "Build streaks, track your sync score,\nand deepen your connection."
    ),
]

// MARK: - Main Onboarding View

struct OnboardingView: View {

    // Set true after paywall dismiss — triggers RootView to show AuthView
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    @State private var currentSlide = 0
    @State private var showPaywall = false
    @State private var iconScale: CGFloat = 1.0
    @State private var contentOffset: CGFloat = 0

    var body: some View {
        ZStack {
            // Slide gradient — changes with each slide
            slides[currentSlide].gradient
                .ignoresSafeArea(.all)
                .animation(.easeInOut(duration: 0.55), value: currentSlide)

            if showPaywall {
                PaywallView { hasSeenOnboarding = true }
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            } else {
                slideOverlay.transition(.opacity)
            }
        }
        .fixWindowBackground()
        .animation(.spring(response: 0.55, dampingFraction: 0.85), value: showPaywall)
    }

    // MARK: - Slide Overlay (content on top of the gradient)

    private var slideOverlay: some View {
        ZStack {
            // Ambient glow orbs
            glowOrbs

            VStack(spacing: 0) {
                // Skip button — respects status bar safe area
                HStack {
                    Spacer()
                    if currentSlide < slides.count - 1 {
                        Button("Skip") { jumpToLast() }
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                            .padding(.trailing, 24)
                            .padding(.top, 60)  // below status bar
                    }
                }

                Spacer()

                // Main icon
                iconView
                    .scaleEffect(iconScale)

                Spacer()

                // Bottom panel
                bottomPanel
            }
        }
        .gesture(
            DragGesture()
                .onEnded { value in
                    if value.translation.width < -50 { advance() }
                    if value.translation.width > 50 && currentSlide > 0 {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            currentSlide -= 1
                        }
                    }
                }
        )
    }

    // MARK: - Glow Orbs

    private var glowOrbs: some View {
        ZStack {
            Circle()
                .fill(slides[currentSlide].glowColor.opacity(0.30))
                .frame(width: 320, height: 320)
                .blur(radius: 90)
                .offset(x: -70, y: -140)
                .animation(.easeInOut(duration: 0.6), value: currentSlide)

            Circle()
                .fill(slides[currentSlide].glowColor.opacity(0.15))
                .frame(width: 220, height: 220)
                .blur(radius: 70)
                .offset(x: 90, y: 160)
                .animation(.easeInOut(duration: 0.6).delay(0.1), value: currentSlide)
        }
        .ignoresSafeArea()
    }

    // MARK: - Icon View

    private var iconView: some View {
        VStack(spacing: 24) {
            ZStack {
                // Outer ring
                Circle()
                    .fill(.white.opacity(0.06))
                    .frame(width: 180, height: 180)

                // Middle ring
                Circle()
                    .fill(.white.opacity(0.09))
                    .frame(width: 130, height: 130)

                // Icon
                Image(systemName: slides[currentSlide].icon)
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolEffect(.pulse.byLayer, options: .repeating)
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: currentSlide)

            Text(slides[currentSlide].emoji)
                .font(.system(size: 36))
                .animation(.spring(response: 0.45), value: currentSlide)
        }
    }

    // MARK: - Bottom Panel

    private var bottomPanel: some View {
        GeometryReader { geo in
            let bottomSafe = geo.safeAreaInsets.bottom

            VStack(spacing: 0) {

                // Page indicator dots
                HStack(spacing: 7) {
                    ForEach(0..<slides.count, id: \.self) { i in
                        Capsule()
                            .fill(.white.opacity(i == currentSlide ? 1.0 : 0.28))
                            .frame(width: i == currentSlide ? 28 : 7, height: 7)
                            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: currentSlide)
                    }
                }
                .padding(.top, 36)
                .padding(.bottom, 32)

                // Title
                Text(slides[currentSlide].title)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 28)
                    .id("t\(currentSlide)")
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))

                // Subtitle
                Text(slides[currentSlide].subtitle)
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 36)
                    .padding(.top, 14)
                    .id("s\(currentSlide)")
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))

                // CTA Button
                Button(action: advance) {
                    Text(currentSlide == slides.count - 1 ? "Get Started" : "Continue")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(slides[currentSlide].buttonForeground)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
                }
                .buttonStyle(BouncyButtonStyle())
                .padding(.horizontal, 24)
                .padding(.top, 36)
                .padding(.bottom, max(bottomSafe, 32))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Actions

    private func advance() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
            if currentSlide < slides.count - 1 {
                currentSlide += 1
            } else {
                showPaywall = true
            }
        }

        // Icon bounce
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
            iconScale = 0.88
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                iconScale = 1.0
            }
        }
    }

    private func jumpToLast() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            currentSlide = slides.count - 1
        }
    }
}

// MARK: - Paywall View

struct PaywallView: View {

    let onComplete: () -> Void

    @State private var selectedPlan: PaywallPlan = .annual
    @State private var isSubscribing = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                headerSection
                featuresSection
                pricingSection
                ctaSection
                legalSection
            }
        }
        .brandBackground()
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 16) {
            // Crown icon with glow
            ZStack {
                Circle()
                    .fill(Brand.accentStart.opacity(0.18))
                    .frame(width: 120, height: 120)
                    .blur(radius: 30)

                ZStack {
                    Circle()
                        .fill(Brand.surfaceLight)
                        .frame(width: 90, height: 90)
                        .overlay(
                            Circle().strokeBorder(Brand.divider, lineWidth: 1)
                        )

                    Image(systemName: "crown.fill")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(red: 1.0, green: 0.82, blue: 0.30), Color(red: 1.0, green: 0.55, blue: 0.20)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                }
            }
            .padding(.top, 56)

            Text("Coupley Premium")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Brand.textPrimary)

            Text("Everything you need to stay\ncloser to the one you love.")
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(Brand.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 36)
    }

    // MARK: - Features

    private var featuresSection: some View {
        VStack(spacing: 12) {
            ForEach(PaywallFeature.all) { feature in
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(feature.color.opacity(0.18))
                            .frame(width: 44, height: 44)

                        Image(systemName: feature.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(feature.color)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(feature.title)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(Brand.textPrimary)

                        Text(feature.description)
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .foregroundStyle(Brand.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Brand.accentStart)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(Brand.surfaceLight)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Brand.divider, lineWidth: 1)
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 32)
    }

    // MARK: - Pricing

    private var pricingSection: some View {
        VStack(spacing: 12) {
            Text("Choose your plan")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Brand.textSecondary)
                .padding(.bottom, 4)

            ForEach(PaywallPlan.allCases, id: \.self) { plan in
                planCard(plan)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 32)
    }

    private func planCard(_ plan: PaywallPlan) -> some View {
        let isSelected = selectedPlan == plan

        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                selectedPlan = plan
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 14) {
                // Selection indicator
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? Brand.accentStart : Brand.divider, lineWidth: 2)
                        .frame(width: 22, height: 22)

                    if isSelected {
                        Circle()
                            .fill(Brand.accentStart)
                            .frame(width: 12, height: 12)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(plan.title)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(Brand.textPrimary)

                        if plan == .annual {
                            Text("SAVE 40%")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Brand.accentGradient)
                                .clipShape(Capsule())
                        }
                    }

                    Text(plan.subtitle)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)
                }

                Spacer()

                Text(plan.price)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(isSelected ? Brand.accentStart : Brand.textSecondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Brand.accentStart.opacity(0.10) : Brand.surfaceLight)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isSelected ? Brand.accentStart.opacity(0.60) : Brand.divider, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(BouncyButtonStyle(scale: 0.98))
    }

    // MARK: - CTA

    private var ctaSection: some View {
        VStack(spacing: 14) {
            PrimaryButton(title: isSubscribing ? "" : "Start 7-Day Free Trial",
                          isLoading: isSubscribing) {
                subscribe()
            }
            .padding(.horizontal, 20)

            Text("then \(selectedPlan.price) · Cancel anytime")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(Brand.textTertiary)

            Button("Maybe Later") {
                onComplete()
            }
            .font(.system(size: 15, weight: .medium, design: .rounded))
            .foregroundStyle(Brand.textSecondary)
            .padding(.top, 4)
            .padding(.bottom, 8)
        }
        .padding(.bottom, 24)
    }

    // MARK: - Legal

    private var legalSection: some View {
        HStack(spacing: 20) {
            Button("Restore") { }
            Text("·").foregroundStyle(Brand.textTertiary)
            Button("Privacy") { }
            Text("·").foregroundStyle(Brand.textTertiary)
            Button("Terms") { }
        }
        .font(.system(size: 12, weight: .regular, design: .rounded))
        .foregroundStyle(Brand.textTertiary)
        .padding(.bottom, 48)
    }

    // MARK: - Subscribe

    private func subscribe() {
        isSubscribing = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        // TODO: StoreKit integration
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            isSubscribing = false
            onComplete()
        }
    }
}

// MARK: - Paywall Plan

enum PaywallPlan: CaseIterable {
    case monthly, annual

    var title: String {
        switch self {
        case .monthly: return "Monthly"
        case .annual:  return "Annual"
        }
    }

    var subtitle: String {
        switch self {
        case .monthly: return "Billed every month"
        case .annual:  return "Billed once a year · best value"
        }
    }

    var price: String {
        switch self {
        case .monthly: return "$9.99/mo"
        case .annual:  return "$59.99/yr"
        }
    }
}

// MARK: - Paywall Feature

private struct PaywallFeature: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let description: String
    let color: Color

    static let all: [PaywallFeature] = [
        PaywallFeature(
            icon: "heart.fill",
            title: "Real-Time Mood Sync",
            description: "Always know how your partner is feeling.",
            color: Color(red: 1.0, green: 0.38, blue: 0.60)
        ),
        PaywallFeature(
            icon: "flame.fill",
            title: "Streak & Sync Score",
            description: "Track your daily connection and celebrate milestones.",
            color: Color(red: 1.0, green: 0.58, blue: 0.20)
        ),
        PaywallFeature(
            icon: "sparkles",
            title: "AI-Powered Suggestions",
            description: "Personalized messages and date ideas, just for you.",
            color: Color(red: 0.55, green: 0.40, blue: 1.0)
        ),
        PaywallFeature(
            icon: "bell.badge.fill",
            title: "Smart Nudges",
            description: "Gentle reminders to check in when it matters most.",
            color: Color(red: 0.25, green: 0.78, blue: 0.65)
        ),
    ]
}
