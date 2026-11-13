//
//  TimeTreeNotificationScheduler.swift
//  Coupley
//
//  Journey's local reminders:
//   - A capsule opening. It fires at the capsule's unlock moment itself, so
//     "it's open" is true when it arrives: 9:00 local on the chosen day for
//     capsules sealed since unlocks became calendar days, the stored time
//     for older ones.
//   - A crown milestone (100 days, 1 year, …) at 9:00 local on the day it is
//     reached, for the next three only.
//
//  WidgetSyncService owns them for the whole paired session: its anchor and
//  memory listeners outlive the Journey tab, so a partner's new capsule or a
//  changed start date is scheduled even if Journey is never opened on this
//  phone. Leaving the paired state calls `cancelAll()`.
//
//  Every request carries `JourneyNotification`'s userInfo, which
//  NotificationViewModel turns back into a `JourneyFocus` when it is tapped.
//

import Foundation
import UserNotifications

// MARK: - Protocol

protocol TimeTreeNotificationScheduling {
    /// Schedules (or replaces) one capsule's reminder at its unlock moment,
    /// and removes it once that moment is well past (one iOS is delivering
    /// right now stays).
    func rescheduleCapsule(_ memory: TimeMemory) async
    /// Removes one capsule's reminder, pending and delivered.
    func cancelCapsule(_ memoryId: String) async
    /// Makes the capsule reminders match `memories`, the whole collection:
    /// the soonest future unlocks are scheduled (at most
    /// `TimeTreeNotificationScheduler.maxCapsules`), pending ones no longer
    /// wanted are removed, and delivered ones whose memory is gone (or
    /// sealed again) are cleared.
    func reconcileCapsules(_ memories: [TimeMemory]) async
    /// Replaces the crown reminders with the next
    /// `TimeTreeNotificationScheduler.maxCrowns` milestones.
    func rescheduleCrowns(anchor: RelationshipAnchor) async
    /// Removes pending crown reminders.
    func cancelAllCrowns() async
    /// Removes every capsule and crown reminder, pending AND delivered.
    func cancelAll() async
}

// MARK: - Scheduler

final class TimeTreeNotificationScheduler: TimeTreeNotificationScheduling {

    /// iOS keeps only the 64 soonest pending requests, and letters, crowns,
    /// capsules, Together and micro actions share that budget.
    static let maxCapsules = 20
    static let maxCrowns = 3

    private static let capsulePrefix = "tt.capsule."
    private static let crownPrefix   = "tt.crown."

    /// How long after its unlock a capsule's request is still left alone:
    /// iOS is delivering it, or already has. Removing it at that moment
    /// would drop the one reminder this exists to show.
    private static let deliveryGrace: TimeInterval = 60

    private let center = UNUserNotificationCenter.current()
    /// The crowns' hour. Capsules fire at their own unlock moment.
    private let fireHour: Int

    init(fireHour: Int = JourneyCalendarDay.reminderHour) {
        self.fireHour = fireHour
    }

    // MARK: - Capsules

    func rescheduleCapsule(_ memory: TimeMemory) async {
        if let unlockDate = memory.unlockDate,
           unlockDate > Date().addingTimeInterval(-Self.deliveryGrace) {
            // Adding replaces the pending request with the same identifier;
            // a moment a second away or less keeps the one iOS is delivering.
            await addCapsuleReminder(for: memory, unlockDate: unlockDate)
        } else {
            center.removePendingNotificationRequests(withIdentifiers: [Self.capsuleIdentifier(for: memory.id)])
        }
    }

    func cancelCapsule(_ memoryId: String) async {
        let identifier = Self.capsuleIdentifier(for: memoryId)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    func reconcileCapsules(_ memories: [TimeMemory]) async {
        let now = Date()
        let wanted = Array(
            memories
                .compactMap { memory in memory.unlockDate.map { (memory: memory, unlock: $0) } }
                .filter { $0.unlock > now }
                .sorted { $0.unlock < $1.unlock }
                .prefix(Self.maxCapsules)
        )
        let justOpened = memories.filter { memory in
            guard let unlock = memory.unlockDate else { return false }
            return unlock <= now && unlock > now.addingTimeInterval(-Self.deliveryGrace)
        }
        let keepIds = Set((wanted.map { $0.memory } + justOpened).map { Self.capsuleIdentifier(for: $0.id) })

        let pending = await center.pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix(Self.capsulePrefix) }
        let stale = pending.map(\.identifier).filter { !keepIds.contains($0) }
        if !stale.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: stale)
        }

        // "A capsule just opened" for a memory deleted since, or sealed again
        // (its unlock moved back into the future): tapping it would open
        // nothing, or a capsule that is still closed.
        let delivered = await center.deliveredNotifications()
            .map(\.request.identifier)
            .filter { $0.hasPrefix(Self.capsulePrefix) }
        if !delivered.isEmpty {
            // Measured after the fetch: everything in it has already fired.
            let checkedAt = Date()
            let openIds = Set(memories
                .filter { ($0.unlockDate ?? .distantPast) <= checkedAt }
                .map { Self.capsuleIdentifier(for: $0.id) })
            let staleDelivered = delivered.filter { !openIds.contains($0) }
            if !staleDelivered.isEmpty {
                center.removeDeliveredNotifications(withIdentifiers: staleDelivered)
            }
        }

        let pendingById = Dictionary(pending.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
        for entry in wanted {
            let copy = Self.capsuleCopy(for: entry.memory)
            // Already scheduled for this moment with this text: leave it. An
            // interval trigger's nextTriggerDate() counts from now, not from
            // when it was added, so this matches only a request added in the
            // last second (a burst of snapshots). An older one is replaced,
            // which keeps the same instant.
            if let existing = pendingById[Self.capsuleIdentifier(for: entry.memory.id)],
               existing.content.title == copy.title,
               existing.content.body == copy.body,
               let fireDate = (existing.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate(),
               abs(fireDate.timeIntervalSince(entry.unlock)) <= 1 {
                continue
            }
            // A sign-out or disconnect cancels this task: nothing is added
            // after it.
            guard !Task.isCancelled else { return }
            await addCapsuleReminder(for: entry.memory, unlockDate: entry.unlock)
        }
    }

    /// Adds (or replaces) one capsule's request, firing at `unlockDate`.
    /// Skipped when that moment is a second away or less, and once the
    /// calling task is cancelled.
    private func addCapsuleReminder(for memory: TimeMemory, unlockDate: Date) async {
        // Measured right before the add: the awaits before it take time.
        let interval = unlockDate.timeIntervalSinceNow
        guard interval > 1, !Task.isCancelled else { return }

        let copy = Self.capsuleCopy(for: memory)
        let content = UNMutableNotificationContent()
        content.title = copy.title
        content.body = copy.body
        content.sound = .default
        content.threadIdentifier = JourneyNotification.threadIdentifier
        content.userInfo = [
            JourneyNotification.typeKey: JourneyNotification.capsuleType,
            JourneyNotification.memoryIdKey: memory.id,
            // Local notifications have no `aps`; NotificationViewModel reads
            // the text of its in-app list from here.
            JourneyNotification.bodyKey: copy.body
        ]

        // An interval, not calendar components: a capsule opens at one
        // absolute instant for both partners, wherever this phone travels.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: Self.capsuleIdentifier(for: memory.id),
                                            content: content,
                                            trigger: trigger)
        try? await center.add(request)
    }

    /// The title is shown on a sealed capsule's card too, so it may appear
    /// on the lock screen; the note never does.
    private static func capsuleCopy(for memory: TimeMemory) -> (title: String, body: String) {
        let name = memory.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = name.isEmpty
            ? "A memory you sealed together is ready on Journey."
            : "“\(name)” is ready to read on Journey."
        return (title: "A capsule just opened ✨", body: body)
    }

    // MARK: - Crown Milestones

    func rescheduleCrowns(anchor: RelationshipAnchor) async {
        await cancelAllCrowns()

        let now = Date()
        let calendar = Calendar.current
        let upcoming = CrownMilestone.ladder
            .compactMap { milestone -> (milestone: CrownMilestone, fireDate: Date)? in
                // `date(anchor:)` names the milestone's calendar day.
                let day = calendar.startOfDay(for: milestone.date(anchor: anchor.startDate, calendar: calendar))
                guard let fireDate = calendar.date(bySettingHour: fireHour, minute: 0, second: 0, of: day),
                      fireDate > now else { return nil }
                return (milestone: milestone, fireDate: fireDate)
            }
            .sorted { $0.fireDate < $1.fireDate }
            .prefix(Self.maxCrowns)

        for crown in upcoming {
            guard !Task.isCancelled else { return }

            let body = crown.milestone.celebrationSubtitle
            let content = UNMutableNotificationContent()
            content.title = "\(crown.milestone.displayTitle) together 👑"
            content.body = body
            content.sound = .default
            content.threadIdentifier = JourneyNotification.threadIdentifier
            content.userInfo = [
                JourneyNotification.typeKey: JourneyNotification.crownType,
                JourneyNotification.milestoneIdKey: crown.milestone.id,
                JourneyNotification.bodyKey: body
            ]

            // Calendar components without a time zone: 9:00 wherever the
            // phone is that morning.
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: crown.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: Self.crownIdentifier(for: crown.milestone.id),
                                                content: content,
                                                trigger: trigger)
            try? await center.add(request)
        }
    }

    func cancelAllCrowns() async {
        let ids = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.crownPrefix) }
        if !ids.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    // MARK: - Cancel All

    func cancelAll() async {
        let pending = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.capsulePrefix) || $0.hasPrefix(Self.crownPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)

        let delivered = await center.deliveredNotifications()
            .map(\.request.identifier)
            .filter { $0.hasPrefix(Self.capsulePrefix) || $0.hasPrefix(Self.crownPrefix) }
        center.removeDeliveredNotifications(withIdentifiers: delivered)
    }

    // MARK: - Identifiers

    private static func capsuleIdentifier(for memoryId: String) -> String {
        capsulePrefix + memoryId
    }

    private static func crownIdentifier(for milestoneId: String) -> String {
        crownPrefix + milestoneId
    }
}
