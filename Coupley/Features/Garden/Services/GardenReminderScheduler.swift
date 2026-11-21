//
//  GardenReminderScheduler.swift
//  Coupley
//
//  The garden's two local reminders (spec H): `tt.garden.ready` at the first
//  19:00 at or after the latest confirmed watering + 48 h, and
//  `tt.garden.rest` at the first 19:00 at or after it + 7 days. A garden that
//  was never watered is invited on screen, never nagged.
//
//  Re-planned by WidgetSyncService on its serial reminder chain (confirmed
//  watering snapshots, foreground, the anchor, the Garden toggle and the
//  remote switch: while the garden is switched off remotely every plan
//  cancels) and by the watering push's background wake. Never in a build
//  without the garden. The two paths can interleave, so
//  every plan goes through the monotonic guard (GardenReminderPlan.isStale):
//  a plan that knows an older watering than the one already planned for the
//  couple changes nothing, and the stored time only ever moves forward.
//
//  The copy is English, like every notification in the app (the product
//  owner's decision): the in-app list shows the `body` it carries.
//

import Foundation
import UserNotifications

@MainActor
final class GardenReminderScheduler: GardenReminderScheduling {

    /// Both reminders fire at this local hour, wherever the phone is.
    nonisolated static let reminderHour = 19
    /// A reminder less than this far away is not added: iOS may already be
    /// delivering the one it replaces, and a reminder a few seconds after
    /// the plan is noise.
    nonisolated static let minimumLead: TimeInterval = 60

    nonisolated private static let readyTitle = "The garden is ready for water 💧"
    /// Picked by the watering id, so both phones say the same line.
    nonisolated private static let readyBodies = [
        "Water it together tonight?",
        "A little water, a little note: the garden is ready.",
        "Time for a drink? The garden is ready when you are."
    ]
    nonisolated private static let restTitle = "Your garden is resting 🌙"
    nonisolated private static let restBody = "No rush. Whenever you're ready, a little water wakes it up."

    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard

    init() {}

    // MARK: - Planning (pure)

    /// One reminder request, before it is handed to iOS.
    nonisolated struct Reminder: Equatable, Sendable {
        let identifier: String
        let type: String
        let title: String
        let body: String
        let fireDate: Date
    }

    /// What `reschedule` does with a plan, given the time already stored for
    /// the couple (`GardenDefaultsKey.lastWateringMs`).
    nonisolated enum Decision: Equatable, Sendable {
        /// Stale: built from an older watering than the one already planned.
        case ignore
        /// No Our tree, never watered, or the Garden toggle is off.
        case cancel
        /// Store `lastWateringMs` and plan the reminders for this watering.
        case schedule(lastWateringMs: Int64, wateringId: String, reminders: [Reminder])
    }

    nonisolated static func decision(for plan: GardenReminderPlan, storedLastWateringMs stored: Int64?,
                                      calendar: Calendar) -> Decision {
        if plan.isStale(storedLastWateringMs: stored) { return .ignore }
        guard plan.hasOurTree, plan.isEnabled,
              let lastWateredAt = plan.lastWateredAt,
              let lastWateringMs = plan.lastWateredAtMs else { return .cancel }
        let wateringId = plan.lastWateringId ?? ""
        return .schedule(lastWateringMs: lastWateringMs,
                         wateringId: wateringId,
                         reminders: reminders(lastWateredAt: lastWateredAt, wateringId: wateringId, calendar: calendar))
    }

    /// Both reminders for a watering, whether or not their moment has passed
    /// (`reschedule` adds only the ones still ahead).
    nonisolated static func reminders(lastWateredAt: Date, wateringId: String, calendar: Calendar) -> [Reminder] {
        var result: [Reminder] = []
        if let ready = firstReminderMoment(atOrAfter: lastWateredAt.addingTimeInterval(GardenCadence.readyAfter),
                                           calendar: calendar) {
            let line = Int(JourneyTreeOrnament.stableSeed(wateringId) % UInt64(readyBodies.count))
            result.append(Reminder(identifier: GardenNotification.readyReminderId,
                                   type: GardenNotification.readyReminderType,
                                   title: readyTitle,
                                   body: readyBodies[line],
                                   fireDate: ready))
        }
        if let rest = firstReminderMoment(atOrAfter: lastWateredAt.addingTimeInterval(GardenCadence.restingAfter),
                                          calendar: calendar) {
            result.append(Reminder(identifier: GardenNotification.restReminderId,
                                   type: GardenNotification.restReminderType,
                                   title: restTitle,
                                   body: restBody,
                                   fireDate: rest))
        }
        return result
    }

    /// Delivered garden reminders a newer watering made untrue: every
    /// `tt.garden.*` about another watering. One about the current watering
    /// stays in Notification Center.
    nonisolated static func untrueDelivered(_ delivered: [(identifier: String, wateringId: String?)],
                                            currentWateringId: String) -> [String] {
        delivered
            .filter { $0.identifier.hasPrefix(GardenNotification.reminderPrefix) && $0.wateringId != currentWateringId }
            .map(\.identifier)
    }

    /// The first 19:00 in `calendar`'s time zone at or after `moment`.
    nonisolated static func firstReminderMoment(atOrAfter moment: Date, calendar: Calendar) -> Date? {
        calendar.nextDate(after: moment.addingTimeInterval(-1),
                          matching: DateComponents(hour: reminderHour, minute: 0),
                          matchingPolicy: .nextTime)
    }

    // MARK: - Push wake

    /// The background wake of a watering push (AppDelegate). Proceeds only
    /// in a build with the garden, for the couple WidgetSyncService last
    /// bound (`GardenDefaultsKey.activeCoupleId`), while reminders are
    /// allowed (the Garden toggle's mirror is on and the garden is not
    /// switched off remotely: either one already cancelled them); joins
    /// WidgetSyncService's serial chain when it is bound to that couple,
    /// otherwise reschedules directly. Returns once the plan has been
    /// applied (or ignored), so the wake is not suspended mid-way.
    static func replanFromPush(coupleId: String, wateredAtMs: String, wateringId: String) async {
        let defaults = UserDefaults.standard
        guard GardenFeature.isEnabled,
              !coupleId.isEmpty,
              coupleId == defaults.string(forKey: GardenDefaultsKey.activeCoupleId),
              let ms = Int64(wateredAtMs.trimmingCharacters(in: .whitespaces)), ms > 0,
              !wateringId.isEmpty,
              remindersAllowed(defaults) else { return }

        let sync = WidgetSyncService.shared
        if sync.isBound(toCouple: coupleId) {
            sync.queueGardenReplan(fromPushWateredAtMs: ms, wateringId: wateringId)
            await sync.reminderWorkSettled()
        } else {
            // A watering needs the start date, so Our tree exists.
            let plan = GardenReminderPlan(coupleId: coupleId,
                                          lastWateredAt: Date(timeIntervalSince1970: TimeInterval(ms) / 1000),
                                          lastWateringId: wateringId,
                                          hasOurTree: true,
                                          isEnabled: true)
            await GardenReminderScheduler().reschedule(plan)
        }
    }

    /// The Garden toggle's mirror (`notificationPreferences.garden`), on
    /// until the preferences say otherwise.
    static func isEnabledMirror(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: GardenDefaultsKey.notificationsEnabled) as? Bool ?? true
    }

    /// Reminders may be planned: the Garden toggle's mirror is on and the
    /// garden is not switched off remotely (`appConfig/garden {enabled:
    /// false}` as this install last heard it). A plan built while they may
    /// not cancels every garden reminder.
    static func remindersAllowed(_ defaults: UserDefaults = .standard) -> Bool {
        isEnabledMirror(defaults) && !GardenBackendState.isSwitchedOff
    }

    /// The watering time last planned for a couple, in whole milliseconds.
    static func storedLastWateringMs(coupleId: String, defaults: UserDefaults = .standard) -> Int64? {
        (defaults.object(forKey: GardenDefaultsKey.lastWateringMs(coupleId)) as? NSNumber)?.int64Value
    }

    // MARK: - GardenReminderScheduling

    func reschedule(_ plan: GardenReminderPlan) async {
        let stored = Self.storedLastWateringMs(coupleId: plan.coupleId, defaults: defaults)
        switch Self.decision(for: plan, storedLastWateringMs: stored, calendar: .current) {
        case .ignore:
            return

        case .cancel:
            await cancelAll()

        case let .schedule(lastWateringMs, wateringId, reminders):
            // A confirmed server time, never older than the stored one (the
            // guard), so the stored value only moves forward. Stored even
            // without permission: the guard must still know it.
            defaults.set(NSNumber(value: lastWateringMs), forKey: GardenDefaultsKey.lastWateringMs(plan.coupleId))

            let status = await center.notificationSettings().authorizationStatus
            guard status == .authorized || status == .provisional else {
                await cancelAll()
                return
            }

            center.removePendingNotificationRequests(withIdentifiers: [GardenNotification.readyReminderId,
                                                                       GardenNotification.restReminderId])
            let delivered = await center.deliveredNotifications().map {
                (identifier: $0.request.identifier,
                 wateringId: $0.request.content.userInfo[GardenNotification.wateringIdKey] as? String)
            }
            let untrue = Self.untrueDelivered(delivered, currentWateringId: wateringId)
            if !untrue.isEmpty {
                center.removeDeliveredNotifications(withIdentifiers: untrue)
            }

            for reminder in reminders {
                // A sign-out or disconnect cancels the chain: nothing is
                // added after it.
                guard !Task.isCancelled else { return }
                // Measured right before the add: the awaits above take time.
                guard reminder.fireDate.timeIntervalSinceNow >= Self.minimumLead else { continue }
                try? await center.add(request(for: reminder, coupleId: plan.coupleId, wateringId: wateringId))
            }
        }
    }

    func cancelAll() async {
        let pending = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(GardenNotification.reminderPrefix) }
        if !pending.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: pending)
        }
        let delivered = await center.deliveredNotifications()
            .map(\.request.identifier)
            .filter { $0.hasPrefix(GardenNotification.reminderPrefix) }
        if !delivered.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: delivered)
        }
    }

    // MARK: - Request

    private func request(for reminder: Reminder, coupleId: String, wateringId: String) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        content.threadIdentifier = GardenNotification.reminderThread
        content.userInfo = [
            GardenNotification.typeKey: reminder.type,
            GardenNotification.coupleIdKey: coupleId,
            GardenNotification.wateringIdKey: wateringId,
            // Local notifications have no `aps`; NotificationViewModel reads
            // the text of its in-app list from here.
            GardenNotification.bodyKey: reminder.body
        ]
        // Calendar components without a time zone: 19:00 wherever the phone
        // is that evening, through DST and travel (crowns do the same).
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: trigger)
    }
}
