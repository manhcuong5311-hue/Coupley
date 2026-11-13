//
//  FutureLetterNotificationScheduler.swift
//  Coupley
//
//  "A letter for you is ready" reminders. They are scheduled on the
//  RECIPIENT's device from its own listener, because a device can only
//  schedule its own local notifications. The copy never carries anything
//  from the letter.
//

import Foundation
import UserNotifications

protocol FutureLetterNotificationScheduling {
    /// Makes the reminders match `lettersToMe`: adds the soonest unopened
    /// ones, removes pending ones no longer wanted, and clears delivered ones
    /// for letters since opened (here or on another device), unsent or purged.
    func reconcile(_ lettersToMe: [FutureLetter]) async
    /// Removes pending AND delivered reminders.
    func cancelAll() async
    func clearDelivered(letterId: String)
}

final class FutureLetterNotificationScheduler: FutureLetterNotificationScheduling {

    static let prefix = "fl.ready."
    /// iOS keeps only the 64 soonest pending requests, and anniversaries,
    /// crowns, capsules, Together and micro actions share that budget.
    static let maxPending = 8

    private let center = UNUserNotificationCenter.current()

    func reconcile(_ lettersToMe: [FutureLetter]) async {
        let now = Date()
        let unopened = lettersToMe.filter { $0.openedAt == nil }
        let wanted = Array(
            unopened
                .filter { $0.opensAt > now }
                .sorted { $0.opensAt < $1.opensAt }
                .prefix(Self.maxPending)
        )
        // A letter that has just reached its moment keeps its request: iOS is
        // delivering it, or already has. Removing it here, at the flip, would
        // drop the one reminder this feature exists to show.
        let keepIds = Set((wanted + unopened.filter { $0.opensAt <= now }).map { Self.prefix + $0.id })

        let stale = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.prefix) && !keepIds.contains($0) }
        if !stale.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: stale)
        }

        let unopenedIds = Set(unopened.map { Self.prefix + $0.id })
        let staleDelivered = await center.deliveredNotifications()
            .map(\.request.identifier)
            .filter { $0.hasPrefix(Self.prefix) && !unopenedIds.contains($0) }
        if !staleDelivered.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: staleDelivered)
        }

        for letter in wanted {
            // Measured right before each add: the awaits above take time.
            let interval = letter.opensAt.timeIntervalSinceNow
            guard interval > 1 else { continue }

            let body = "Sealed on \(FutureLetterClock.shortDate(letter.sealedMoment, now: letter.opensAt)). Open it on Home."
            let content = UNMutableNotificationContent()
            content.title = "A letter for you is ready 💌"
            content.body = body
            content.sound = .default
            content.threadIdentifier = "coupley-future-letter"
            content.userInfo = [
                "type": NudgeType.futureLetter.rawValue,
                "letterId": letter.id,
                // Local notifications have no `aps`; NotificationViewModel
                // reads the text for its in-app list from "body".
                "body": body
            ]

            // An interval, not calendar components: the letter opens at one
            // absolute instant, which must survive time-zone travel.
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            let request = UNNotificationRequest(identifier: Self.prefix + letter.id,
                                                content: content,
                                                trigger: trigger)
            try? await center.add(request)
        }
    }

    func cancelAll() async {
        let pending = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)

        let delivered = await center.deliveredNotifications()
            .map(\.request.identifier)
            .filter { $0.hasPrefix(Self.prefix) }
        center.removeDeliveredNotifications(withIdentifiers: delivered)
    }

    func clearDelivered(letterId: String) {
        center.removeDeliveredNotifications(withIdentifiers: [Self.prefix + letterId])
    }
}
