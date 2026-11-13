//
//  NudgeModels.swift
//  Coupley
//

import Foundation

// MARK: - Nudge Type

enum NudgeType: String, Codable, CaseIterable {
    case lowMood    = "low_mood"
    case dailySync  = "daily_sync"
    case inactivity = "inactivity"
    case ping       = "ping"
    case reaction   = "reaction"
    case questionOfTheDay = "qotd"
    /// Local only: scheduled on the recipient's device for a letter's opening moment.
    case futureLetter = "future_letter"

    var icon: String {
        switch self {
        case .lowMood:    return "heart.fill"
        case .dailySync:  return "arrow.triangle.2.circlepath"
        case .inactivity: return "clock.fill"
        case .ping:       return "paperplane.fill"
        case .reaction:   return "face.smiling.fill"
        case .questionOfTheDay: return "questionmark.bubble.fill"
        case .futureLetter: return "envelope.fill"
        }
    }

    /// In-app label for the notification list. Display only: the type travels
    /// and is stored as `rawValue`.
    var label: LocalizedStringResource {
        switch self {
        case .lowMood:
            return LocalizedStringResource("Partner Alert",
                                           comment: "Notification type: your partner logged a low mood")
        case .dailySync:
            return LocalizedStringResource("Daily Sync",
                                           comment: "Notification type: your partner checked in, your turn")
        case .inactivity:
            return LocalizedStringResource("Check-in Reminder",
                                           comment: "Notification type: you haven't checked in for a while")
        case .ping:
            return LocalizedStringResource("Thinking of You",
                                           comment: "Notification type: your partner sent a 'thinking of you' ping")
        case .reaction:
            return LocalizedStringResource("Reaction",
                                           comment: "Notification type: your partner reacted to your mood")
        case .questionOfTheDay:
            return LocalizedStringResource("Question of the Day",
                                           comment: "Notification type: the daily question")
        case .futureLetter:
            return LocalizedStringResource("Future Letter",
                                           comment: "Notification type: a letter written for the future is ready")
        }
    }
}

// MARK: - Nudge Record

struct NudgeRecord: Identifiable, Codable {
    let id: String
    let type: String
    let title: String
    let body: String
    let timestamp: Date
    var isRead: Bool

    var nudgeType: NudgeType? { NudgeType(rawValue: type) }

    init(
        id: String = UUID().uuidString,
        type: String,
        title: String,
        body: String,
        timestamp: Date = Date(),
        isRead: Bool = false
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.body = body
        self.timestamp = timestamp
        self.isRead = isRead
    }

    var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = RelativeDateTimeFormatter.compactUnitsStyle
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}

// MARK: - Notification Permission State

enum NotificationPermissionState: Equatable {
    case unknown
    case authorized
    case denied
    case provisional
}

// MARK: - Notification Preferences

struct NotificationPreferences: Equatable {
    var partnerMoodAlert:   Bool = true
    var dailySyncReminder:  Bool = true
    var inactivityReminder: Bool = true
    var partnerPing:        Bool = true
    var partnerReaction:    Bool = true
    var reminderHour:       Int  = 20

    init() {}

    init(from dict: [String: Any], reminderHour: Int = 20) {
        self.partnerMoodAlert   = dict["partnerMoodAlert"]   as? Bool ?? true
        self.dailySyncReminder  = dict["dailySyncReminder"]  as? Bool ?? true
        self.inactivityReminder = dict["inactivityReminder"] as? Bool ?? true
        self.partnerPing        = dict["partnerPing"]        as? Bool ?? true
        self.partnerReaction    = dict["partnerReaction"]    as? Bool ?? true
        self.reminderHour       = reminderHour
    }

    var firestorePrefsDict: [String: Any] {
        [
            "partnerMoodAlert":   partnerMoodAlert,
            "dailySyncReminder":  dailySyncReminder,
            "inactivityReminder": inactivityReminder,
            "partnerPing":        partnerPing,
            "partnerReaction":    partnerReaction,
        ]
    }
}
