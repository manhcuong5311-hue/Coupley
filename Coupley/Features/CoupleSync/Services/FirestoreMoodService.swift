//
//  FirestoreMoodService.swift
//  Coupley
//
//  Created by Sam Manh Cuong on 1/4/26.
//

import Foundation
import FirebaseFirestore
import Network

// MARK: - Firestore Mood Service

final class FirestoreMoodService: MoodService {

    private let db = Firestore.firestore()
    private let session: UserSession
    private let queue: MoodQueueStore
    private let monitor: NWPathMonitor
    private let monitorQueue = DispatchQueue(label: "Coupley.FirestoreMoodService.pathMonitor")

    init(session: UserSession, queue: MoodQueueStore = UserDefaultsMoodQueueStore()) {
        self.session = session
        self.queue = queue
        self.monitor = NWPathMonitor()
        startMonitoring()
    }

    deinit {
        monitor.cancel()
    }

    // MARK: - MoodService Protocol

    func save(entry: MoodEntry) async throws {
        do {
            try await writeToFirestore(entry)
            queue.dequeue(id: entry.id)
        } catch {
            // Queue for retry. Firestore offline cache will usually also persist
            // the write, but our queue guarantees retry semantics across relaunches.
            queue.enqueue(entry)
            throw MoodWriteError.queuedForRetry(underlying: error)
        }
    }

    func fetchAll() async throws -> [MoodEntry] {
        let snapshot = try await db
            .collection(FirestorePath.moods(coupleId: session.coupleId))
            .whereField("userId", isEqualTo: session.userId)
            .order(by: "timestamp", descending: true)
            .limit(to: 50)
            .getDocuments()

        let remote = snapshot.documents.compactMap { doc in
            try? doc.data(as: SharedMoodEntry.self)
        }.map { $0.toMoodEntry() }

        // Merge queued (unsynced) entries on top
        let queued = queue.all()
        return (queued + remote).sorted { $0.timestamp > $1.timestamp }
    }

    // MARK: - Daily Count (one-shot, no listener)

    func countTodayEntries() async throws -> Int {
        guard !session.coupleId.isEmpty else { return 0 }
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let snapshot = try await db
            .collection(FirestorePath.moods(coupleId: session.coupleId))
            .whereField("userId", isEqualTo: session.userId)
            .whereField("timestamp", isGreaterThanOrEqualTo: Timestamp(date: startOfDay))
            .getDocuments()
        // Also include any locally-queued (unsynced) entries from today
        let queued = queue.all().filter { $0.timestamp >= startOfDay }
        return snapshot.count + queued.count
    }

    // MARK: - Partner Moods

    func fetchPartnerMoods(limit: Int = 10) async throws -> [SharedMoodEntry] {
        let snapshot = try await db
            .collection(FirestorePath.moods(coupleId: session.coupleId))
            .whereField("userId", isEqualTo: session.partnerId)
            .order(by: "timestamp", descending: true)
            .limit(to: limit)
            .getDocuments()

        return snapshot.documents.compactMap { doc in
            try? doc.data(as: SharedMoodEntry.self)
        }
    }

    // MARK: - Queue

    var pendingCount: Int { queue.pendingCount }

    /// Attempt to flush any queued entries. Safe to call repeatedly.
    func flushQueue() async {
        let pending = queue.all()
        guard !pending.isEmpty else { return }

        for entry in pending {
            do {
                try await writeToFirestore(entry)
                queue.dequeue(id: entry.id)
            } catch {
                // Stop on first failure — we'll retry later
                break
            }
        }
    }

    // MARK: - Private

    private func writeToFirestore(_ entry: MoodEntry) async throws {
        guard !session.coupleId.isEmpty else {
            throw MoodWriteError.notPaired
        }

        let shared = SharedMoodEntry(from: entry, userId: session.userId)
        try db
            .collection(FirestorePath.moods(coupleId: session.coupleId))
            .document(shared.id)
            .setData(from: shared)
    }

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            if path.status == .satisfied {
                Task { await self.flushQueue() }
            }
        }
        monitor.start(queue: monitorQueue)
    }
}

// MARK: - Errors

enum MoodWriteError: LocalizedError {
    case notPaired
    case queuedForRetry(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .notPaired:
            return "Connect a partner before saving moods."
        case .queuedForRetry:
            return "Saved locally — will sync when online."
        }
    }

    /// True if caller should show a soft "queued" state rather than an error.
    var isQueued: Bool {
        if case .queuedForRetry = self { return true }
        return false
    }
}
