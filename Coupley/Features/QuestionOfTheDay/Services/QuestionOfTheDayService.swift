//
//  QuestionOfTheDayService.swift
//  Coupley
//
//  Creates and observes the one shared question a couple gets each day.
//
//  Why there is no calendar-day key
//  --------------------------------
//  The obvious design — a document id of `qotd-2026-11-12` — breaks for
//  couples in different timezones: they'd compute different keys and answer
//  different questions. Anchoring to UTC instead moves the problem rather
//  than solving it (a couple in California would see the question change at
//  4pm).
//
//  So the day boundary is expressed as elapsed time, not as a date: a new
//  question becomes available `refreshInterval` after the last one was
//  created. Both partners simply read whichever QotD is newest, so they
//  cannot diverge no matter where they are.
//
//  Why a transaction
//  -----------------
//  Both phones may open within the same second. The sequence counter and the
//  creation timestamp live on the couple document and are read-then-written
//  inside one transaction, so exactly one client wins and the loser becomes
//  a no-op.
//

import Foundation
import FirebaseFirestore

// MARK: - Protocol

protocol QuestionOfTheDayServicing {

    /// Streams the couple's most recent daily question.
    func observeCurrent(
        coupleId: String,
        onUpdate: @escaping (ChatQuiz?) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration

    /// Creates today's question if one is due. Safe to call on every app
    /// open and from both devices at once.
    /// - Returns: `true` if this call created the question.
    @discardableResult
    func ensureCurrentQuestion(coupleId: String, userId: String) async throws -> Bool
}

// MARK: - Firestore implementation

final class FirestoreQuestionOfTheDayService: QuestionOfTheDayServicing {

    /// Earliest a new question may appear after the previous one. Slightly
    /// under 24h so the question never arrives *later* in the day than it did
    /// yesterday — the rotation drifts earlier, never later.
    static let refreshInterval: TimeInterval = 20 * 3600

    /// A question nobody touched is not replaced right away: a fresh one
    /// wouldn't help, and each creation pings the partner. After this long an
    /// untouched question rotates out anyway so the card can't go stale.
    static let staleUnansweredInterval: TimeInterval = 72 * 3600

    private let db = Firestore.firestore()

    // MARK: - Observe

    func observeCurrent(
        coupleId: String,
        onUpdate: @escaping (ChatQuiz?) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        db.collection(FirestorePath.chatQuizzes(coupleId: coupleId))
            .whereField("kind", isEqualTo: ChatQuizKind.questionOfTheDay.rawValue)
            .order(by: "createdAt", descending: true)
            .limit(to: 1)
            .addSnapshotListener { snapshot, error in
                if let error {
                    onError(error)
                    return
                }
                let quiz = snapshot?.documents
                    .compactMap { try? $0.data(as: ChatQuiz.self) }
                    .first
                onUpdate(quiz)
            }
    }

    // MARK: - Create

    @discardableResult
    func ensureCurrentQuestion(coupleId: String, userId: String) async throws -> Bool {
        guard !coupleId.isEmpty else { return false }

        let coupleRef = db.collection(FirestorePath.couples).document(coupleId)

        let created = try await db.runTransaction { transaction, errorPointer -> Any? in
            do {
                let coupleSnap = try transaction.getDocument(coupleRef)
                let coupleData = coupleSnap.data() ?? [:]

                let lastCreatedAt = (coupleData["qotdLastCreatedAt"] as? Timestamp)?.dateValue()
                let lastQuizId    = coupleData["qotdCurrentId"] as? String
                let sequence      = (coupleData["qotdSequence"] as? Int ?? 0) + 1

                // Reads must all happen before any write in a transaction, so
                // the previous question is fetched up front even though it is
                // only needed in one branch.
                var previous: ChatQuiz?
                if let lastQuizId {
                    let ref = self.db
                        .collection(FirestorePath.chatQuizzes(coupleId: coupleId))
                        .document(lastQuizId)
                    previous = try? transaction.getDocument(ref).data(as: ChatQuiz.self)
                }

                guard Self.isQuestionDue(lastCreatedAt: lastCreatedAt, previous: previous) else {
                    return false
                }

                guard let template = ChatQuizBank.questionOfTheDay(
                    coupleId: coupleId,
                    sequence: sequence
                ) else {
                    return false
                }

                // `qotd-{sequence}` is unique because the transaction owns the
                // counter — two racing clients cannot both reach this line
                // with the same sequence.
                let quizId = "qotd-\(sequence)"
                let quiz = ChatQuiz(
                    id: quizId,
                    questionId: template.questionId,
                    topic: template.topic,
                    question: template.question,
                    subtitle: template.subtitle,
                    options: template.optionLabels,
                    optionIds: template.optionIds,
                    allowsMultiple: template.allowsMultiple,
                    createdAt: Date(),
                    status: .pending,
                    answers: [:],
                    result: nil,
                    authorId: nil,
                    authorAnswer: nil,
                    customNote: nil,
                    kind: .questionOfTheDay,
                    triggeredBy: userId
                )

                let quizRef = self.db
                    .collection(FirestorePath.chatQuizzes(coupleId: coupleId))
                    .document(quizId)
                try transaction.setData(from: quiz, forDocument: quizRef)

                // Mirror into chat so the question joins the couple's history
                // and the archive keeps growing — that archive is the point.
                let messageRef = self.db
                    .collection(FirestorePath.messages(coupleId: coupleId))
                    .document()
                try transaction.setData(
                    from: ChatMessage.quizCard(quizId: quizId),
                    forDocument: messageRef
                )

                transaction.setData([
                    "qotdSequence":      sequence,
                    "qotdCurrentId":     quizId,
                    "qotdLastCreatedAt": FieldValue.serverTimestamp(),
                    "lastMessageAt":     FieldValue.serverTimestamp()
                ], forDocument: coupleRef, merge: true)

                return true
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }
        }

        return (created as? Bool) ?? false
    }

    // MARK: - Scheduling rule

    /// A new question is due when enough time has passed *and* the previous
    /// one actually got some engagement. An untouched question is given a
    /// longer grace period rather than being replaced daily, so a couple who
    /// stopped answering doesn't collect a push a day.
    static func isQuestionDue(lastCreatedAt: Date?, previous: ChatQuiz?) -> Bool {
        guard let lastCreatedAt else { return true }      // never had one

        let age = Date().timeIntervalSince(lastCreatedAt)
        guard age >= refreshInterval else { return false }

        // Someone engaged → keep the daily rhythm going.
        if let previous, !previous.answers.isEmpty { return true }

        // Nobody answered → hold the question, but not forever.
        return age >= staleUnansweredInterval
    }
}
