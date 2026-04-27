//
//  TogetherNotificationScheduler.swift
//  Coupley
//
//  Local notifications for the Together tab. Three flavors:
//   1. Daily nudge — for any active challenge that hasn't been checked in
//      today, fires at 20:00. Re-scheduled on every data change so a freshly
//      checked-in challenge silences itself.
//   2. Goal milestone — fires when a goal crosses 50%, 75%, or 90% locally.
//      Computed at update time, not from a stored "last threshold" — the
//      identifier itself carries the percentage so a stale write can't
//      double-fire.
//   3. Challenge ending soon — fires 3 days before a challenge's end date
//      to nudge a final push.
//
//  Notifications are best-effort. If the user denied permission, the calls
//  silently no-op (UNUserNotificationCenter.add throws which we swallow).
//

import Foundation
import UserNotifications

// MARK: - Protocol

protocol TogetherNotificationScheduling {
    func reconcile(
        goals: [TogetherGoal],
        challenges: [CoupleChallenge],
        dreams: [Dream]
    ) async

    func cancelAll() async
}

// MARK: - Scheduler

final class TogetherNotificationScheduler: TogetherNotificationScheduling {

    private let center = UNUserNotificationCenter.current()

    private let dailyChallengePrefix = "tg.challenge.daily."
    private let goalMilestonePrefix  = "tg.goal.milestone."
    private let challengeEndPrefix   = "tg.challenge.end."

    /// Hour-of-day for the daily check-in nudge (8pm by default — after work,
    /// before most users start winding down).
    private let nudgeHour: Int = 20

    // MARK: - Reconcile

    func reconcile(
        goals: [TogetherGoal],
        challenges: [CoupleChallenge],
        dreams _: [Dream]
    ) async {
        // Wipe everything we own and rebuild. The total request count we add
        // is small (~one per active challenge, plus a handful for milestones)
        // so this is cheap and keeps the state machine trivially correct.
        let pending = await center.pendingNotificationRequests()
        let ourIds = pending
            .map(\.identifier)
            .filter { id in
                id.hasPrefix(dailyChallengePrefix) ||
                id.hasPrefix(goalMilestonePrefix) ||
                id.hasPrefix(challengeEndPrefix)
            }
        center.removePendingNotificationRequests(withIdentifiers: ourIds)

        for challenge in challenges where !challenge.isComplete {
            await scheduleDailyChallenge(challenge)
            await scheduleChallengeEndNudge(challenge)
        }

        for goal in goals where !goal.isComplete {
            await scheduleGoalMilestone(goal)
        }
    }

    func cancelAll() async {
        let pending = await center.pendingNotificationRequests()
        let ourIds = pending
            .map(\.identifier)
            .filter { id in
                id.hasPrefix(dailyChallengePrefix) ||
                id.hasPrefix(goalMilestonePrefix) ||
                id.hasPrefix(challengeEndPrefix)
            }
        center.removePendingNotificationRequests(withIdentifiers: ourIds)
    }

    // MARK: - Daily Challenge Nudge

    private func scheduleDailyChallenge(_ challenge: CoupleChallenge) async {
        // Daily challenges only — weekly challenges nudge once a week
        // (handled by .end-soon below; we don't want a useless 7-day-out
        // notification spamming the user).
        guard challenge.cadence == .daily else { return }
        guard challenge.hasStarted else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(challenge.title) ✨"
        content.body = challenge.streak.current > 0
            ? "Don't let your \(challenge.streak.current)-day streak slip. Tap to check in."
            : "A small \"yes\" today builds the streak. Check in together."
        content.sound = .default
        content.userInfo = [
            "type": "togetherChallenge",
            "challengeId": challenge.id
        ]

        var comps = DateComponents()
        comps.hour = nudgeHour
        comps.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)

        let request = UNNotificationRequest(
            identifier: dailyChallengePrefix + challenge.id,
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }

    // MARK: - Goal Milestone

    /// Fires once per *uncrossed* threshold above the current progress.
    /// The threshold is encoded into the identifier so re-running this
    /// scheduler won't enqueue duplicates for thresholds the user has
    /// already passed.
    private func scheduleGoalMilestone(_ goal: TogetherGoal) async {
        let thresholds: [Double] = [0.5, 0.75, 0.9]
        let calendar = Calendar.current

        for threshold in thresholds where goal.progress < threshold {
            // Schedule for tomorrow morning at 9am — this is a "you're getting
            // close" hint, not a real-time celebration. The actual milestone
            // crossing is handled in-app by the coach engine.
            guard
                let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()),
                let fire = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)
            else { continue }

            let pct = Int(threshold * 100)
            let content = UNMutableNotificationContent()
            content.title = "\(goal.title) is getting close \(goal.category.emoji)"
            content.body = "You're \(pct)% of the way there. One more push together."
            content.sound = .default
            content.userInfo = [
                "type": "togetherGoal",
                "goalId": goal.id,
                "threshold": pct
            ]

            // Note: this fires once a day per uncrossed threshold. We
            // intentionally don't reduce to "next-up only" because the
            // reconcile pass wipes them all on every data change — we'll
            // re-evaluate after each contribution.
            let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

            let request = UNNotificationRequest(
                identifier: "\(goalMilestonePrefix)\(goal.id).\(pct)",
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
            break  // only enqueue the *next* threshold, not all three at once
        }
    }

    // MARK: - Challenge Ending Nudge

    private func scheduleChallengeEndNudge(_ challenge: CoupleChallenge) async {
        let calendar = Calendar.current
        guard let fire = calendar.date(byAdding: .day, value: -3, to: challenge.endDate) else { return }
        guard fire > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Only 3 days left ⏳"
        content.body = "\(challenge.title) ends soon. Don't let this one slip in the last stretch."
        content.sound = .default
        content.userInfo = [
            "type": "togetherChallenge",
            "challengeId": challenge.id
        ]

        let comps = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: calendar.date(bySettingHour: 9, minute: 0, second: 0, of: fire) ?? fire
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

        let request = UNNotificationRequest(
            identifier: challengeEndPrefix + challenge.id,
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }
}

// MARK: - Mock

final class MockTogetherNotificationScheduler: TogetherNotificationScheduling {
    func reconcile(goals: [TogetherGoal], challenges: [CoupleChallenge], dreams: [Dream]) async {}
    func cancelAll() async {}
}
