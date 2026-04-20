//
//  CoupleModels.swift
//  Coupley
//
//  Created by Sam Manh Cuong on 1/4/26.
//

import Foundation
import FirebaseFirestore

// MARK: - User Session

struct UserSession {
    let userId: String
    let coupleId: String
    let partnerId: String

    /// True only when this session has a real partner connected.
    var isPaired: Bool { !coupleId.isEmpty && !partnerId.isEmpty }

    /// Solo session — authenticated but no partner yet.
    static func solo(userId: String) -> UserSession {
        UserSession(userId: userId, coupleId: "", partnerId: "")
    }

    static let demo = UserSession(
        userId: "user_001",
        coupleId: "couple_001",
        partnerId: "user_002"
    )
}

// MARK: - Couple Document

struct CoupleDocument: Codable {
    let userIds: [String]

    func partnerId(for userId: String) -> String? {
        userIds.first { $0 != userId }
    }
}

// MARK: - Shared Mood Entry (Firestore)

struct SharedMoodEntry: Identifiable, Codable, Equatable {
    @DocumentID var firestoreId: String?
    let id: String
    let userId: String
    let mood: String
    let energy: String
    let note: String?
    let timestamp: Date

    var documentId: String {
        firestoreId ?? id
    }

    // MARK: - Domain Mapping

    var moodValue: Mood {
        Mood(rawValue: mood) ?? .neutral
    }

    var energyValue: EnergyLevel {
        EnergyLevel(rawValue: energy) ?? .medium
    }

    var isLowMood: Bool {
        moodValue == .sad || moodValue == .stressed
    }

    var isLowEnergy: Bool {
        energyValue == .low
    }

    var needsAttention: Bool {
        isLowMood || (isLowMood && isLowEnergy)
    }

    // MARK: - From MoodEntry

    init(from entry: MoodEntry, userId: String) {
        self.id = entry.id.uuidString
        self.userId = userId
        self.mood = entry.mood.rawValue
        self.energy = entry.energy.rawValue
        self.note = entry.note
        self.timestamp = entry.timestamp
    }

    // MARK: - To MoodEntry

    func toMoodEntry() -> MoodEntry {
        MoodEntry(
            id: UUID(uuidString: id) ?? UUID(),
            mood: moodValue,
            energy: energyValue,
            note: note,
            timestamp: timestamp
        )
    }

    // MARK: - To MoodContext

    func toMoodContext(lastInteraction: Date? = nil) -> MoodContext {
        MoodContext(
            mood: moodValue,
            energy: energyValue,
            note: note,
            lastInteraction: lastInteraction
        )
    }

    // MARK: - Relative Time

    var relativeTimestamp: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}

// MARK: - Firestore Collection Paths

enum FirestorePath {
    static let couples = "couples"
    static let users = "users"
    static let pairingCodes = "pairingCodes"
    static let notifications = "notifications"

    static func moods(coupleId: String) -> String {
        "\(couples)/\(coupleId)/moods"
    }

    static func syncScores(coupleId: String) -> String {
        "\(couples)/\(coupleId)/syncScores"
    }

    static func userDocument(userId: String) -> String {
        "\(users)/\(userId)"
    }
}
