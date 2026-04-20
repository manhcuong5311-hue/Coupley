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

    var label: String {
        rawValue.capitalized
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

    var label: String {
        rawValue.capitalized
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
