//
//  TogetherTodayHero.swift
//  Coupley
//
//  The hero pane at the top of the Together tab. Mood: a panoramic, premium
//  "today" snapshot — overall progress, the leading goal, the longest active
//  streak, and a single AI-flavored line that ties it all together.
//
//  This card alone has to do *most* of the emotional work of the tab when
//  the user only opens the app for 8 seconds. Every detail in here is tuned
//  to make those 8 seconds feel like a luxury moment.
//

import SwiftUI

// MARK: - Today Hero

struct TogetherTodayHero: View {

    let stats: TogetherStats
    let headline: TogetherInsight?
    let leadingGoal: TogetherGoal?
    let longestStreakChallenge: CoupleChallenge?
    let onOpenLeadingGoal: () -> Void
    let onOpenLongestStreakChallenge: () -> Void
    let onTapHeadline: () -> Void

    @State private var ringProgress: Double = 0
    @State private var didAppear = false

    /// The hero's colorway tracks the leading goal's colorway when one
    /// exists, so the entire card subtly "belongs" to that dream. Falls back
    /// to a warm blossom when the user hasn't started anything.
    private var heroColorway: TogetherColorway {
        leadingGoal?.colorway ?? .blossom
    }

    var body: some View {
        ZStack {
            TogetherHeroBackground(colorway: heroColorway)

            VStack(alignment: .leading, spacing: 18) {

                // Top row — "Today Together" eyebrow + couple avatar
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Today Together")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .kerning(1.4)
                            .textCase(.uppercase)
                            .foregroundStyle(.white.opacity(0.78))

                        Text(greeting)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }

                    Spacer()

                    CouplePairAvatar(size: 26,
                                     leading: .white.opacity(0.95),
                                     trailing: heroColorway.deep.opacity(0.85))
                }

                // Headline insight (premium AI line)
                if let headline {
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onTapHeadline()
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: headline.tone.icon)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 26, height: 26)
                                .background(
                                    Circle().fill(.white.opacity(0.18))
                                )

                            Text(headline.title)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)

                            Spacer(minLength: 0)
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(.white.opacity(0.12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(BouncyButtonStyle(scale: 0.985))
                }

                // Stat tiles — progress ring + leading goal + streak
                HStack(alignment: .center, spacing: 12) {

                    // Progress ring
                    progressRing
                        .frame(width: 96, height: 96)

                    VStack(alignment: .leading, spacing: 8) {

                        if let leadingGoal {
                            Button(action: {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                onOpenLeadingGoal()
                            }) {
                                statTile(
                                    icon: leadingGoal.category.icon,
                                    title: leadingGoal.title,
                                    value: "\(Int(leadingGoal.progress * 100))%",
                                    accent: .white
                                )
                            }
                            .buttonStyle(BouncyButtonStyle(scale: 0.97))
                        } else {
                            statTile(
                                icon: "sparkles",
                                title: "Start a goal",
                                value: "0",
                                accent: .white
                            )
                        }

                        if let challenge = longestStreakChallenge, challenge.streak.current > 0 {
                            Button(action: {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                onOpenLongestStreakChallenge()
                            }) {
                                statTile(
                                    icon: "flame.fill",
                                    title: "\(challenge.title) streak",
                                    value: "\(challenge.streak.current)d",
                                    accent: .white
                                )
                            }
                            .buttonStyle(BouncyButtonStyle(scale: 0.97))
                        } else {
                            statTile(
                                icon: "flame.fill",
                                title: "No streak yet",
                                value: "0",
                                accent: .white.opacity(0.7)
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                // Foot row — "build our future" tagline
                HStack(spacing: 6) {
                    Image(systemName: "infinity")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Building our life together")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white.opacity(0.78))
                .padding(.top, 2)
            }
            .padding(22)
        }
        .frame(maxWidth: .infinity)
        .opacity(didAppear ? 1 : 0)
        .offset(y: didAppear ? 0 : 12)
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) {
                didAppear = true
            }
            // Animate the ring fill from 0 to actual once the user lands.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 1.1, dampingFraction: 0.85)) {
                    ringProgress = stats.overallProgress
                }
            }
        }
        .onChange(of: stats.overallProgress) { _, new in
            withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) {
                ringProgress = new
            }
        }
    }

    // MARK: - Progress Ring

    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.18), lineWidth: 10)

            Circle()
                .trim(from: 0, to: ringProgress)
                .stroke(.white, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))

            VStack(spacing: 0) {
                Text("\(Int(ringProgress * 100))%")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("together")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .kerning(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    // MARK: - Stat Tile

    private func statTile(icon: String, title: String, value: String, accent: Color) -> some View {
        TogetherGlassTile {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.20))
                        .frame(width: 28, height: 28)
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(1)
                    Text(value)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(accent)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Greeting Copy

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Good morning."
        case 12..<17: return "An afternoon together."
        case 17..<21: return "Slow evening together."
        default:      return "A quiet night together."
        }
    }
}

// MARK: - Compact Banner Variant (used when paired but no data yet)

struct TogetherEmptyHero: View {
    let onAddDream: () -> Void
    let onAddGoal: () -> Void

    var body: some View {
        ZStack {
            TogetherHeroBackground(colorway: .blossom)

            VStack(alignment: .leading, spacing: 14) {
                Text("Together")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .kerning(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.78))

                Text("What are you\nbuilding together?")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineSpacing(2)

                Text("Start with one thing — a dream you share, or a goal you both want.")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineSpacing(2)

                HStack(spacing: 10) {
                    Button(action: onAddGoal) {
                        Label("Add a goal", systemImage: "target")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                Capsule().fill(.white.opacity(0.20))
                                    .overlay(Capsule().strokeBorder(.white.opacity(0.30), lineWidth: 1))
                            )
                    }
                    .buttonStyle(BouncyButtonStyle())

                    Button(action: onAddDream) {
                        Label("Add a dream", systemImage: "sparkles")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                Capsule().fill(.white.opacity(0.20))
                                    .overlay(Capsule().strokeBorder(.white.opacity(0.30), lineWidth: 1))
                            )
                    }
                    .buttonStyle(BouncyButtonStyle())
                }
                .padding(.top, 4)
            }
            .padding(22)
        }
    }
}
