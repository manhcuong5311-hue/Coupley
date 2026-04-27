//
//  TogetherActiveSection.swift
//  Coupley
//
//  Section 2 of the Together tab: Active Goals + Active Challenges. Goals
//  and challenges are visually distinct so they don't blur into each other,
//  but they share the same TogetherCard chassis so the page reads as one
//  cohesive surface rather than two stacked features.
//
//  Premium gating: free users see a max of 2 goals and 1 challenge. Beyond
//  that, the "Add a goal" tile turns into a premium teaser.
//

import SwiftUI

// MARK: - Active Goals Section

struct ActiveGoalsSection: View {

    let goals: [TogetherGoal]
    let userId: String
    let isPremium: Bool
    let onSelect: (TogetherGoal) -> Void
    let onCreate: () -> Void
    let onShowPaywall: () -> Void

    private let freeLimit = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TogetherSectionTitle(
                "Active Goals",
                subtitle: "What you're working toward — together."
            ) {
                AnyView(
                    Button(action: handleAdd) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(Brand.accentGradient)
                                    .shadow(color: Brand.accentStart.opacity(0.30), radius: 8, y: 3)
                            )
                    }
                    .buttonStyle(BouncyButtonStyle(scale: 0.92))
                )
            }

            if goals.isEmpty {
                TogetherEmptySlot(
                    title: "Start your first goal",
                    subtitle: "A trip, a savings target, a habit. Pick one.",
                    icon: "target",
                    onTap: onCreate
                )
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(Array(goals.enumerated()), id: \.element.id) { index, goal in
                        let isLocked = !isPremium && index >= freeLimit
                        Group {
                            if isLocked {
                                // Render a translucent preview of the locked goal
                                ZStack {
                                    GoalProgressCard(
                                        goal: goal,
                                        userId: userId,
                                        onTap: { /* swallowed */ }
                                    )
                                    .blur(radius: 4)
                                    .opacity(0.55)
                                    .allowsHitTesting(false)

                                    PremiumLockOverlay(
                                        title: "More goals on Premium",
                                        subtitle: "Free includes 2 active goals. Unlock unlimited goals + financial planning.",
                                        onTap: onShowPaywall
                                    )
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            } else {
                                GoalProgressCard(
                                    goal: goal,
                                    userId: userId,
                                    onTap: { onSelect(goal) }
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    private func handleAdd() {
        let active = goals.filter { !$0.isComplete }.count
        if !isPremium && active >= freeLimit {
            onShowPaywall()
        } else {
            onCreate()
        }
    }
}

// MARK: - Goal Progress Card

struct GoalProgressCard: View {
    let goal: TogetherGoal
    let userId: String
    let onTap: () -> Void

    /// Animated progress so cards animate as data arrives.
    @State private var animatedProgress: Double = 0

    var body: some View {
        PressableContainer(onTap: onTap) {
            TogetherCard(tint: goal.colorway) {
                VStack(alignment: .leading, spacing: 14) {

                    // Header row — icon + title + status chip
                    HStack(alignment: .center, spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(goal.colorway.gradient)
                                .frame(width: 44, height: 44)
                                .shadow(color: goal.colorway.primary.opacity(0.45),
                                        radius: 8, y: 3)
                            Image(systemName: goal.category.icon)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(goal.title)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(Brand.textPrimary)
                                .lineLimit(1)
                            Text(goal.category.label)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(Brand.textSecondary)
                        }

                        Spacer()

                        progressBadge
                    }

                    // Progress bar
                    TogetherProgressBar(progress: animatedProgress, colorway: goal.colorway)

                    // Bottom row — split + estimated completion
                    HStack(alignment: .center, spacing: 10) {
                        contributionSplit

                        Spacer()

                        if let estimate = goal.estimatedCompletion(),
                           !goal.isComplete {
                            HStack(spacing: 5) {
                                Image(systemName: "clock")
                                    .font(.system(size: 10, weight: .semibold))
                                Text("Est. \(estimate.formatted(.dateTime.month(.abbreviated).year()))")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                            }
                            .foregroundStyle(Brand.textTertiary)
                        }
                    }
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.85).delay(0.1)) {
                animatedProgress = goal.progress
            }
        }
        .onChange(of: goal.progress) { _, new in
            withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) {
                animatedProgress = new
            }
        }
    }

    // MARK: - Subviews

    private var progressBadge: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text("\(Int(goal.progress * 100))%")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(goal.colorway.deep)
                .monospacedDigit()
            Text(goal.progressLabel)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Brand.textSecondary)
                .lineLimit(1)
        }
    }

    private var contributionSplit: some View {
        let total = goal.contribution.total
        return Group {
            if total > 0 {
                let myShare = Int(goal.contribution.share(for: userId) * 100)
                HStack(spacing: 8) {
                    CouplePairAvatar(
                        size: 18,
                        leading: goal.colorway.primary,
                        trailing: goal.colorway.deep
                    )
                    Text("You: \(myShare)% · Partner: \(100 - myShare)%")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)
                }
            } else {
                HStack(spacing: 8) {
                    CouplePairAvatar(
                        size: 18,
                        leading: goal.colorway.primary,
                        trailing: goal.colorway.deep
                    )
                    Text("Tap to start contributing")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)
                }
            }
        }
    }
}

// MARK: - Active Challenges Section

struct ActiveChallengesSection: View {

    let challenges: [CoupleChallenge]
    let userId: String
    let isPremium: Bool
    let onSelect: (CoupleChallenge) -> Void
    let onCheckIn: (CoupleChallenge) -> Void
    let onCreate: () -> Void
    let onShowPaywall: () -> Void

    private let freeLimit = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TogetherSectionTitle(
                "Couple Challenges",
                subtitle: "Daily check-ins. Streaks that mean something."
            ) {
                AnyView(
                    Button(action: handleAdd) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(Brand.accentGradient)
                                    .shadow(color: Brand.accentStart.opacity(0.30), radius: 8, y: 3)
                            )
                    }
                    .buttonStyle(BouncyButtonStyle(scale: 0.92))
                )
            }

            if challenges.isEmpty {
                TogetherEmptySlot(
                    title: "Start a couple challenge",
                    subtitle: "Gratitude. Gym. Date nights. A small daily \"yes.\"",
                    icon: "flame.fill",
                    onTap: onCreate
                )
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(Array(challenges.enumerated()), id: \.element.id) { index, challenge in
                        let isLocked = !isPremium && index >= freeLimit
                        Group {
                            if isLocked {
                                ZStack {
                                    ChallengeProgressCard(
                                        challenge: challenge,
                                        userId: userId,
                                        onTap: {},
                                        onCheckIn: {}
                                    )
                                    .blur(radius: 4)
                                    .opacity(0.55)
                                    .allowsHitTesting(false)

                                    PremiumLockOverlay(
                                        title: "More challenges on Premium",
                                        subtitle: "Free includes 1 active challenge. Unlock unlimited streaks together.",
                                        onTap: onShowPaywall
                                    )
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            } else {
                                ChallengeProgressCard(
                                    challenge: challenge,
                                    userId: userId,
                                    onTap: { onSelect(challenge) },
                                    onCheckIn: { onCheckIn(challenge) }
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    private func handleAdd() {
        let active = challenges.filter { !$0.isComplete }.count
        if !isPremium && active >= freeLimit {
            onShowPaywall()
        } else {
            onCreate()
        }
    }
}

// MARK: - Challenge Progress Card

struct ChallengeProgressCard: View {
    let challenge: CoupleChallenge
    let userId: String
    let onTap: () -> Void
    let onCheckIn: () -> Void

    @State private var animatedProgress: Double = 0
    @State private var checkInBouncing = false

    var body: some View {
        PressableContainer(onTap: onTap) {
            TogetherCard(tint: challenge.colorway) {
                VStack(alignment: .leading, spacing: 14) {

                    // Header
                    HStack(alignment: .center, spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(challenge.colorway.gradient)
                                .frame(width: 44, height: 44)
                                .shadow(color: challenge.colorway.primary.opacity(0.45),
                                        radius: 8, y: 3)
                            Image(systemName: challenge.category.icon)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(challenge.title)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(Brand.textPrimary)
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                Text(challenge.statusLine)
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(Brand.textSecondary)
                                if challenge.streak.current > 0 {
                                    Text("·")
                                        .foregroundStyle(Brand.textTertiary)
                                    StreakPill(streak: challenge.streak.current)
                                }
                            }
                        }

                        Spacer()

                        Text("\(Int(challenge.progress * 100))%")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(challenge.colorway.deep)
                            .monospacedDigit()
                    }

                    TogetherProgressBar(progress: animatedProgress, colorway: challenge.colorway)

                    // Check-in CTA
                    HStack {
                        contributionSplit

                        Spacer()

                        checkInButton
                    }
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.85).delay(0.1)) {
                animatedProgress = challenge.progress
            }
        }
        .onChange(of: challenge.progress) { _, new in
            withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) {
                animatedProgress = new
            }
        }
    }

    private var contributionSplit: some View {
        let total = challenge.contribution.total
        return Group {
            if total > 0 {
                let myShare = Int(challenge.contribution.share(for: userId) * 100)
                HStack(spacing: 8) {
                    CouplePairAvatar(
                        size: 18,
                        leading: challenge.colorway.primary,
                        trailing: challenge.colorway.deep
                    )
                    Text("You: \(myShare)% · Partner: \(100 - myShare)%")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)
                }
            } else {
                HStack(spacing: 8) {
                    CouplePairAvatar(
                        size: 18,
                        leading: challenge.colorway.primary,
                        trailing: challenge.colorway.deep
                    )
                    Text("First check-in starts your streak")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private var checkInButton: some View {
        let alreadyChecked = challenge.hasCheckedIn(for: userId)
        Button(action: {
            guard !alreadyChecked, challenge.hasStarted else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
                checkInBouncing = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                checkInBouncing = false
            }
            onCheckIn()
        }) {
            HStack(spacing: 6) {
                Image(systemName: alreadyChecked ? "checkmark" : "plus.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                Text(alreadyChecked ? "Done today" :
                        (challenge.hasStarted ? "Check in" : "Soon"))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(alreadyChecked
                          ? AnyShapeStyle(Color.white.opacity(0.18))
                          : AnyShapeStyle(challenge.colorway.gradient))
            )
            .overlay(
                Capsule().strokeBorder(.white.opacity(alreadyChecked ? 0.25 : 0), lineWidth: 1)
            )
            .shadow(color: alreadyChecked ? .clear : challenge.colorway.primary.opacity(0.4),
                    radius: 6, y: 2)
        }
        .buttonStyle(BouncyButtonStyle())
        .scaleEffect(checkInBouncing ? 1.10 : 1.0)
        .disabled(alreadyChecked || !challenge.hasStarted)
    }
}
