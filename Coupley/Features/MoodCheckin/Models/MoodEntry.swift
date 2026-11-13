//
//  MoodEntry.swift
//  Coupley
//
//  Created by Sam Manh Cuong on 1/4/26.
//

import Foundation

// MARK: - Mood

enum Mood: String, CaseIterable, Identifiable, Codable {
    case happy
    case neutral
    case sad
    case stressed

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .happy: return "😊"
        case .neutral: return "😐"
        case .sad: return "😢"
        case .stressed: return "😤"
        }
    }

    /// Display name in the user's language. Display only: storage, comparisons
    /// and the AI backend use `rawValue`, which never changes.
    var label: String {
        switch self {
        case .happy:    return String(localized: "Happy", comment: "Mood name")
        case .neutral:  return String(localized: "Neutral", comment: "Mood name")
        case .sad:      return String(localized: "Sad", comment: "Mood name")
        case .stressed: return String(localized: "Stressed", comment: "Mood name")
        }
    }
}

// MARK: - Energy Level

enum EnergyLevel: String, CaseIterable, Identifiable, Codable {
    case low
    case medium
    case high

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .low: return "battery.25"
        case .medium: return "battery.50"
        case .high: return "battery.100"
        }
    }

    /// Display name in the user's language. Display only: storage, comparisons
    /// and the AI backend use `rawValue`, which never changes.
    var label: String {
        switch self {
        case .low:    return String(localized: "Low", comment: "Energy level")
        case .medium: return String(localized: "Medium", comment: "Energy level")
        case .high:   return String(localized: "High", comment: "Energy level")
        }
    }
}

// MARK: - Mood Entry

struct MoodEntry: Identifiable, Codable {
    let id: UUID
    let mood: Mood
    let energy: EnergyLevel
    let note: String?
    let timestamp: Date

    init(
        id: UUID = UUID(),
        mood: Mood,
        energy: EnergyLevel,
        note: String? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.mood = mood
        self.energy = energy
        self.note = note?.isEmpty == true ? nil : note
        self.timestamp = timestamp
    }
}
