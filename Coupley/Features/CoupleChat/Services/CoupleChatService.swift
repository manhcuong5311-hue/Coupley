//
//  CoupleChatService.swift
//  Coupley
//
//  Firestore-backed real-time chat + quiz service.
//  Mirrors the pattern used in MoodListenerService / PresenceService:
//    - protocol
//    - closure callbacks
//    - returns ListenerRegistration for caller cleanup
//

import Foundation
import FirebaseFirestore

// MARK: - Protocol

protocol CoupleChatServicing {

    /// Stream the most recent N messages for this couple, newest last.
    /// `pendingIds` contains the IDs of messages whose write hasn't yet
    /// been acknowledged by the server — used to render a "Sending…" state.
    func listenToMessages(coupleId: String,
                          limit: Int,
                          onUpdate: @escaping (_ messages: [ChatMessage],
                                               _ pendingIds: Set<String>) -> Void,
                          onError: @escaping (Error) -> Void) -> ListenerRegistration

    /// One-shot paginated fetch of messages older than `before`. Used to
    /// power infinite upward scroll. Returns up to `limit` messages,
    /// oldest-first.
    func loadOlderMessages(coupleId: String,
                           before: Date,
                           limit: Int) async throws -> [ChatMessage]

    /// Stream the active (non-complete) quizzes so both clients can react when
    /// their partner answers.
    func listenToQuizzes(coupleId: String,
                         onUpdate: @escaping ([ChatQuiz]) -> Void,
                         onError: @escaping (Error) -> Void) -> ListenerRegistration

    // Writes

    func sendText(_ body: String, coupleId: String, senderId: String) async throws
    func postSystemMessage(_ body: String, coupleId: String) async throws
    func postQuiz(_ quiz: ChatQuiz, coupleId: String) async throws

    /// Submit this user's answer. If they are the second answerer, this call
    /// also posts the comparison result atomically.
    /// - Returns: the resulting `ChatQuiz` (with `status` updated). If the
    ///   status is `.complete`, the caller should also run profile aggregation.
    func submitAnswer(_ answer: ChatQuizAnswer,
                      quizId: String,
                      coupleId: String,
                      userId: String,
                      otherUserId: String,
                      resultBuilder: @escaping (ChatQuiz) -> ChatQuizResult) async throws -> ChatQuiz

    /// Mark all unread messages as read by this user (writes readBy in batches).
    func markAsRead(coupleId: String, userId: String, messageIds: [String]) async throws
}

// MARK: - Firestore implementation

final class FirestoreCoupleChatService: CoupleChatServicing {

    private let db = Firestore.firestore()
    private let clientId = UUID().uuidString   // per-launch arbitration token

    // MARK: Listeners

    func listenToMessages(coupleId: String,
                          limit: Int = 50,
                          onUpdate: @escaping (_ messages: [ChatMessage],
                                               _ pendingIds: Set<String>) -> Void,
                          onError: @escaping (Error) -> Void) -> ListenerRegistration {
        // `includeMetadataChanges` so we're notified when a locally-cached
        // write gets ack'd by the server (hasPendingWrites flips false),
        // which is how the "Sending… → Sent" UI transition is driven.
        db.collection(FirestorePath.messages(coupleId: coupleId))
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
            .addSnapshotListener(includeMetadataChanges: true) { snapshot, error in
                if let error {
                    onError(error); return
                }
                let docs = snapshot?.documents ?? []
                var pending: Set<String> = []
                let messages: [ChatMessage] = docs.compactMap { doc in
                    guard let msg = try? doc.data(as: ChatMessage.self) else { return nil }
                    if doc.metadata.hasPendingWrites { pending.insert(msg.id) }
                    return msg
                }
                // Listener returns newest-first; callers want oldest-first for a chat feed.
                onUpdate(messages.reversed(), pending)
            }
    }

    func loadOlderMessages(coupleId: String,
                           before: Date,
                           limit: Int = 50) async throws -> [ChatMessage] {
        let snap = try await db.collection(FirestorePath.messages(coupleId: coupleId))
            .order(by: "createdAt", descending: true)
            .whereField("createdAt", isLessThan: Timestamp(date: before))
            .limit(to: limit)
            .getDocuments()
        let msgs = snap.documents.compactMap { try? $0.data(as: ChatMessage.self) }
        return msgs.reversed()
    }

    func listenToQuizzes(coupleId: String,
                         onUpdate: @escaping ([ChatQuiz]) -> Void,
                         onError: @escaping (Error) -> Void) -> ListenerRegistration {
        db.collection(FirestorePath.chatQuizzes(coupleId: coupleId))
            .order(by: "createdAt", descending: true)
            .limit(to: 20)
            .addSnapshotListener { snapshot, error in
                if let error {
                    onError(error); return
                }
                let docs = snapshot?.documents ?? []
                let quizzes = docs.compactMap { try? $0.data(as: ChatQuiz.self) }
                onUpdate(quizzes)
            }
    }

    // MARK: Writes

    func sendText(_ body: String, coupleId: String, senderId: String) async throws {
        let msg = ChatMessage.text(body, senderId: senderId)
        try await writeMessage(msg, coupleId: coupleId)
        try await touchLastMessage(coupleId: coupleId)
    }

    func postSystemMessage(_ body: String, coupleId: String) async throws {
        let msg = ChatMessage.system(body)
        try await writeMessage(msg, coupleId: coupleId)
        try await touchLastMessage(coupleId: coupleId)
    }

    func postQuiz(_ quiz: ChatQuiz, coupleId: String) async throws {
        let quizRef = db.collection(FirestorePath.chatQuizzes(coupleId: coupleId))
            .document(quiz.id)
        let msgRef = db.collection(FirestorePath.messages(coupleId: coupleId))
            .document()
        let card = ChatMessage.quizCard(quizId: quiz.id)

        let batch = db.batch()
        try batch.setData(from: quiz, forDocument: quizRef)
        try batch.setData(from: card, forDocument: msgRef)
        batch.setData([
            "lastQuizSuggestedAt": FieldValue.serverTimestamp(),
            "lastMessageAt":       FieldValue.serverTimestamp()
        ], forDocument: db.collection(FirestorePath.couples).document(coupleId),
           merge: true)

        try await batch.commit()
    }

    /// Core of the double-answer race.
    ///
    /// Uses a Firestore transaction that:
    ///   1. reads the quiz doc
    ///   2. bails if this user already answered (idempotent)
    ///   3. writes this user's answer
    ///   4. if both users have answered, marks the quiz complete, writes
    ///      the result payload, and writes a `result` message atomically
    ///
    /// If two devices submit simultaneously, at most one transaction sees
    /// both answers present and therefore at most one result message is
    /// written. `postedByClientId` is included so conflicts are auditable.
    func submitAnswer(_ answer: ChatQuizAnswer,
                      quizId: String,
                      coupleId: String,
                      userId: String,
                      otherUserId: String,
                      resultBuilder: @escaping (ChatQuiz) -> ChatQuizResult) async throws -> ChatQuiz {

        let quizRef = db.collection(FirestorePath.chatQuizzes(coupleId: coupleId))
            .document(quizId)
        let messagesRef = db.collection(FirestorePath.messages(coupleId: coupleId))
        let coupleRef = db.collection(FirestorePath.couples).document(coupleId)
        let clientId = self.clientId

        // Run in a transaction, then decode the committed quiz for the caller.
        let updatedQuiz: ChatQuiz = try await withCheckedThrowingContinuation { cont in
            db.runTransaction({ tx, errorPointer -> Any? in
                do {
                    let snap = try tx.getDocument(quizRef)
                    guard var quiz = try? snap.data(as: ChatQuiz.self) else {
                        throw CoupleChatError.quizNotFound
                    }

                    // Idempotent: don't overwrite an existing answer.
                    if quiz.answers[userId] == nil {
                        quiz.answers[userId] = answer
                    }

                    let bothAnswered = quiz.answers[userId] != nil
                                    && quiz.answers[otherUserId] != nil

                    if bothAnswered && quiz.result == nil {
                        // Second answerer posts the result inside the same tx.
                        var result = resultBuilder(quiz)
                        result = ChatQuizResult(
                            match: result.match,
                            summary: result.summary,
                            emoji: result.emoji,
                            traits: result.traits,
                            postedAt: Date(),
                            postedByClientId: clientId
                        )
                        quiz.result = result
                        quiz.status = .complete

                        let resultMsg = ChatMessage.resultCard(
                            quizId: quiz.id,
                            summary: result.summary,
                            emoji: result.emoji,
                            match: result.match
                        )
                        try tx.setData(from: resultMsg,
                                       forDocument: messagesRef.document(resultMsg.id))
                        tx.setData(["lastMessageAt": FieldValue.serverTimestamp()],
                                   forDocument: coupleRef, merge: true)
                    } else if bothAnswered {
                        quiz.status = .complete
                    } else {
                        quiz.status = .partial
                    }

                    try tx.setData(from: quiz, forDocument: quizRef)
                    return quiz
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }
            }) { result, error in
                if let error { cont.resume(throwing: error); return }
                guard let quiz = result as? ChatQuiz else {
                    cont.resume(throwing: CoupleChatError.transactionFailed); return
                }
                cont.resume(returning: quiz)
            }
        }

        return updatedQuiz
    }

    func markAsRead(coupleId: String, userId: String, messageIds: [String]) async throws {
        guard !messageIds.isEmpty else { return }
        // Firestore batch is 500 ops max — chunk if necessary.
        for chunk in messageIds.chunked(into: 450) {
            let batch = db.batch()
            for id in chunk {
                let ref = db.collection(FirestorePath.messages(coupleId: coupleId))
                    .document(id)
                batch.updateData(["readBy": FieldValue.arrayUnion([userId])],
                                 forDocument: ref)
            }
            try await batch.commit()
        }
    }

    // MARK: - Helpers

    private func writeMessage(_ msg: ChatMessage, coupleId: String) async throws {
        let ref = db.collection(FirestorePath.messages(coupleId: coupleId))
            .document(msg.id)
        try ref.setData(from: msg)
    }

    private func touchLastMessage(coupleId: String) async throws {
        try await db.collection(FirestorePath.couples).document(coupleId)
            .setData(["lastMessageAt": FieldValue.serverTimestamp()], merge: true)
    }
}

// MARK: - Errors

enum CoupleChatError: LocalizedError {
    case quizNotFound
    case transactionFailed
    case notPaired

    var errorDescription: String? {
        switch self {
        case .quizNotFound:      return "This quiz is no longer available."
        case .transactionFailed: return "Couldn't save your answer. Please try again."
        case .notPaired:         return "Connect a partner to start chatting."
        }
    }
}

// MARK: - Array chunk helper (small)

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
