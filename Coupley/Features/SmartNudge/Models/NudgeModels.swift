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

    var icon: String {
        switch self {
        case .lowMood:    return "heart.fill"
        case .dailySync:  return "arrow.triangle.2.circlepath"
        case .inactivity: return "clock.fill"
        case .ping:       return "paperplane.fill"
        case .reaction:   return "face.smiling.fill"
        }
    }

    var label: String {
        switch self {
        case .lowMood:    return "Partner Alert"
        case .dailySync:  return "Daily Sync"
        case .inactivity: return "Check-in Reminder"
        case .ping:       return "Thinking of You"
        case .reaction:   return "Reaction"
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
        formatter.unitsStyle = .abbreviated
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
