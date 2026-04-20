//
//  StreakService.swift
//  Coupley
//
//  Created by Sam Manh Cuong on 1/4/26.
//

import Foundation
import FirebaseFirestore

// MARK: - Streak Service Protocol

protocol StreakService {
    func fetchStreak(coupleId: String) async throws -> StreakData
    func updateStreak(coupleId: String, session: UserSession) async throws -> StreakData
}

// MARK: - Firestore Streak Service

final class FirestoreStreakService: StreakService {

    private let db = Firestore.firestore()

    // MARK: - Fetch

    func fetchStreak(coupleId: String) async throws -> StreakData {
        let doc = try await db
            .collection(FirestorePath.couples)
            .document(coupleId)
            .getDocument()

        guard doc.exists,
              let data = doc.data(),
              let current = data["currentStreak"] as? Int,
              let longest = data["longestStreak"] as? Int else {
            return .zero
        }

        let lastDate = (data["lastStreakDate"] as? Timestamp)?.dateValue()

        return StreakData(
            currentStreak: current,
            longestStreak: longest,
            lastStreakDate: lastDate
        )
    }

    // MARK: - Update

    func updateStreak(coupleId: String, session: UserSession) async throws -> StreakData {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let todayEnd = calendar.date(byAdding: .day, value: 1, to: todayStart)!

        // Fetch today's moods for both users
        let snapshot = try await db
            .collection(FirestorePath.moods(coupleId: coupleId))
            .whereField("timestamp", isGreaterThanOrEqualTo: Timestamp(date: todayStart))
            .whereField("timestamp", isLessThan: Timestamp(date: todayEnd))
            .getDocuments()

        let todayMoods = snapshot.documents.compactMap { doc in
            try? doc.data(as: SharedMoodEntry.self)
        }

        let userIds = Set(todayMoods.map(\.userId))
        let bothCheckedIn = userIds.contains(session.userId) && userIds.contains(session.partnerId)

        // Fetch current streak
        var streak = try await fetchStreak(coupleId: coupleId)

        if bothCheckedIn {
            // Already counted today
            if streak.isActiveToday {
                return streak
            }

            // Check if yesterday was active (continuation) or gap (restart)
            let yesterday = calendar.date(byAdding: .day, value: -1, to: todayStart)!
            if let lastDate = streak.lastStreakDate,
               calendar.isDate(lastDate, inSameDayAs: yesterday) {
                // Continue streak
                streak.currentStreak += 1
            } else if streak.lastStreakDate == nil {
                // First ever streak
                streak.currentStreak = 1
            } else {
                // Gap — restart
                streak.currentStreak = 1
            }

            streak.longestStreak = max(streak.longestStreak, streak.currentStreak)
            streak.lastStreakDate = Date()

            // Save to Firestore
            try await db
                .collection(FirestorePath.couples)
                .document(coupleId)
                .setData([
                    "currentStreak": streak.currentStreak,
                    "longestStreak": streak.longestStreak,
                    "lastStreakDate": Timestamp(date: streak.lastStreakDate!),
                ], merge: true)
        } else {
            // Check if streak needs reset (yesterday had no streak update)
            if let lastDate = streak.lastStreakDate {
                let yesterday = calendar.date(byAdding: .day, value: -1, to: todayStart)!
                if lastDate < yesterday {
                    streak.currentStreak = 0
                    streak.lastStreakDate = nil

                    try await db
                        .collection(FirestorePath.couples)
                        .document(coupleId)
                        .setData([
                            "currentStreak": 0,
                            "lastStreakDate": FieldValue.delete(),
                        ], merge: true)
                }
            }
        }

        return streak
    }
}

// MARK: - Mock Streak Service

final class MockStreakService: StreakService {

    private var mockStreak = StreakData(
        currentStreak: 5,
        longestStreak: 12,
        lastStreakDate: Date()
    )

    func fetchStreak(coupleId: String) async throws -> StreakData {
        try await Task.sleep(nanoseconds: 300_000_000)
        return mockStreak
    }

    func updateStreak(coupleId: String, session: UserSession) async throws -> StreakData {
        try await Task.sleep(nanoseconds: 400_000_000)
        mockStreak.currentStreak += 1
        mockStreak.longestStreak = max(mockStreak.longestStreak, mockStreak.currentStreak)
        mockStreak.lastStreakDate = Date()
        return mockStreak
    }
}
