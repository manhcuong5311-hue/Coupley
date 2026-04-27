//
//  TogetherCoachSection.swift
//  Coupley
//
//  Section 4 — the AI Couple Coach. Premium-coded by design: the section has
//  a gold accent crown, a pearl-on-ink card aesthetic, and a tighter visual
//  rhythm than the rest of the page. Free users see two soft preview lines
//  with the body blurred — the conversion moment.
//

import SwiftUI

// MARK: - Coach Section

struct CoupleCoachSection: View {

    let insights: [TogetherInsight]
    let stats: TogetherStats
    let isPremium: Bool
    let onAction: (InsightAction) -> Void
    let onShowPaywall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(coachAccent)
                        Text("AI Couple Coach")
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .foregroundStyle(Brand.textPrimary)
                        if !isPremium {
                            PremiumBadge(compact: true)
                                .scaleEffect(0.9)
                        }
                    }
                    Text(headerSubtitle)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            // Body
            if isPremium {
                premiumCoach
            } else {
                lockedCoach
            }
        }
    }

    // MARK: - Header subtitle

    private var headerSubtitle: String {
        if !isPremium {
            return "Private insights that read your patterns and recommend the right next move."
        }
        if let leading = stats.leadingGoalTitle, let progress = stats.leadingGoalProgress {
            return "\(leading) — \(Int(progress * 100))% of the way. Here's what the patterns say."
        }
        if stats.longestActiveStreak > 0 {
            return "On a \(stats.longestActiveStreak)-day streak. Here's what to watch."
        }
        return "Private insights tuned to the rhythms of you two."
    }

    // MARK: - Premium

    private var premiumCoach: some View {
        VStack(spacing: 12) {
            // Hero stat card
            statHero
                .padding(.bottom, 2)

            // Insight cards
            if insights.isEmpty {
                emptyInsightCard
            } else {
                ForEach(insights.prefix(4)) { insight in
                    InsightCard(insight: insight, onAction: onAction)
                }
            }
        }
    }

    // MARK: - Stat Hero

    private var statHero: some View {
        TogetherCard(tint: nil, padding: 18) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(coachGoldGradient)
                        .frame(width: 52, height: 52)
                        .shadow(color: Color(red: 1.0, green: 0.7, blue: 0.2).opacity(0.45),
                                radius: 10, y: 4)
                    Image(systemName: "crown.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Your Couple Health")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                    Text(coachStatusLine)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(Int(stats.overallProgress * 100))%")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(coachAccent)
                        .monospacedDigit()
                    Text("overall")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(Brand.textTertiary)
                }
            }
        }
    }

    private var coachStatusLine: String {
        if stats.activeGoalCount == 0 && stats.activeChallengeCount == 0 {
            return "No signals yet — start a goal or a challenge for tailored insights."
        }
        if stats.hasActivityToday {
            return "Strong day. The couple coach noticed."
        }
        return "Patterns are forming. Keep the rhythm."
    }

    // MARK: - Empty insight card

    private var emptyInsightCard: some View {
        TogetherCard {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(coachAccent)
                Text("Insights appear as you build momentum together.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
        }
    }

    // MARK: - Locked

    private var lockedCoach: some View {
        ZStack(alignment: .topLeading) {
            // Two preview rows underneath, blurred
            VStack(spacing: 12) {
                ForEach(0..<2, id: \.self) { i in
                    InsightCard(
                        insight: previewInsight(i),
                        onAction: { _ in }
                    )
                }
            }
            .blur(radius: 5)
            .opacity(0.55)
            .allowsHitTesting(false)

            // Locked overlay
            VStack(spacing: 14) {
                Spacer(minLength: 8)
                ZStack {
                    Circle()
                        .fill(coachGoldGradient)
                        .frame(width: 64, height: 64)
                        .shadow(color: Color(red: 1.0, green: 0.7, blue: 0.2).opacity(0.45),
                                radius: 14, y: 6)
                    Image(systemName: "crown.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(spacing: 6) {
                    Text("Unlock the Couple Coach")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                    Text("Personalized insights that read your patterns and tell you the right next move — together.")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .padding(.horizontal, 24)
                }

                Button(action: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onShowPaywall()
                }) {
                    Text("Try Premium")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(
                            Capsule()
                                .fill(coachGoldGradient)
                                .shadow(color: Color(red: 1.0, green: 0.7, blue: 0.2).opacity(0.45),
                                        radius: 10, y: 3)
                        )
                }
                .buttonStyle(BouncyButtonStyle())

                Spacer(minLength: 8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                    )
            )
        }
    }

    private func previewInsight(_ index: Int) -> TogetherInsight {
        if index == 0 {
            return TogetherInsight(
                id: "preview-1",
                tone: .celebrate,
                category: .progress,
                title: "Your Japan Trip is 72% complete ✈️",
                detail: "You're so close. One more push from both of you.",
                action: nil,
                weight: 0
            )
        } else {
            return TogetherInsight(
                id: "preview-2",
                tone: .encourage,
                category: .consistency,
                title: "12-day gratitude streak together 🌿",
                detail: "Consistency is the rarest thing. You're doing the rare thing together.",
                action: nil,
                weight: 0
            )
        }
    }

    // MARK: - Tokens

    private var coachAccent: Color {
        Color(red: 0.92, green: 0.62, blue: 0.18)
    }

    private var coachGoldGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 1.00, green: 0.78, blue: 0.30),
                Color(red: 0.92, green: 0.50, blue: 0.18)
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }
}

// MARK: - Insight Card

struct InsightCard: View {

    let insight: TogetherInsight
    let onAction: (InsightAction) -> Void

    @State private var didAppear = false

    var body: some View {
        TogetherCard(tint: insight.tone.color) {
            HStack(alignment: .top, spacing: 14) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(insight.tone.color.gradient)
                        .frame(width: 38, height: 38)
                        .shadow(color: insight.tone.color.primary.opacity(0.35),
                                radius: 6, y: 2)
                    Image(systemName: insight.tone.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(insight.title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let detail = insight.detail {
                        Text(detail)
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(Brand.textSecondary)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let action = insight.action {
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onAction(action)
                        }) {
                            HStack(spacing: 5) {
                                Text(action.label)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .foregroundStyle(insight.tone.color.deep)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(insight.tone.color.primary.opacity(0.18))
                                    .overlay(Capsule().strokeBorder(insight.tone.color.primary.opacity(0.35), lineWidth: 0.5))
                            )
                        }
                        .buttonStyle(BouncyButtonStyle(scale: 0.96))
                        .padding(.top, 2)
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .opacity(didAppear ? 1 : 0)
        .offset(y: didAppear ? 0 : 8)
        .onAppear {
            withAnimation(.spring(response: 0.65, dampingFraction: 0.85)) {
                didAppear = true
            }
        }
    }
}
