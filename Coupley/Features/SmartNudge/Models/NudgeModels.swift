//
//  NudgeModels.swift
//  Coupley
//
//  Created by Sam Manh Cuong on 1/4/26.
//

import Foundation

// MARK: - Nudge Type

enum NudgeType: String, Codable, CaseIterable {
    case lowMood = "low_mood"
    case dailySync = "daily_sync"
    case inactivity = "inactivity"

    var priority: Int {
        switch self {
        case .lowMood: return 1
        case .dailySync: return 2
        case .inactivity: return 3
        }
    }

    var icon: String {
        switch self {
        case .lowMood: return "heart.fill"
        case .dailySync: return "arrow.triangle.2.circlepath"
        case .inactivity: return "clock.fill"
        }
    }

    var label: String {
        switch self {
        case .lowMood: return "Partner Alert"
        case .dailySync: return "Daily Sync"
        case .inactivity: return "Check-in Reminder"
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

    var nudgeType: NudgeType? {
        NudgeType(rawValue: type)
    }

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

// FirestorePath members (users, notifications, userDocument) are in CoupleModels.swift
