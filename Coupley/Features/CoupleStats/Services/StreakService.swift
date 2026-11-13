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

        var streak = try await fetchStreak(coupleId: coupleId)

        if bothCheckedIn {
            // Already counted today
            if streak.isActiveToday {
                return streak
            }

            // Transactional, because BOTH partners' devices run this the moment
            // the second check-in lands. A plain read-modify-write races and
            // increments the shared streak twice for one day.
            let coupleRef = db.collection(FirestorePath.couples).document(coupleId)
            let yesterday = calendar.date(byAdding: .day, value: -1, to: todayStart)!

            let updated = try await db.runTransaction { transaction, errorPointer -> Any? in
                do {
                    let snap = try transaction.getDocument(coupleRef)
                    let data = snap.data() ?? [:]

                    let current = data["currentStreak"] as? Int ?? 0
                    let longest = data["longestStreak"] as? Int ?? 0
                    let lastDate = (data["lastStreakDate"] as? Timestamp)?.dateValue()

                    // Someone else already counted today — adopt their value.
                    if let lastDate, calendar.isDateInToday(lastDate) {
                        return [current, longest]
                    }

                    let nextCurrent: Int
                    if let lastDate, calendar.isDate(lastDate, inSameDayAs: yesterday) {
                        nextCurrent = current + 1      // continues yesterday
                    } else {
                        nextCurrent = 1                // first ever, or after a gap
                    }
                    let nextLongest = max(longest, nextCurrent)

                    transaction.setData([
                        "currentStreak": nextCurrent,
                        "longestStreak": nextLongest,
                        "lastStreakDate": Timestamp(date: Date()),
                    ], forDocument: coupleRef, merge: true)
                    return [nextCurrent, nextLongest]
                } catch let error as NSError {
                    errorPointer?.pointee = error
                    return nil
                }
            }

            if let pair = updated as? [Int], pair.count == 2 {
                streak.currentStreak = pair[0]
                streak.longestStreak = pair[1]
                streak.lastStreakDate = Date()
            }
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
