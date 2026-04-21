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

final class FirestoreCoupleInsightAggregator: CoupleInsightAggregating {

    private let db = Firestore.firestore()

    func listenToProfile(coupleId: String,
                         onUpdate: @escaping (CoupleInsightProfile) -> Void,
                         onError: @escaping (Error) -> Void) -> ListenerRegistration {
        db.document(FirestorePath.coupleProfileCurrent(coupleId: coupleId))
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

        guard quiz.status == .complete,
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
                        summary: self.primaryTrait(aAnswer),
                        quizId: quiz.id
                    )
                    topic.userB = self.merge(
                        existing: topic.userB,
                        userId: userBId,
                        summary: self.primaryTrait(bAnswer),
                        quizId: quiz.id
                    )

                    // Shared / differences
                    let aOptions = Set(aAnswer.options)
                    let bOptions = Set(bAnswer.options)
                    let shared = aOptions.intersection(bOptions)
                    let differences = aOptions.symmetricDifference(bOptions)

                    topic.sharedTraits = Array(Set(topic.sharedTraits).union(shared))
                    topic.differences  = Array(Set(topic.differences).union(differences))

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
                       quizId: String) -> CoupleInsightProfile.PartnerTrait {
        var samples = existing?.sampleQuizIds ?? []
        if !samples.contains(quizId) { samples.append(quizId) }
        let confidence = min(100, samples.count * 15)  // 7 quizzes → 100%
        return .init(userId: userId,
                     summary: summary,
                     confidence: confidence,
                     sampleQuizIds: samples)
    }

    private func primaryTrait(_ answer: ChatQuizAnswer) -> String {
        if let first = answer.options.first { return first }
        if let text = answer.text, !text.isEmpty { return text }
        return "—"
    }
}
