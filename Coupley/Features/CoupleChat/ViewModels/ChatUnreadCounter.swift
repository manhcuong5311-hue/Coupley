//
//  ChatUnreadCounter.swift
//  Coupley
//
//  Lightweight listener that powers the unread badge on the Chat tab.
//  Lives at ContentView level so the badge stays current even when the
//  Chat tab isn't selected — ChatViewModel only runs while the tab is on
//  screen, so it can't be the source of truth here.
//

import Foundation
import FirebaseFirestore
import Combine

@MainActor
final class ChatUnreadCounter: ObservableObject {

    @Published private(set) var unreadCount: Int = 0

    private var listener: ListenerRegistration?
    private let db = Firestore.firestore()

    /// Cap matches the live window of the chat listener — anything older than
    /// the most recent 50 messages is treated as already-seen for the badge.
    private let windowSize = 50

    func start(session: UserSession) {
        guard session.isPaired else { stop(); return }
        listener?.remove()

        let userId = session.userId
        listener = db.collection(FirestorePath.messages(coupleId: session.coupleId))
            .order(by: "createdAt", descending: true)
            .limit(to: windowSize)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self else { return }
                let docs = snapshot?.documents ?? []
                let count = docs.reduce(into: 0) { acc, doc in
                    let data = doc.data()
                    let senderId = data["senderId"] as? String
                    let kind = data["kind"] as? String ?? ""
                    let readBy = data["readBy"] as? [String] ?? []
                    // Count partner messages and quiz/result cards the user
                    // hasn't seen yet. `text`/`photo` are sent by the partner;
                    // `quiz`/`result` are system-generated (senderId nil) but
                    // still represent something new for the user to see.
                    let countableKinds: Set<String> = ["text", "photo", "quiz", "result"]
                    guard countableKinds.contains(kind) else { return }
                    if let senderId, senderId == userId { return }
                    guard !readBy.contains(userId) else { return }
                    acc += 1
                }
                Task { @MainActor in self.unreadCount = count }
            }
    }

    func stop() {
        listener?.remove()
        listener = nil
        unreadCount = 0
    }

    deinit { listener?.remove() }
}
