//
//  QuizOrchestrator.swift
//  Coupley
//
//  Decides when and which quiz to suggest inside the chat.
//  Default implementation is rule-based + curated bank; swap in AI later by
//  implementing the same protocol.
//

import Foundation
import FirebaseFirestore

// MARK: - Protocol

protocol QuizOrchestrating {
    /// Returns a new quiz to post, or nil if the couple shouldn't be bothered yet.
    func nextQuiz(coupleId: String,
                  profile: CoupleInsightProfile,
                  recentQuizzes: [ChatQuiz],
                  lastSuggestedAt: Date?) async -> ChatQuiz?
}

// MARK: - Rule-based default

final class DefaultQuizOrchestrator: QuizOrchestrating {

    /// Minimum gap between suggestions.
    private let minGapSeconds: TimeInterval = 24 * 60 * 60

    func nextQuiz(coupleId: String,
                  profile: CoupleInsightProfile,
                  recentQuizzes: [ChatQuiz],
                  lastSuggestedAt: Date?) async -> ChatQuiz? {

        // 1. Anti-spam: only one suggestion per 24h.
        if let last = lastSuggestedAt,
           Date().timeIntervalSince(last) < minGapSeconds {
            return nil
        }

        // 2. Don't pile on if there's already an unanswered quiz.
        let hasPending = recentQuizzes.contains { $0.status != .complete }
        if hasPending { return nil }

        // 3. Pick the next template, prioritising underexplored topics.
        let askedIds = Set(recentQuizzes.map { $0.questionId })
        let template = pickTemplate(profile: profile, excluding: askedIds)
        guard let template else { return nil }

        return makeQuiz(from: template)
    }

    // MARK: Selection

    private func pickTemplate(profile: CoupleInsightProfile,
                              excluding excluded: Set<String>) -> ChatQuizTemplate? {

        let pool = ChatQuizBank.all.filter { !excluded.contains($0.questionId) }
        guard !pool.isEmpty else {
            // Let them repeat a topic eventually.
            return ChatQuizBank.all.randomElement()
        }

        // Priority 1: topics with no answers yet.
        let coveredTopics = Set(profile.topics.compactMap { key, value in
            value.answeredCount > 0 ? key : nil
        })
        let uncoveredPool = pool.filter { !coveredTopics.contains($0.topic.rawValue) }
        if let pick = uncoveredPool.randomElement() { return pick }

        // Priority 2: topics with the lowest confidence.
        let sortedPool = pool.sorted { a, b in
            confidence(for: a.topic, in: profile) < confidence(for: b.topic, in: profile)
        }
        return sortedPool.first
    }

    private func confidence(for topic: QuizTopic, in profile: CoupleInsightProfile) -> Int {
        guard let t = profile.topics[topic.rawValue] else { return 0 }
        let a = t.userA?.confidence ?? 0
        let b = t.userB?.confidence ?? 0
        return (a + b) / 2
    }

    // MARK: Build

    private func makeQuiz(from t: ChatQuizTemplate) -> ChatQuiz {
        ChatQuiz(
            id: UUID().uuidString,
            questionId: t.questionId,
            topic: t.topic,
            question: t.question,
            subtitle: t.subtitle,
            options: t.options,
            allowsMultiple: t.allowsMultiple,
            createdAt: Date(),
            status: .pending,
            answers: [:],
            result: nil
        )
    }
}

// MARK: - Insight generator (rule-based, AI-ready)

/// Builds the comparison text shown in the chat after both answer.
/// Swap in an AI implementation to make the tone warmer.
protocol InsightGenerating {
    func buildResult(for quiz: ChatQuiz, userAId: String, userBId: String) -> ChatQuizResult
}

final class DefaultInsightGenerator: InsightGenerating {

    func buildResult(for quiz: ChatQuiz, userAId: String, userBId: String) -> ChatQuizResult {

        let aAnswer = quiz.answers[userAId]
        let bAnswer = quiz.answers[userBId]

        // Treat overlap of selected options OR equal text as "match".
        let aSet = Set(aAnswer?.options ?? [])
        let bSet = Set(bAnswer?.options ?? [])
        let optionOverlap = aSet.intersection(bSet)

        let aText = (aAnswer?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let bText = (bAnswer?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let textMatches = !aText.isEmpty && aText == bText

        let isMatch = !optionOverlap.isEmpty || textMatches

        let summary: String
        if isMatch {
            if let shared = optionOverlap.first {
                summary = "You both value \(shared.lowercased()) \(quiz.topic.emoji)"
            } else {
                summary = "You're on the same page here \(quiz.topic.emoji)"
            }
        } else {
            summary = "You see \(quiz.topic.label.lowercased()) a little differently — might be worth a chat."
        }

        var traits: [String: String] = [:]
        if let a = aAnswer?.options.first { traits["userA"] = a }
        if let b = bAnswer?.options.first { traits["userB"] = b }

        return ChatQuizResult(
            match: isMatch,
            summary: summary,
            emoji: quiz.topic.emoji,
            traits: traits,
            postedAt: Date(),
            postedByClientId: ""     // filled by the service at transaction time
        )
    }
}
