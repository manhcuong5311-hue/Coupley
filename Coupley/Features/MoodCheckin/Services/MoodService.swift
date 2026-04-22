//
//  MoodService.swift
//  Coupley
//
//  Created by Sam Manh Cuong on 1/4/26.
//

import Foundation

// MARK: - Mood Service Protocol

protocol MoodService {
    func save(entry: MoodEntry) async throws
    func fetchAll() async throws -> [MoodEntry]
    /// Returns how many entries the current user has saved today (local time).
    func countTodayEntries() async throws -> Int
}

// MARK: - Local Mood Service (In-Memory Mock)

final class LocalMoodService: MoodService {

    private var entries: [MoodEntry] = []

    func save(entry: MoodEntry) async throws {
        // Simulate network latency for realistic UX testing
        try await Task.sleep(nanoseconds: 800_000_000)
        entries.append(entry)
    }

    func fetchAll() async throws -> [MoodEntry] {
        try await Task.sleep(nanoseconds: 300_000_000)
        return entries.sorted { $0.timestamp > $1.timestamp }
    }

    func countTodayEntries() async throws -> Int {
        let today = Calendar.current.startOfDay(for: Date())
        return entries.filter { $0.timestamp >= today }.count
    }
}

// NOTE: FirestoreMoodService is in Features/CoupleSync/Services/FirestoreMoodService.swift
// It conforms to MoodService and writes to Firestore with the user's coupleId.
// To use: MoodCheckinView(moodService: FirestoreMoodService(session: .demo))
