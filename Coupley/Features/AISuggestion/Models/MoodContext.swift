//
//  MoodContext.swift
//  Coupley
//
//  Created by Sam Manh Cuong on 1/4/26.
//

import Foundation

// MARK: - Mood Context

struct MoodContext: Codable, Equatable {
    let mood: Mood
    let energy: EnergyLevel
    let note: String?
    let lastInteraction: Date?

    init(
        mood: Mood,
        energy: EnergyLevel,
        note: String? = nil,
        lastInteraction: Date? = nil
    ) {
        self.mood = mood
        self.energy = energy
        self.note = note
        self.lastInteraction = lastInteraction
    }

    /// Convenience initializer from a MoodEntry
    init(from entry: MoodEntry, lastInteraction: Date? = nil) {
        self.mood = entry.mood
        self.energy = entry.energy
        self.note = entry.note
        self.lastInteraction = lastInteraction
    }

    // MARK: - Helpers

    var isLowMood: Bool {
        mood == .sad || mood == .stressed
    }

    var timeSinceLastInteraction: String? {
        guard let lastInteraction else { return nil }
        let interval = Date().timeIntervalSince(lastInteraction)
        let hours = Int(interval / 3600)
        if hours < 1 { return "just now" }
        if hours < 24 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }
}
