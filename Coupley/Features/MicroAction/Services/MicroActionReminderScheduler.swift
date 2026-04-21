//
//  MicroActionReminderScheduler.swift
//  Coupley
//

import Foundation
import UserNotifications

// MARK: - Protocol

protocol MicroActionReminderScheduling {
    func scheduleReminder(for action: MicroAction, at date: Date) async
    func cancelReminder(for actionId: String) async
}

// MARK: - Default

/// Thin wrapper around UNUserNotificationCenter. Reminders are gentle: one
/// shot, no repeats, and we rate-limit by replacing any existing reminder on
/// the same action id.
final class MicroActionReminderScheduler: MicroActionReminderScheduling {

    private let center = UNUserNotificationCenter.current()

    func scheduleReminder(for action: MicroAction, at date: Date) async {
        await cancelReminder(for: action.id)

        // Don't bother if the reminder would fire in the past or within
        // the next minute — too jarring.
        guard date.timeIntervalSinceNow > 60 else { return }

        let content = UNMutableNotificationContent()
        content.title = "A small thing you were going to do"
        content.body  = action.text
        content.sound = .default
        content.userInfo = [
            "type": "microAction",
            "actionId": action.id
        ]

        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: comps,
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: identifier(for: action.id),
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
        } catch {
            print("[MicroActionReminder] Failed: \(error.localizedDescription)")
        }
    }

    func cancelReminder(for actionId: String) async {
        center.removePendingNotificationRequests(
            withIdentifiers: [identifier(for: actionId)]
        )
    }

    private func identifier(for actionId: String) -> String {
        "microaction.\(actionId)"
    }
}
