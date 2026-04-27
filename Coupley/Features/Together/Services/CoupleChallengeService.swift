//
//  CoupleChallengeService.swift
//  Coupley
//
//  Firestore CRUD + observation for challenges at
//  couples/{coupleId}/coupleChallenges/{challengeId}.
//
//  Check-ins are written via a dedicated `recordCheckIn` transaction so the
//  log array, the contribution map, and the streak struct stay consistent
//  even when both partners check in simultaneously.
//

import Foundation
import FirebaseFirestore

// MARK: - Protocol

protocol CoupleChallengeService {
    func create(coupleId: String, challenge: CoupleChallenge) async throws
    func update(coupleId: String, challenge: CoupleChallenge) async throws
    func delete(coupleId: String, id: String) async throws

    /// Record a check-in for `userId` on `date`. Returns the freshly-merged
    /// challenge so the caller can immediately reflect new streak / progress
    /// without waiting for the listener round-trip. Same-day check-ins are
    /// idempotent — calling twice writes once.
    func recordCheckIn(
        coupleId: String,
        challengeId: String,
        userId: String,
        date: Date
    ) async throws -> CoupleChallenge?

    func markComplete(coupleId: String, challengeId: String) async throws

    func observe(
        coupleId: String,
        onUpdate: @escaping ([CoupleChallenge]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration
}

// MARK: - Firestore Path

extension FirestorePath {
    static func coupleChallenges(coupleId: String) -> String {
        "\(couples)/\(coupleId)/coupleChallenges"
    }
}

// MARK: - Firestore Implementation

final class FirestoreCoupleChallengeService: CoupleChallengeService {

    private let db = Firestore.firestore()

    // MARK: - Create

    func create(coupleId: String, challenge: CoupleChallenge) async throws {
        try await collection(coupleId)
            .document(challenge.id)
            .setData(Self.payload(from: challenge, forCreate: true))
    }

    // MARK: - Update

    func update(coupleId: String, challenge: CoupleChallenge) async throws {
        var updated = challenge
        updated.updatedAt = Date()
        try await collection(coupleId)
            .document(updated.id)
            .setData(Self.payload(from: updated, forCreate: false), merge: true)
    }

    // MARK: - Delete

    func delete(coupleId: String, id: String) async throws {
        try await collection(coupleId).document(id).delete()
    }

    // MARK: - Check-in

    func recordCheckIn(
        coupleId: String,
        challengeId: String,
        userId: String,
        date: Date
    ) async throws -> CoupleChallenge? {
        let ref = collection(coupleId).document(challengeId)

        let result = try await db.runTransaction({ txn, errorPointer -> Any? in
            let snap: DocumentSnapshot
            do {
                snap = try txn.getDocument(ref)
            } catch let err as NSError {
                errorPointer?.pointee = err
                return nil
            }

            guard let data = snap.data(),
                  let challenge = Self.decode(data: data, documentId: snap.documentID) else {
                return nil
            }

            // Idempotency: don't double-record on the same calendar day.
            if challenge.hasCheckedIn(for: userId, on: date) {
                return Self.payload(from: challenge, forCreate: false) as Any
            }

            var updated = challenge
            updated.checkInLog.append(date)
            updated.checkInLog.sort()
            updated.contribution.add(1, for: userId)

            // Recompute streak from the freshly-appended log. We compute it
            // here rather than client-side so two simultaneous writes can't
            // disagree about the streak count.
            updated.streak = Self.recomputeStreak(
                log: updated.checkInLog,
                cadence: updated.cadence,
                now: date
            )

            // Auto-complete when target reached.
            if updated.totalCheckIns >= updated.targetCount && updated.completedAt == nil {
                updated.completedAt = date
            }

            updated.updatedAt = date
            txn.setData(
                Self.payload(from: updated, forCreate: false),
                forDocument: ref,
                merge: true
            )
            return Self.payload(from: updated, forCreate: false) as Any
        })

        if let dict = result as? [String: Any] {
            return Self.decode(data: dict, documentId: challengeId)
        }
        return nil
    }

    // MARK: - Mark Complete

    func markComplete(coupleId: String, challengeId: String) async throws {
        try await collection(coupleId).document(challengeId).setData([
            "completedAt": Timestamp(date: Date()),
            "updatedAt":   Timestamp(date: Date())
        ], merge: true)
    }

    // MARK: - Observe

    func observe(
        coupleId: String,
        onUpdate: @escaping ([CoupleChallenge]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        collection(coupleId)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { snapshot, error in
                if let error {
                    onError(error)
                    return
                }
                let items = snapshot?.documents.compactMap {
                    Self.decode(data: $0.data(), documentId: $0.documentID)
                } ?? []
                onUpdate(items)
            }
    }

    // MARK: - Streak Recomputation

    /// Walks the log backward from `now`, counting consecutive cadence units
    /// with at least one check-in. Stops at the first gap. Updates `longest`
    /// only when current beats it.
    static func recomputeStreak(
        log: [Date],
        cadence: ChallengeCadence,
        now: Date
    ) -> TogetherStreak {
        guard !log.isEmpty else { return .zero }

        let calendar = Calendar.current
        let sorted = log.sorted()

        // Build the set of cadence-unit "buckets" that had at least one check-in.
        let bucketDates: Set<Date> = Set(sorted.map { date in
            switch cadence {
            case .daily:  return calendar.startOfDay(for: date)
            case .weekly:
                // Use the start of the ISO-8601 week so weekly streaks are
                // independent of when the user happened to check in.
                let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
                return calendar.date(from: comps) ?? date
            }
        })

        // Walk back from "today's bucket" until we hit a missing one.
        var anchor: Date
        switch cadence {
        case .daily:
            anchor = calendar.startOfDay(for: now)
        case .weekly:
            let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
            anchor = calendar.date(from: comps) ?? now
        }

        // If today's bucket is empty, the streak runs through "yesterday" only
        // if yesterday had a check-in. We allow the streak to remain "alive"
        // for one cadence unit of grace, matching how Duolingo / Apple Fitness
        // treat in-progress streaks.
        if !bucketDates.contains(anchor) {
            anchor = calendar.date(byAdding: cadence == .daily ? .day : .weekOfYear,
                                   value: -1, to: anchor) ?? anchor
        }

        var current = 0
        var cursor = anchor
        while bucketDates.contains(cursor) {
            current += 1
            cursor = calendar.date(byAdding: cadence == .daily ? .day : .weekOfYear,
                                   value: -1, to: cursor) ?? cursor
        }

        let lastCheckIn = sorted.last
        return TogetherStreak(
            current: current,
            longest: max(current, computeLongestStreak(buckets: bucketDates,
                                                     calendar: calendar,
                                                     cadence: cadence)),
            lastCheckIn: lastCheckIn
        )
    }

    /// Scans every bucket and tracks the maximum consecutive run. We don't
    /// bother with this for sub-1000-entry logs, so the O(n log n) sort is fine.
    private static func computeLongestStreak(
        buckets: Set<Date>,
        calendar: Calendar,
        cadence: ChallengeCadence
    ) -> Int {
        guard !buckets.isEmpty else { return 0 }
        let sorted = buckets.sorted()
        var longest = 1
        var current = 1
        for i in 1..<sorted.count {
            let prev = sorted[i - 1]
            let next = sorted[i]
            let expected = calendar.date(byAdding: cadence == .daily ? .day : .weekOfYear,
                                         value: 1, to: prev)
            if let expected, calendar.isDate(expected, equalTo: next, toGranularity: cadence == .daily ? .day : .weekOfYear) {
                current += 1
                longest = max(longest, current)
            } else {
                current = 1
            }
        }
        return longest
    }

    // MARK: - Payload / Decoding

    private func collection(_ coupleId: String) -> CollectionReference {
        db.collection(FirestorePath.coupleChallenges(coupleId: coupleId))
    }

    private static func payload(from c: CoupleChallenge, forCreate: Bool) -> [String: Any] {
        var dict: [String: Any] = [
            "id":                  c.id,
            "title":               c.title,
            "category":            c.category.rawValue,
            "colorway":            c.colorway.rawValue,
            "cadence":             c.cadence.rawValue,
            "targetCount":         c.targetCount,
            "contributionAmounts": c.contribution.amounts,
            "checkInLog":          c.checkInLog.map { Timestamp(date: $0) },
            "streakCurrent":       c.streak.current,
            "streakLongest":       c.streak.longest,
            "startDate":           Timestamp(date: c.startDate),
            "createdBy":           c.createdBy,
            "createdAt":           Timestamp(date: c.createdAt),
            "updatedAt":           Timestamp(date: c.updatedAt)
        ]

        if let last = c.streak.lastCheckIn {
            dict["streakLastCheckIn"] = Timestamp(date: last)
        } else if !forCreate {
            dict["streakLastCheckIn"] = FieldValue.delete()
        }

        if let completed = c.completedAt {
            dict["completedAt"] = Timestamp(date: completed)
        } else if !forCreate {
            dict["completedAt"] = FieldValue.delete()
        }

        return dict
    }

    private static func decode(data: [String: Any], documentId: String) -> CoupleChallenge? {
        guard
            let id           = data["id"] as? String,
            let title        = data["title"] as? String,
            let categoryRaw  = data["category"] as? String,
            let category     = ChallengeCategory(rawValue: categoryRaw),
            let colorwayRaw  = data["colorway"] as? String,
            let colorway     = TogetherColorway(rawValue: colorwayRaw),
            let cadenceRaw   = data["cadence"] as? String,
            let cadence      = ChallengeCadence(rawValue: cadenceRaw),
            let targetCount  = data["targetCount"] as? Int,
            let createdBy    = data["createdBy"] as? String,
            let createdAt    = (data["createdAt"] as? Timestamp)?.dateValue(),
            let startDate    = (data["startDate"] as? Timestamp)?.dateValue()
        else { return nil }

        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? createdAt
        let amounts = (data["contributionAmounts"] as? [String: Double]) ?? [:]
        let log = (data["checkInLog"] as? [Timestamp])?.map { $0.dateValue() } ?? []
        let streak = TogetherStreak(
            current: (data["streakCurrent"] as? Int) ?? 0,
            longest: (data["streakLongest"] as? Int) ?? 0,
            lastCheckIn: (data["streakLastCheckIn"] as? Timestamp)?.dateValue()
        )
        let completed = (data["completedAt"] as? Timestamp)?.dateValue()

        var c = CoupleChallenge(
            id: id,
            title: title,
            category: category,
            colorway: colorway,
            cadence: cadence,
            targetCount: targetCount,
            contribution: TogetherContribution(amounts: amounts),
            checkInLog: log,
            streak: streak,
            startDate: startDate,
            createdBy: createdBy,
            createdAt: createdAt,
            updatedAt: updatedAt,
            completedAt: completed
        )
        c.firestoreId = documentId
        return c
    }
}

// MARK: - Mock

final class MockCoupleChallengeService: CoupleChallengeService {
    func create(coupleId: String, challenge: CoupleChallenge) async throws {}
    func update(coupleId: String, challenge: CoupleChallenge) async throws {}
    func delete(coupleId: String, id: String) async throws {}
    func recordCheckIn(coupleId: String, challengeId: String, userId: String, date: Date) async throws -> CoupleChallenge? { nil }
    func markComplete(coupleId: String, challengeId: String) async throws {}
    func observe(
        coupleId: String,
        onUpdate: @escaping ([CoupleChallenge]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        onUpdate(SampleTogetherData.challenges)
        return MockListenerRegistration {}
    }
}
