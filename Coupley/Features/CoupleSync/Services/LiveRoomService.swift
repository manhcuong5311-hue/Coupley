//
//  LiveRoomService.swift
//  Coupley
//
//  One small document per couple carrying the signals that are only
//  interesting *right now*: who is typing, and who is pressing the
//  touch-together circle.
//
//  Why its own document rather than `users/{uid}`:
//    – `users/{uid}` is read by half the app and carries the FCM token and
//      premium state. Writing to it every couple of seconds while someone
//      types would wake every one of those listeners.
//    – These signals are worthless once stale, so they are stored as
//      timestamps and read through a freshness window rather than as
//      booleans that need clearing. A client that dies mid-gesture simply
//      goes quiet; nothing has to clean up after it.
//
//  Both features share the document and therefore a single listener.
//

import Foundation
import FirebaseFirestore

// MARK: - Model

struct LiveRoomState: Equatable {
    /// Last time each user signalled they were typing.
    var typing: [String: Date] = [:]
    /// Last time each user signalled they were holding the touch circle.
    var touching: [String: Date] = [:]

    static let empty = LiveRoomState()

    /// Typing is a slow signal — the client refreshes it every couple of
    /// seconds, so the window has to outlast one refresh interval.
    static let typingWindow: TimeInterval = 6
    /// Touch is a live gesture: a short window so the circle lets go the
    /// moment the other person does.
    static let touchWindow: TimeInterval = 2.5

    func isTyping(_ userId: String, now: Date = Date()) -> Bool {
        guard let at = typing[userId] else { return false }
        return now.timeIntervalSince(at) < Self.typingWindow
    }

    func isTouching(_ userId: String, now: Date = Date()) -> Bool {
        guard let at = touching[userId] else { return false }
        return now.timeIntervalSince(at) < Self.touchWindow
    }
}

// MARK: - Protocol

protocol LiveRoomServicing {
    func observe(
        coupleId: String,
        onUpdate: @escaping (LiveRoomState) -> Void
    ) -> ListenerRegistration

    /// Refreshes this user's typing timestamp. Call freely — the service
    /// throttles writes itself.
    func markTyping(coupleId: String, userId: String) async
    /// Drops the typing signal immediately (message sent, field blurred).
    func clearTyping(coupleId: String, userId: String) async

    /// Refreshes this user's touch timestamp. Also throttled, but faster.
    func markTouching(coupleId: String, userId: String) async
    func clearTouching(coupleId: String, userId: String) async
}

// MARK: - Firestore implementation

actor FirestoreLiveRoomService: LiveRoomServicing {

    private let db = Firestore.firestore()

    /// Minimum gap between repeat writes of the same signal. Typing refreshes
    /// at a human pace; touch has to feel immediate.
    private let typingWriteGap: TimeInterval = 2
    private let touchWriteGap: TimeInterval = 0.6

    private var lastTypingWrite: Date?
    private var lastTouchWrite: Date?

    private func document(_ coupleId: String) -> DocumentReference {
        db.collection(FirestorePath.couples)
            .document(coupleId)
            .collection("liveState")
            .document("room")
    }

    nonisolated func observe(
        coupleId: String,
        onUpdate: @escaping (LiveRoomState) -> Void
    ) -> ListenerRegistration {
        db.collection(FirestorePath.couples)
            .document(coupleId)
            .collection("liveState")
            .document("room")
            .addSnapshotListener { snapshot, _ in
                let data = snapshot?.data() ?? [:]
                onUpdate(LiveRoomState(
                    typing: Self.dates(from: data["typing"]),
                    touching: Self.dates(from: data["touching"])
                ))
            }
    }

    private static func dates(from field: Any?) -> [String: Date] {
        guard let raw = field as? [String: Any] else { return [:] }
        return raw.compactMapValues { ($0 as? Timestamp)?.dateValue() }
    }

    // MARK: Typing

    func markTyping(coupleId: String, userId: String) async {
        guard !coupleId.isEmpty, !userId.isEmpty else { return }
        if let last = lastTypingWrite, Date().timeIntervalSince(last) < typingWriteGap {
            return
        }
        lastTypingWrite = Date()
        await write(coupleId: coupleId, field: "typing", userId: userId, value: FieldValue.serverTimestamp())
    }

    func clearTyping(coupleId: String, userId: String) async {
        guard !coupleId.isEmpty, !userId.isEmpty else { return }
        lastTypingWrite = nil
        await write(coupleId: coupleId, field: "typing", userId: userId, value: FieldValue.delete())
    }

    // MARK: Touch

    func markTouching(coupleId: String, userId: String) async {
        guard !coupleId.isEmpty, !userId.isEmpty else { return }
        if let last = lastTouchWrite, Date().timeIntervalSince(last) < touchWriteGap {
            return
        }
        lastTouchWrite = Date()
        await write(coupleId: coupleId, field: "touching", userId: userId, value: FieldValue.serverTimestamp())
    }

    func clearTouching(coupleId: String, userId: String) async {
        guard !coupleId.isEmpty, !userId.isEmpty else { return }
        lastTouchWrite = nil
        await write(coupleId: coupleId, field: "touching", userId: userId, value: FieldValue.delete())
    }

    // MARK: Shared write

    private func write(coupleId: String, field: String, userId: String, value: Any) async {
        do {
            try await document(coupleId).setData([field: [userId: value]], merge: true)
        } catch {
            // These signals are cosmetic; a failed write just means the other
            // side doesn't see the dots this second.
            print("[LiveRoom] \(field) write failed: \(error.localizedDescription)")
        }
    }
}
