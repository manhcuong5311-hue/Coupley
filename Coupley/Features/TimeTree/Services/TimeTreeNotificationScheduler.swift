//
//  TimeTreeNotificationScheduler.swift
//  Coupley
//
//  Local notifications for the Time Tree:
//   - Capsule unlock day (fires at 09:00 the morning the capsule unlocks)
//   - Crown milestone reached (100 days, 1 year, etc.) — fires at 09:00
//     on the day the milestone is reached, computed from the anchor.
//
//  Both flavors are reconciled on every app foreground / data change so
//  partner-side edits and OS-dropped requests heal themselves without
//  manual intervention.
//

import Foundation
import UserNotifications

// MARK: - Protocol

protocol TimeTreeNotificationScheduling {
    func rescheduleCapsule(_ memory: TimeMemory) async
    func cancelCapsule(_ memoryId: String) async
    func rescheduleCrowns(anchor: RelationshipAnchor) async
    func cancelAllCrowns() async
    func cancelAll() async
}

// MARK: - Scheduler

final class TimeTreeNotificationScheduler: TimeTreeNotificationScheduling {

    private let center = UNUserNotificationCenter.current()
    private let fireHour: Int

    private let capsulePrefix = "tt.capsule."
    private let crownPrefix   = "tt.crown."

    init(fireHour: Int = 9) {
        self.fireHour = fireHour
    }

    // MARK: - Capsule

    func rescheduleCapsule(_ memory: TimeMemory) async {
        await cancelCapsule(memory.id)

        guard let unlockDate = memory.unlockDate, unlockDate > Date() else { return }

        let calendar = Calendar.current
        let day = calendar.startOfDay(for: unlockDate)
        guard let fireDate = calendar.date(bySettingHour: fireHour, minute: 0, second: 0, of: day) else { return }
        guard fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "A capsule is ready ✨"
        content.body = memory.title.isEmpty
            ? "Your Time Tree has a memory waiting to be opened."
            : "“\(memory.title)” is unlocking today."
        content.sound = .default
        content.userInfo = [
            "type": "timeTreeCapsule",
            "memoryId": memory.id
        ]

        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(
            identifier: capsuleIdentifier(for: memory.id),
            content: content,
            trigger: trigger
        )

        try? await center.add(request)
    }

    func cancelCapsule(_ memoryId: String) async {
        center.removePendingNotificationRequests(withIdentifiers: [capsuleIdentifier(for: memoryId)])
    }

    // MARK: - Crown Milestones

    func rescheduleCrowns(anchor: RelationshipAnchor) async {
        await cancelAllCrowns()

        let now = Date()
        let calendar = Calendar.current

        for milestone in CrownMilestone.ladder {
            let day = calendar.startOfDay(for: milestone.date(anchor: anchor.startDate, calendar: calendar))
            guard let fireDate = calendar.date(bySettingHour: fireHour, minute: 0, second: 0, of: day) else { continue }
            guard fireDate > now else { continue }

            let content = UNMutableNotificationContent()
            content.title = "\(milestone.displayTitle) together 👑"
            content.body  = milestone.celebrationSubtitle
            content.sound = .default
            content.userInfo = [
                "type": "timeTreeCrown",
                "milestoneId": milestone.id
            ]

            let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(
                identifier: crownIdentifier(for: milestone.id),
                content: content,
                trigger: trigger
            )

            try? await center.add(request)
        }
    }

    func cancelAllCrowns() async {
        let pending = await center.pendingNotificationRequests()
        let ids = pending.filter { $0.identifier.hasPrefix(crownPrefix) }.map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: - Cancel All

    func cancelAll() async {
        let pending = await center.pendingNotificationRequests()
        let ids = pending
            .filter { $0.identifier.hasPrefix(capsulePrefix) || $0.identifier.hasPrefix(crownPrefix) }
            .map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: - Identifiers

    private func capsuleIdentifier(for memoryId: String) -> String {
        capsulePrefix + memoryId
    }

    private func crownIdentifier(for milestoneId: String) -> String {
        crownPrefix + milestoneId
    }
}
