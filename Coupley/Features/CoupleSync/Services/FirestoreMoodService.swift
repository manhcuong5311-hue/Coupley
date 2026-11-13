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
        } catch let error as MoodWriteError where !error.isQueued {
            // Not retryable. `.notPaired` used to fall into the blanket catch
            // below and be reported as "Saved locally — will sync when online",
            // which is never true: every flush hits the same guard and breaks
            // on the first entry, so the queue could only grow. The user was
            // told to wait for connectivity for a problem connectivity cannot
            // fix, while their 3/day allowance was spent on writes that can
            // never land.
            throw error
        } catch where Self.isServerRejection(error) {
            // The server answered and said no (rules, a disconnected couple).
            // Retrying cannot change that, so it is not queued: queueing it
            // told the user "will sync" and retried it on every reconnect.
            throw MoodWriteError.rejected
        } catch {
            // Queue for retry. Firestore offline cache will usually also persist
            // the write, but our queue guarantees retry semantics across relaunches.
            queue.enqueue(entry)
            throw MoodWriteError.queuedForRetry(underlying: error)
        }
    }

    /// A definite "no" from the backend: the rules refused the write, or the
    /// data itself is invalid. Retrying sends the same write and gets the same
    /// answer. Anything else (quota, auth refresh, an internal error) may pass
    /// on a later attempt, so it stays queued.
    private static func isServerRejection(_ error: Error) -> Bool {
        let ns = error as NSError
        guard ns.domain == FirestoreErrorDomain else { return false }
        return ns.code == FirestoreErrorCode.permissionDenied.rawValue
            || ns.code == FirestoreErrorCode.invalidArgument.rawValue
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
            } catch where Self.isServerRejection(error) {
                // Will never succeed; drop it rather than retry it forever.
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
        // `setData(from:)` has no async form, so a plain `try await` on it
        // never saw a failure and the retry queue below could never fill.
        // This throws when the server rejects the write; offline it returns
        // after a short wait and Firestore syncs the write later.
        try await db
            .collection(FirestorePath.moods(coupleId: session.coupleId))
            .document(shared.id)
            .setDataConfirmed(from: shared)
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
    case rejected
    case queuedForRetry(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .notPaired:
            return String(localized: "Connect a partner before saving moods.")
        case .rejected:
            return String(localized: "Couldn't save your mood. Please try again.")
        case .queuedForRetry:
            return String(localized: "Saved locally — will sync when online.",
                          comment: "Mood check-in saved offline; it uploads when the connection returns")
        }
    }

    /// True if caller should show a soft "queued" state rather than an error.
    var isQueued: Bool {
        if case .queuedForRetry = self { return true }
        return false
    }
}
