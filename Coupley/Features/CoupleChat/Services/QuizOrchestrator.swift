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
            options: t.optionLabels,
            optionIds: t.optionIds,
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
        //
        // Compared by stable id, not by display text. The old version
        // intersected the two stored label arrays, so two partners whose apps
        // rendered the same choice differently never intersected: every
        // result came back `match: false` and every answer was filed as a
        // difference.
        //
        // `sharedOptionIds` returns them in the quiz's own option order. The
        // old code took `Set.first`, which for the seven multi-select
        // templates named a different option on different runs.
        let optionOverlap = quiz.sharedOptionIds(userAId, userBId)

        let aText = (aAnswer?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let bText = (bAnswer?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let textMatches = !aText.isEmpty && aText == bText

        let isMatch = !optionOverlap.isEmpty || textMatches

        // The verdict is stored as a shape plus its parameters, so each
        // partner renders it in their own language. The prose below is still
        // written alongside it, for documents read by a build that predates
        // `kind` — and it is the reason history cannot be localized
        // retroactively: every result already in Firestore has only this.
        let kind: QuizResultKind
        let sharedId: String?
        if isMatch {
            if let shared = optionOverlap.first {
                kind = .matchShared
                sharedId = shared
            } else {
                kind = .matchGeneric
                sharedId = nil
            }
        } else {
            kind = .mismatch
            sharedId = nil
        }

        // Base language, because it is written into Firestore and read by
        // builds that have no idea which language wrote it.
        let sharedLabel = sharedId.map { quiz.baseLabel(forOptionId: $0) }

        let summary = QuizResultCopy.baseSentence(
            kind: kind,
            optionLabel: sharedLabel,
            emoji: quiz.topic.emoji,
            topicLabel: quiz.topic.baseLabel
        )

        // Write-only field, kept so existing documents keep their shape and
        // their encoding: still base-language display text, as the shipped
        // build writes it. Changing what an existing field means is not worth
        // doing for data nothing reads.
        var traits: [String: String] = [:]
        if let a = quiz.baseLabels(ofUser: userAId).first { traits["userA"] = a }
        if let b = quiz.baseLabels(ofUser: userBId).first { traits["userB"] = b }

        return ChatQuizResult(
            match: isMatch,
            summary: summary,
            emoji: quiz.topic.emoji,
            traits: traits,
            postedAt: Date(),
            postedByClientId: "",    // filled by the service at transaction time
            kind: kind,
            sharedOptionId: sharedId,
            sharedOptionLabel: sharedLabel
        )
    }
}
