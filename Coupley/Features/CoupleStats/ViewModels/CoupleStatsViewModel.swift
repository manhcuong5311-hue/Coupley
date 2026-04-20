//
//  CoupleStatsViewModel.swift
//  Coupley
//
//  Created by Sam Manh Cuong on 1/4/26.
//

import Foundation
import Combine
// MARK: - Stats Load State

enum StatsLoadState: Equatable {
    case idle
    case loading
    case loaded
    case error(String)
}

// MARK: - Couple Stats ViewModel

@MainActor
final class CoupleStatsViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var loadState: StatsLoadState = .idle
    @Published var streak: StreakData = .zero
    @Published var todaySyncScore: SyncScore?
    @Published var weeklyScores: [SyncScore] = []
    @Published var weeklyAverage: Int = 0
    @Published var trend: SyncTrend = .stable

    // MARK: - Computed Properties

    var syncLevel: SyncLevel {
        guard let score = todaySyncScore else { return .outOfSync }
        return SyncLevel.from(score: score.score)
    }

    var streakProgressToNextMilestone: Double {
        guard let current = streak.milestoneReached,
              let next = current.next else {
            // No milestone yet — progress toward first (3)
            if streak.currentStreak == 0 { return 0 }
            return min(Double(streak.currentStreak) / 3.0, 1.0)
        }
        let progress = Double(streak.currentStreak - current.threshold)
            / Double(next.threshold - current.threshold)
        return min(max(progress, 0), 1.0)
    }

    var nextMilestone: StreakMilestone? {
        if let current = streak.milestoneReached {
            return current.next
        }
        return .spark
    }

    var daysToNextMilestone: Int {
        guard let next = nextMilestone else { return 0 }
        return max(next.threshold - streak.currentStreak, 0)
    }

    // MARK: - Dependencies

    private let session: UserSession
    private let syncService: SyncService
    private let streakService: StreakService

    // MARK: - Init

    init(
        session: UserSession? = nil,
        syncService: (any SyncService)? = nil,
        streakService: (any StreakService)? = nil
    ) {
        self.session = session ?? .demo
        self.syncService = syncService ?? MockSyncService()
        self.streakService = streakService ?? MockStreakService()
    }

    // MARK: - Load

    func loadStats() {
        guard loadState != .loading else { return }
        loadState = .loading

        Task {
            do {
                async let streakResult = streakService.fetchStreak(coupleId: session.coupleId)
                async let scoresResult = syncService.fetchRecentScores(
                    coupleId: session.coupleId, days: 7
                )

                let fetchedStreak = try await streakResult
                let fetchedScores = try await scoresResult

                streak = fetchedStreak
                weeklyScores = fetchedScores.sorted { $0.date < $1.date }
                weeklyAverage = syncService.calculateWeeklyAverage(scores: fetchedScores)
                trend = syncService.calculateTrend(scores: fetchedScores)

                // Today's score is the most recent
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                let todayString = dateFormatter.string(from: Date())
                todaySyncScore = fetchedScores.first { $0.date == todayString }

                loadState = .loaded
            } catch {
                loadState = .error("Couldn't load stats. Pull to refresh.")
            }
        }
    }

    func refresh() {
        loadState = .idle
        loadStats()
    }

    // MARK: - Future AI Hook

    /// Placeholder: AI-powered explanation for sync score changes
    func explainSyncScoreDrop(current: SyncScore, previous: SyncScore) async -> String? {
        // Future: Call AI with both scores + partner profile
        // Example response: "You were both stressed yesterday,
        //   but today Alex bounced back while you're still feeling low.
        //   A quick check-in might help you reconnect."
        return nil
    }
}
