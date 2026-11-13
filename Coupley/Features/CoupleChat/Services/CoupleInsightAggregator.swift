//
//  CoupleInsightAggregator.swift
//  Coupley
//
//  Merges completed quizzes into the single aggregated CoupleInsightProfile
//  document at couples/{coupleId}/coupleProfile/current.
//
//  Runs inside a Firestore transaction so concurrent clients can't clobber
//  each other's merges.
//

import Foundation
import FirebaseFirestore

protocol CoupleInsightAggregating {
    /// Listen for the aggregated profile. The caller owns the lifetime.
    func listenToProfile(coupleId: String,
                         onUpdate: @escaping (CoupleInsightProfile) -> Void,
                         onError: @escaping (Error) -> Void) -> ListenerRegistration

    /// Merge a completed quiz into the profile. No-op if the quiz is not yet
    /// complete. Safe to call from multiple devices simultaneously.
    func aggregate(_ quiz: ChatQuiz,
                   coupleId: String,
                   userAId: String,
                   userBId: String) async throws
}

/// No-op registration returned when we can't start a real listener (e.g. solo
/// session without a coupleId). Keeps the call site signature simple and
/// avoids a crash from Firestore's "Paths must not contain //" check.
private final class NoOpListenerRegistration: NSObject, ListenerRegistration {
    func remove() {}
}

final class FirestoreCoupleInsightAggregator: CoupleInsightAggregating {

    private let db = Firestore.firestore()

    func listenToProfile(coupleId: String,
                         onUpdate: @escaping (CoupleInsightProfile) -> Void,
                         onError: @escaping (Error) -> Void) -> ListenerRegistration {
        guard !coupleId.isEmpty else {
            onUpdate(.empty)
            return NoOpListenerRegistration()
        }
        return db.document(FirestorePath.coupleProfileCurrent(coupleId: coupleId))
            .addSnapshotListener { snap, error in
                if let error { onError(error); return }
                guard let snap, snap.exists else {
                    onUpdate(.empty); return
                }
                if let profile = try? snap.data(as: CoupleInsightProfile.self) {
                    onUpdate(profile)
                } else {
                    onUpdate(.empty)
                }
            }
    }

    func aggregate(_ quiz: ChatQuiz,
                   coupleId: String,
                   userAId: String,
                   userBId: String) async throws {

        guard !coupleId.isEmpty,
              !userAId.isEmpty,
              !userBId.isEmpty,
              quiz.status == .complete,
              let result = quiz.result,
              let aAnswer = quiz.answers[userAId],
              let bAnswer = quiz.answers[userBId] else { return }

        let ref = db.document(FirestorePath.coupleProfileCurrent(coupleId: coupleId))

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            db.runTransaction({ tx, errorPointer -> Any? in
                do {
                    let snap = try tx.getDocument(ref)
                    var profile: CoupleInsightProfile
                    if snap.exists, let loaded = try? snap.data(as: CoupleInsightProfile.self) {
                        profile = loaded
                    } else {
                        profile = .empty
                    }

                    // Upsert the topic
                    var topic = profile.topics[quiz.topic.rawValue] ?? .empty
                    topic.answeredCount += 1
                    topic.lastUpdatedAt = Date()

                    topic.userA = self.merge(
                        existing: topic.userA,
                        userId: userAId,
                        summary: self.primaryTrait(aAnswer, in: quiz),
                        refs: self.traitRefs(aAnswer, in: quiz),
                        quizId: quiz.id
                    )
                    topic.userB = self.merge(
                        existing: topic.userB,
                        userId: userBId,
                        summary: self.primaryTrait(bAnswer, in: quiz),
                        refs: self.traitRefs(bAnswer, in: quiz),
                        quizId: quiz.id
                    )

                    // Shared / differences.
                    //
                    // Compared by stable id, not display text. The old code
                    // set-differenced the two stored label arrays, so two
                    // partners whose apps worded a choice differently had
                    // every answer pushed wholly into `differences` — and
                    // because both arrays are accumulated with `union`, the
                    // profile kept every spelling of the same concept
                    // permanently. That is corruption a code fix cannot
                    // undo, which is why it had to stop before any
                    // translation shipped rather than after.
                    let aIds = Set(quiz.stableIds(for: aAnswer))
                    let bIds = Set(quiz.stableIds(for: bAnswer))
                    let sharedIds = aIds.intersection(bIds)
                    let differingIds = aIds.symmetricDifference(bIds)

                    let makeRef = { QuizOptionRef.make(questionId: quiz.questionId, optionId: $0) }
                    // Sorted, not `Array(Set(...))`: Swift seeds String
                    // hashing per process, so an unsorted Set would write a
                    // different order to Firestore on every run and the
                    // profile's chips would reshuffle for no reason.
                    topic.sharedTraitRefs = Set(topic.sharedTraitRefs ?? [])
                        .union(sharedIds.map(makeRef)).sorted()
                    topic.differenceRefs = Set(topic.differenceRefs ?? [])
                        .union(differingIds.map(makeRef)).sorted()

                    // Legacy mirrors, so a build without ref support still
                    // draws something — and so the two arrays stay comparable.
                    // Base language, not this device's: the shipped build
                    // unions into these same arrays, and two spellings of one
                    // concept would both survive forever.
                    let sharedLabels = sharedIds.map { quiz.baseLabel(forOptionId: $0) }
                    let differingLabels = differingIds.map { quiz.baseLabel(forOptionId: $0) }
                    topic.sharedTraits = Set(topic.sharedTraits).union(sharedLabels).sorted()
                    topic.differences  = Set(topic.differences).union(differingLabels).sorted()

                    profile.topics[quiz.topic.rawValue] = topic

                    // Confidence: total answered quizzes * 5, capped at 100.
                    let totalAnswered = profile.topics.values
                        .map { $0.answeredCount }.reduce(0, +)
                    profile.confidenceScore = min(100, totalAnswered * 5)
                    profile.updatedAt = Date()

                    try tx.setData(from: profile, forDocument: ref)
                    _ = result                       // kept for future AI use
                    return nil
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }
            }) { _, error in
                if let error { cont.resume(throwing: error) }
                else         { cont.resume() }
            }
        }
    }

    // MARK: - Helpers

    private func merge(existing: CoupleInsightProfile.PartnerTrait?,
                       userId: String,
                       summary: String,
                       refs: [String]?,
                       quizId: String) -> CoupleInsightProfile.PartnerTrait {
        var samples = existing?.sampleQuizIds ?? []
        if !samples.contains(quizId) { samples.append(quizId) }
        let confidence = min(100, samples.count * 15)  // 7 quizzes → 100%
        return .init(userId: userId,
                     summary: summary,
                     confidence: confidence,
                     sampleQuizIds: samples,
                     summaryRefs: refs)
    }

    /// Legacy joined text, base language. Falls back to what the answer
    /// actually stored rather than to the placeholder: an option the bank can
    /// no longer resolve should read as itself, not as "—".
    private func primaryTrait(_ answer: ChatQuizAnswer, in quiz: ChatQuiz) -> String {
        let labels = quiz.stableIds(for: answer)
            .map { quiz.baseLabel(forOptionId: $0) }
        if !labels.isEmpty { return labels.joined(separator: ", ") }
        if !answer.options.isEmpty { return answer.options.joined(separator: ", ") }
        if let text = answer.text, !text.isEmpty { return text }
        return "—"
    }

    /// References behind that line, so a reader can rebuild it in their own
    /// language. Nil for a free-text answer, whose `summary` is the user's own
    /// words and is already correct as stored.
    private func traitRefs(_ answer: ChatQuizAnswer, in quiz: ChatQuiz) -> [String]? {
        let ids = quiz.stableIds(for: answer)
        guard !ids.isEmpty else { return nil }
        return ids.map { QuizOptionRef.make(questionId: quiz.questionId, optionId: $0) }
    }
}
