//
//  SyncService.swift
//  Coupley
//
//  Created by Sam Manh Cuong on 1/4/26.
//

import Foundation
import FirebaseFirestore

// MARK: - Sync Service Protocol

protocol SyncService {
    func calculateDailyScore(userA: SharedMoodEntry, userB: SharedMoodEntry) -> SyncScore
    func fetchRecentScores(coupleId: String, days: Int) async throws -> [SyncScore]
    func saveSyncScore(_ score: SyncScore, coupleId: String) async throws
    func calculateWeeklyAverage(scores: [SyncScore]) -> Int
    func calculateTrend(scores: [SyncScore]) -> SyncTrend

    /// Computes and stores today's score when BOTH partners have checked in.
    ///
    /// `calculateDailyScore` and `saveSyncScore` existed but had no callers
    /// anywhere in the app, so no sync score was ever written and every number
    /// on the stats screen was permanently zero.
    @discardableResult
    func recomputeTodayScore(coupleId: String, session: UserSession) async throws -> SyncScore?
}

// MARK: - Mood Scoring Matrix

private enum MoodScoringMatrix {

    /// Mood similarity score (0–60 points)
    static func moodScore(_ a: Mood, _ b: Mood) -> Int {
        if a == b { return 60 }

        let matrix: [Set<Mood>: Int] = [
            [.happy, .neutral]: 45,
            [.neutral, .sad]: 35,
            [.neutral, .stressed]: 35,
            [.happy, .stressed]: 20,
            [.happy, .sad]: 15,
            [.sad, .stressed]: 40,
        ]

        return matrix[Set([a, b])] ?? 25
    }

    /// Energy similarity score (0–40 points)
    static func energyScore(_ a: EnergyLevel, _ b: EnergyLevel) -> Int {
        if a == b { return 40 }

        let matrix: [Set<EnergyLevel>: Int] = [
            [.low, .medium]: 25,
            [.medium, .high]: 25,
            [.low, .high]: 10,
        ]

        return matrix[Set([a, b])] ?? 15
    }
}

// MARK: - Firestore Sync Service

final class FirestoreSyncService: SyncService {

    private let db = Firestore.firestore()

    // MARK: - Calculate Score

    func calculateDailyScore(userA: SharedMoodEntry, userB: SharedMoodEntry) -> SyncScore {
        let moodPts = MoodScoringMatrix.moodScore(userA.moodValue, userB.moodValue)
        let energyPts = MoodScoringMatrix.energyScore(userA.energyValue, userB.energyValue)
        let total = moodPts + energyPts

        let dateString = DayKey.string(from: userA.timestamp)

        return SyncScore(
            date: dateString,
            score: total,
            moodMatch: userA.mood == userB.mood,
            energyMatch: userA.energy == userB.energy,
            userAMood: userA.mood,
            userBMood: userB.mood,
            userAEnergy: userA.energy,
            userBEnergy: userB.energy
        )
    }

    // MARK: - Fetch

    func fetchRecentScores(coupleId: String, days: Int = 7) async throws -> [SyncScore] {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let cutoffString = DayKey.string(from: cutoffDate)

        let snapshot = try await db
            .collection(FirestorePath.syncScores(coupleId: coupleId))
            .whereField("date", isGreaterThanOrEqualTo: cutoffString)
            .order(by: "date", descending: true)
            .getDocuments()

        return snapshot.documents.compactMap { doc in
            try? doc.data(as: SyncScore.self)
        }
    }

    // MARK: - Save

    @discardableResult
    func recomputeTodayScore(coupleId: String, session: UserSession) async throws -> SyncScore? {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let todayEnd = calendar.date(byAdding: .day, value: 1, to: todayStart)!

        let snapshot = try await db
            .collection(FirestorePath.moods(coupleId: coupleId))
            .whereField("timestamp", isGreaterThanOrEqualTo: Timestamp(date: todayStart))
            .whereField("timestamp", isLessThan: Timestamp(date: todayEnd))
            .getDocuments()

        let moods = snapshot.documents.compactMap { try? $0.data(as: SharedMoodEntry.self) }

        // Most recent entry per person — a user may check in up to 3x a day.
        func latest(_ userId: String) -> SharedMoodEntry? {
            moods.filter { $0.userId == userId }.max(by: { $0.timestamp < $1.timestamp })
        }
        guard let mine = latest(session.userId),
              let theirs = latest(session.partnerId) else { return nil }

        let score = calculateDailyScore(userA: mine, userB: theirs)
        try await saveSyncScore(score, coupleId: coupleId)
        return score
    }

    func saveSyncScore(_ score: SyncScore, coupleId: String) async throws {
        try await db
            .collection(FirestorePath.syncScores(coupleId: coupleId))
            .document(score.date)
            .setData(from: score)
    }

    // MARK: - Aggregation

    func calculateWeeklyAverage(scores: [SyncScore]) -> Int {
        guard !scores.isEmpty else { return 0 }
        let total = scores.reduce(0) { $0 + $1.score }
        return total / scores.count
    }

    func calculateTrend(scores: [SyncScore]) -> SyncTrend {
        guard scores.count >= 2 else { return .stable }

        let sorted = scores.sorted { $0.date < $1.date }
        let half = sorted.count / 2
        let firstHalf = Array(sorted.prefix(half))
        let secondHalf = Array(sorted.suffix(half))

        let firstAvg = firstHalf.isEmpty ? 0 : firstHalf.reduce(0) { $0 + $1.score } / firstHalf.count
        let secondAvg = secondHalf.isEmpty ? 0 : secondHalf.reduce(0) { $0 + $1.score } / secondHalf.count

        let diff = secondAvg - firstAvg

        if diff > 3 {
            return .up(diff)
        } else if diff < -3 {
            return .down(abs(diff))
        } else {
            return .stable
        }
    }
}

// MARK: - Mock Sync Service

final class MockSyncService: SyncService {

    func calculateDailyScore(userA: SharedMoodEntry, userB: SharedMoodEntry) -> SyncScore {
        FirestoreSyncService().calculateDailyScore(userA: userA, userB: userB)
    }

    func fetchRecentScores(coupleId: String, days: Int = 7) async throws -> [SyncScore] {
        try await Task.sleep(nanoseconds: 400_000_000)

        let calendar = Calendar.current

        return (0..<days).map { daysAgo in
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: Date())!
            let dateStr = DayKey.string(from: date)
            let score = Int.random(in: 45...98)

            return SyncScore(
                date: dateStr,
                score: score,
                moodMatch: score > 70,
                energyMatch: score > 60,
                userAMood: "happy",
                userBMood: score > 70 ? "happy" : "neutral",
                userAEnergy: "medium",
                userBEnergy: score > 60 ? "medium" : "low"
            )
        }
    }

    func saveSyncScore(_ score: SyncScore, coupleId: String) async throws {
        try await Task.sleep(nanoseconds: 200_000_000)
    }

    @discardableResult
    func recomputeTodayScore(coupleId: String, session: UserSession) async throws -> SyncScore? {
        nil
    }

    func calculateWeeklyAverage(scores: [SyncScore]) -> Int {
        FirestoreSyncService().calculateWeeklyAverage(scores: scores)
    }

    func calculateTrend(scores: [SyncScore]) -> SyncTrend {
        FirestoreSyncService().calculateTrend(scores: scores)
    }
}
