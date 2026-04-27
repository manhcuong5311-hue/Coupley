//
//  SampleTogetherData.swift
//  Coupley
//
//  Hand-curated previewable data for SwiftUI #Preview blocks and the mock
//  service implementations. Kept in one place so visuals stay consistent
//  between previews and so adjusting copy doesn't require touching three files.
//

import Foundation

enum SampleTogetherData {

    static let userId    = "user_001"
    static let partnerId = "user_002"

    static let goals: [TogetherGoal] = {
        let cal = Calendar.current
        let now = Date()
        return [
            TogetherGoal(
                id: "g1",
                title: "Japan Trip Fund",
                category: .travel,
                colorway: .ocean,
                trackingMode: .currency,
                target: 5000,
                contribution: TogetherContribution(amounts: [
                    userId: 2200, partnerId: 1400
                ]),
                dueDate: cal.date(byAdding: .month, value: 5, to: now),
                note: "Two weeks. Tokyo + Kyoto. The big one.",
                createdBy: userId,
                createdAt: cal.date(byAdding: .day, value: -42, to: now) ?? now,
                updatedAt: cal.date(byAdding: .day, value: -2, to: now) ?? now,
                completedAt: nil
            ),
            TogetherGoal(
                id: "g2",
                title: "Wedding Savings",
                category: .wedding,
                colorway: .blossom,
                trackingMode: .currency,
                target: 25000,
                contribution: TogetherContribution(amounts: [
                    userId: 5800, partnerId: 4400
                ]),
                dueDate: cal.date(byAdding: .month, value: 18, to: now),
                note: "Our day. Slowly, but ours.",
                createdBy: partnerId,
                createdAt: cal.date(byAdding: .day, value: -90, to: now) ?? now,
                updatedAt: cal.date(byAdding: .day, value: -6, to: now) ?? now,
                completedAt: nil
            ),
            TogetherGoal(
                id: "g3",
                title: "Gym Together",
                category: .health,
                colorway: .ember,
                trackingMode: .count,
                target: 20,
                contribution: TogetherContribution(amounts: [
                    userId: 7, partnerId: 7
                ]),
                dueDate: cal.date(byAdding: .day, value: 8, to: now),
                note: "20 sessions in a month. Side by side.",
                createdBy: userId,
                createdAt: cal.date(byAdding: .day, value: -22, to: now) ?? now,
                updatedAt: cal.date(byAdding: .day, value: -1, to: now) ?? now,
                completedAt: nil
            )
        ]
    }()

    static let challenges: [CoupleChallenge] = {
        let cal = Calendar.current
        let now = Date()
        let log: [Date] = (0..<12).compactMap { cal.date(byAdding: .day, value: -$0, to: now) }
        return [
            CoupleChallenge(
                id: "c1",
                title: "30 Days Gratitude",
                category: .gratitude,
                colorway: .dawn,
                cadence: .daily,
                targetCount: 30,
                contribution: TogetherContribution(amounts: [userId: 6, partnerId: 6]),
                checkInLog: log,
                streak: TogetherStreak(current: 12, longest: 12, lastCheckIn: now),
                startDate: cal.date(byAdding: .day, value: -12, to: now) ?? now,
                createdBy: userId,
                createdAt: cal.date(byAdding: .day, value: -12, to: now) ?? now,
                updatedAt: now,
                completedAt: nil
            )
        ]
    }()

    static let dreams: [Dream] = {
        let cal = Calendar.current
        let now = Date()
        return [
            Dream(
                id: "d1",
                title: "Japan Together",
                category: .travel,
                colorway: .ocean,
                horizon: .nextYear,
                photoURL: nil,
                note: "Tokyo at night. Kyoto in the morning.",
                inspiration: "Cherry blossoms with you.",
                firstStep: "Open the savings goal — we already started.",
                createdBy: userId,
                createdAt: cal.date(byAdding: .day, value: -50, to: now) ?? now,
                updatedAt: cal.date(byAdding: .day, value: -50, to: now) ?? now
            ),
            Dream(
                id: "d2",
                title: "Our First Home",
                category: .home,
                colorway: .meadow,
                horizon: .fiveYears,
                photoURL: nil,
                note: "A door with both our names.",
                inspiration: "A kitchen we picked together.",
                firstStep: "Start an Apartment Fund goal.",
                createdBy: partnerId,
                createdAt: cal.date(byAdding: .day, value: -38, to: now) ?? now,
                updatedAt: cal.date(byAdding: .day, value: -38, to: now) ?? now
            ),
            Dream(
                id: "d3",
                title: "A Small Dog",
                category: .pet,
                colorway: .dawn,
                horizon: .thisYear,
                photoURL: nil,
                note: "Slow mornings with three sets of footprints.",
                inspiration: "The third member of our family.",
                firstStep: "Talk through breed, vet, time off work.",
                createdBy: userId,
                createdAt: cal.date(byAdding: .day, value: -10, to: now) ?? now,
                updatedAt: cal.date(byAdding: .day, value: -10, to: now) ?? now
            )
        ]
    }()
}
