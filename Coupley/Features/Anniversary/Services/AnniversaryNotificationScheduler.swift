//
//  AnniversaryNotificationScheduler.swift
//  Coupley
//

import Foundation
import UserNotifications

// MARK: - Protocol

protocol AnniversaryNotificationScheduling {
    func reschedule(_ anniversary: Anniversary) async
    func cancel(_ anniversaryId: String) async
    func cancelAll() async
}

// MARK: - Default Milestones

/// Number of days *before* the target date to fire a notification.
/// `0` = on the day. The scheduler always fires at 09:00 local time.
struct AnniversaryMilestone: Equatable, Identifiable, Hashable {
    let id: String
    let daysBefore: Int

    static let thirtyDays = AnniversaryMilestone(id: "m30", daysBefore: 30)
    static let sevenDays  = AnniversaryMilestone(id: "m7",  daysBefore: 7)
    static let oneDay     = AnniversaryMilestone(id: "m1",  daysBefore: 1)
    static let onTheDay   = AnniversaryMilestone(id: "m0",  daysBefore: 0)

    static let defaults: [AnniversaryMilestone] = [
        .thirtyDays, .sevenDays, .oneDay, .onTheDay
    ]
}

// MARK: - Scheduler

final class AnniversaryNotificationScheduler: AnniversaryNotificationScheduling {

    private let center = UNUserNotificationCenter.current()
    private let milestones: [AnniversaryMilestone]
    private let fireHour: Int

    init(
        milestones: [AnniversaryMilestone] = AnniversaryMilestone.defaults,
        fireHour: Int = 9
    ) {
        self.milestones = milestones
        self.fireHour = fireHour
    }

    // MARK: - Reschedule

    /// Cancels any pending milestone for this anniversary, then schedules fresh
    /// ones for every milestone whose fire date is still in the future.
    func reschedule(_ a: Anniversary) async {
        await cancel(a.id)

        let calendar = Calendar.current

        for milestone in milestones {
            guard let fireDate = calendar.date(
                bySettingHour: fireHour, minute: 0, second: 0,
                of: calendar.date(
                    byAdding: .day,
                    value: -milestone.daysBefore,
                    to: a.date
                ) ?? a.date
            ) else { continue }

            // Only schedule if the fire date is strictly in the future.
            guard fireDate > Date() else { continue }

            let content = UNMutableNotificationContent()
            content.title = notificationTitle(for: milestone, anniversary: a)
            content.body  = notificationBody(for: milestone, anniversary: a)
            content.sound = .default
            content.userInfo = [
                "type": "anniversary",
                "anniversaryId": a.id,
                "milestone": milestone.id
            ]

            let comps = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: fireDate
            )
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: comps,
                repeats: false
            )

            let request = UNNotificationRequest(
                identifier: identifier(for: a.id, milestone: milestone),
                content: content,
                trigger: trigger
            )

            do {
                try await center.add(request)
            } catch {
                print("[AnniversaryScheduler] Failed to add \(request.identifier): \(error)")
            }
        }
    }

    // MARK: - Cancel

    func cancel(_ anniversaryId: String) async {
        let ids = milestones.map { identifier(for: anniversaryId, milestone: $0) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    func cancelAll() async {
        let pending = await center.pendingNotificationRequests()
        let ids = pending
            .filter { $0.identifier.hasPrefix("anniv.") }
            .map { $0.identifier }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: - Copy

    private func notificationTitle(
        for milestone: AnniversaryMilestone,
        anniversary a: Anniversary
    ) -> String {
        switch milestone.daysBefore {
        case 0:  return a.title
        case 1:  return "Tomorrow ♡"
        case 7:  return "One week to go"
        case 30: return "One month to go"
        default: return "\(milestone.daysBefore) days to go"
        }
    }

    private func notificationBody(
        for milestone: AnniversaryMilestone,
        anniversary a: Anniversary
    ) -> String {
        switch milestone.daysBefore {
        case 0:  return "Today is \(a.title). Make it gentle and memorable."
        case 1:  return "\(a.title) is tomorrow. A small gesture goes a long way."
        case 7:  return "\(a.title) in a week. Plan something quiet together."
        case 30: return "\(a.title) is a month away. Room to dream a little."
        default: return "\(a.title) — \(milestone.daysBefore) days to go."
        }
    }

    // MARK: - Identifiers

    private func identifier(for id: String, milestone: AnniversaryMilestone) -> String {
        "anniv.\(id).\(milestone.id)"
    }
}
