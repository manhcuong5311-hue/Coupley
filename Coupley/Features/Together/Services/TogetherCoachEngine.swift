//
//  TogetherCoachEngine.swift
//  Coupley
//
//  Pure-Swift engine that turns the user's goals/challenges/dreams into a
//  prioritized list of premium-feeling insights. Deterministic — same inputs
//  produce the same outputs — so we can swap in an LLM later without breaking
//  the surface area.
//
//  Design choices worth flagging:
//   • We never generate >5 insights. Coach cards are about *meaningful* nudges,
//     not exhaustive analysis. The engine over-generates and the view model
//     trims to top-N by weight.
//   • Insights are deduplicated by `id` — derived from category + subject — so
//     re-runs don't cause cards to flicker between two equivalent suggestions.
//   • The engine never reads the network or any user-identifying data outside
//     the inputs given. Easy to test, easy to reason about.
//

import Foundation

// MARK: - Engine

enum TogetherCoachEngine {

    /// Compute insights for the given inputs. `userId` is required so the
    /// engine can phrase contributions ("you've added 60% of this"). When the
    /// user is solo or unpaired, pass an empty string and the contribution
    /// math degrades gracefully.
    static func generate(
        goals: [TogetherGoal],
        challenges: [CoupleChallenge],
        dreams: [Dream],
        userId: String,
        now: Date = Date()
    ) -> [TogetherInsight] {

        var insights: [TogetherInsight] = []

        insights.append(contentsOf: goalInsights(goals: goals, userId: userId, now: now))
        insights.append(contentsOf: challengeInsights(challenges: challenges, now: now))
        insights.append(contentsOf: dreamInsights(dreams: dreams, goals: goals, now: now))
        insights.append(contentsOf: globalInsights(
            goals: goals, challenges: challenges, dreams: dreams, now: now
        ))

        // Sort highest-weight first, dedupe by id, cap at 6.
        var seen: Set<String> = []
        let trimmed = insights
            .sorted { $0.weight > $1.weight }
            .filter { seen.insert($0.id).inserted }
            .prefix(6)

        return Array(trimmed)
    }

    // MARK: - Stats Snapshot

    static func computeStats(
        goals: [TogetherGoal],
        challenges: [CoupleChallenge],
        dreams: [Dream],
        now: Date = Date()
    ) -> TogetherStats {
        let active = goals.filter { !$0.isComplete }
        let activeChallenges = challenges.filter { !$0.isComplete }

        let leading = active.max(by: { $0.progress < $1.progress })
        let overallProgress: Double = {
            guard !active.isEmpty else { return 0 }
            return active.map(\.progress).reduce(0, +) / Double(active.count)
        }()

        let longestStreak = activeChallenges.map { $0.streak.current }.max() ?? 0

        let calendar = Calendar.current
        let activityToday = activeChallenges.contains { ch in
            ch.checkInLog.contains { calendar.isDate($0, inSameDayAs: now) }
        } || active.contains { goal in
            calendar.isDate(goal.updatedAt, inSameDayAs: now)
        }

        return TogetherStats(
            activeGoalCount: active.count,
            activeChallengeCount: activeChallenges.count,
            dreamCount: dreams.count,
            longestActiveStreak: longestStreak,
            leadingGoalTitle: leading?.title,
            leadingGoalProgress: leading?.progress,
            overallProgress: overallProgress,
            hasActivityToday: activityToday
        )
    }

    // MARK: - Goal Insights

    private static func goalInsights(
        goals: [TogetherGoal],
        userId: String,
        now: Date
    ) -> [TogetherInsight] {
        var out: [TogetherInsight] = []

        for goal in goals where !goal.isComplete {

            // 80%+ → celebrate
            if goal.progress >= 0.8 {
                out.append(TogetherInsight(
                    id: "goal-near-\(goal.id)",
                    tone: .celebrate,
                    category: .progress,
                    title: "Your \(goal.title) goal is \(Int(goal.progress * 100))% complete \(goal.category.emoji)",
                    detail: "You're so close. One more push from both of you.",
                    action: .openGoal(id: goal.id),
                    weight: 90 + Int(goal.progress * 10)
                ))
            }
            // 50–79% → encourage
            else if goal.progress >= 0.5 {
                out.append(TogetherInsight(
                    id: "goal-half-\(goal.id)",
                    tone: .encourage,
                    category: .progress,
                    title: "\(goal.title) is past halfway",
                    detail: "You've crossed the middle. The second half is where dreams turn real.",
                    action: .openGoal(id: goal.id),
                    weight: 70
                ))
            }
            // No movement in 14d → nudge
            else if now.timeIntervalSince(goal.updatedAt) > 60 * 60 * 24 * 14 {
                out.append(TogetherInsight(
                    id: "goal-stalled-\(goal.id)",
                    tone: .nudge,
                    category: .progress,
                    title: "\(goal.title) hasn't moved in two weeks",
                    detail: "Even a small step counts. Add a contribution to keep the momentum.",
                    action: .openGoal(id: goal.id),
                    weight: 60
                ))
            }

            // Contribution imbalance — only when paired AND meaningful total.
            if !userId.isEmpty && goal.contribution.total >= goal.target * 0.2 {
                let myShare = goal.contribution.share(for: userId)
                if myShare < 0.3 {
                    out.append(TogetherInsight(
                        id: "goal-balance-low-\(goal.id)",
                        tone: .suggest,
                        category: .emotional,
                        title: "Your partner is leading on \(goal.title)",
                        detail: "A balanced contribution makes the win feel mutual. Add a little when you can.",
                        action: .openGoal(id: goal.id),
                        weight: 55
                    ))
                } else if myShare > 0.7 {
                    out.append(TogetherInsight(
                        id: "goal-balance-high-\(goal.id)",
                        tone: .suggest,
                        category: .emotional,
                        title: "You're carrying \(goal.title)",
                        detail: "Invite your partner in — even a small contribution makes this *theirs* too.",
                        action: .openGoal(id: goal.id),
                        weight: 50
                    ))
                }
            }
        }

        return out
    }

    // MARK: - Challenge Insights

    private static func challengeInsights(
        challenges: [CoupleChallenge],
        now: Date
    ) -> [TogetherInsight] {
        var out: [TogetherInsight] = []

        for ch in challenges where !ch.isComplete && ch.hasStarted {
            // Hot streak — celebrate every 7-day milestone
            if ch.streak.current >= 7 && ch.streak.current % 7 == 0 {
                out.append(TogetherInsight(
                    id: "ch-streak-\(ch.id)-\(ch.streak.current)",
                    tone: .celebrate,
                    category: .consistency,
                    title: "You're on a \(ch.streak.current)-day \(ch.category.label.lowercased()) streak \(ch.category.emoji)",
                    detail: "Consistency is the rarest thing. You're doing the rare thing together.",
                    action: .openChallenge(id: ch.id),
                    weight: 85
                ))
            }

            // Almost-done
            if ch.progress >= 0.8 && ch.progress < 1.0 {
                let remaining = ch.targetCount - ch.totalCheckIns
                out.append(TogetherInsight(
                    id: "ch-near-\(ch.id)",
                    tone: .encourage,
                    category: .progress,
                    title: "Only \(remaining) \(ch.cadence == .daily ? "days" : "weeks") left on \(ch.title)",
                    detail: "You've come this far. Don't let this one slip in the last stretch.",
                    action: .openChallenge(id: ch.id),
                    weight: 75
                ))
            }

            // Streak just broke — yesterday had no check-in but earlier days did
            if !ch.streak.isAlive(at: now) && ch.totalCheckIns > 0 {
                out.append(TogetherInsight(
                    id: "ch-restart-\(ch.id)",
                    tone: .nudge,
                    category: .habit,
                    title: "\(ch.title) needs a check-in",
                    detail: "Streaks break. Restarting is the part that counts.",
                    action: .openChallenge(id: ch.id),
                    weight: 65
                ))
            }

            // Hasn't checked in today (live streak still alive)
            if ch.streak.isAlive(at: now) && !ch.streak.didCheckInToday(at: now) {
                out.append(TogetherInsight(
                    id: "ch-today-\(ch.id)",
                    tone: .encourage,
                    category: .habit,
                    title: "Don't let \(ch.title) skip today",
                    detail: "Tap to check in and keep the \(ch.streak.current)-day streak alive.",
                    action: .openChallenge(id: ch.id),
                    weight: 80
                ))
            }
        }

        return out
    }

    // MARK: - Dream Insights

    private static func dreamInsights(
        dreams: [Dream],
        goals: [TogetherGoal],
        now: Date
    ) -> [TogetherInsight] {
        var out: [TogetherInsight] = []

        // Dream → Goal bridge: a "this year" or "next year" dream without a
        // matching goal is a conversion opportunity.
        for dream in dreams where dream.horizon == .thisYear || dream.horizon == .nextYear {
            let hasMatchingGoal = goals.contains { goal in
                goal.title.localizedCaseInsensitiveContains(dream.title) ||
                dream.title.localizedCaseInsensitiveContains(goal.title)
            }
            if !hasMatchingGoal {
                out.append(TogetherInsight(
                    id: "dream-bridge-\(dream.id)",
                    tone: .suggest,
                    category: .dream,
                    title: "Turn \(dream.title) into a real plan",
                    detail: "It's \(dream.horizon.shortLabel.lowercased()). Setting a goal makes it inevitable.",
                    action: .openDream(id: dream.id),
                    weight: 50
                ))
            }
        }

        return out
    }

    // MARK: - Global Insights

    private static func globalInsights(
        goals: [TogetherGoal],
        challenges: [CoupleChallenge],
        dreams: [Dream],
        now: Date
    ) -> [TogetherInsight] {
        var out: [TogetherInsight] = []

        // Brand-new user: nothing exists yet.
        if goals.isEmpty && challenges.isEmpty && dreams.isEmpty {
            out.append(TogetherInsight(
                id: "empty-start",
                tone: .suggest,
                category: .emotional,
                title: "What are you building together?",
                detail: "Add a dream or set a shared goal — even a small one starts the story.",
                action: .createDream(suggestion: "Japan Together"),
                weight: 100
            ))
            return out
        }

        // No active challenges
        if challenges.isEmpty || challenges.allSatisfy({ $0.isComplete }) {
            out.append(TogetherInsight(
                id: "empty-challenge",
                tone: .suggest,
                category: .habit,
                title: "Start a challenge together",
                detail: "Daily check-ins build the small habits long-term love is made of.",
                action: .createChallenge(suggestion: "14 Days of Gratitude"),
                weight: 40
            ))
        }

        // No dreams
        if dreams.isEmpty {
            out.append(TogetherInsight(
                id: "empty-dream",
                tone: .suggest,
                category: .dream,
                title: "Your dream board is waiting",
                detail: "What do you want your life together to look like? Start with one.",
                action: .createDream(suggestion: "Japan Together"),
                weight: 35
            ))
        }

        // Many active goals — encourage focus
        let activeGoals = goals.filter { !$0.isComplete }
        if activeGoals.count >= 5 {
            out.append(TogetherInsight(
                id: "focus-many-goals",
                tone: .suggest,
                category: .emotional,
                title: "You're tracking \(activeGoals.count) goals",
                detail: "Focus is a love language. Picking one to lead with usually moves them all.",
                action: nil,
                weight: 30
            ))
        }

        return out
    }
}
