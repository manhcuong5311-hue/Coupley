//
//  MoodListenerService.swift
//  Coupley
//
//  Created by Sam Manh Cuong on 1/4/26.
//

import Foundation
import FirebaseFirestore
import Combine

// MARK: - Mood Listener Protocol

protocol MoodListenerService {
    func listenToPartnerMood(
        coupleId: String,
        partnerId: String,
        onUpdate: @escaping (SharedMoodEntry?) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration

    func listenToAllPartnerMoods(
        coupleId: String,
        partnerId: String,
        limit: Int,
        onUpdate: @escaping ([SharedMoodEntry]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration
}

// MARK: - Firestore Mood Listener

final class FirestoreMoodListenerService: MoodListenerService {

    private let db = Firestore.firestore()

    func listenToPartnerMood(
        coupleId: String,
        partnerId: String,
        onUpdate: @escaping (SharedMoodEntry?) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        db.collection(FirestorePath.moods(coupleId: coupleId))
            .whereField("userId", isEqualTo: partnerId)
            .order(by: "timestamp", descending: true)
            .limit(to: 1)
            .addSnapshotListener { snapshot, error in
                if let error {
                    onError(error)
                    return
                }

                let entry = snapshot?.documents.first.flatMap { doc in
                    try? doc.data(as: SharedMoodEntry.self)
                }

                onUpdate(entry)
            }
    }

    func listenToAllPartnerMoods(
        coupleId: String,
        partnerId: String,
        limit: Int = 10,
        onUpdate: @escaping ([SharedMoodEntry]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        db.collection(FirestorePath.moods(coupleId: coupleId))
            .whereField("userId", isEqualTo: partnerId)
            .order(by: "timestamp", descending: true)
            .limit(to: limit)
            .addSnapshotListener { snapshot, error in
                if let error {
                    onError(error)
                    return
                }

                let entries = snapshot?.documents.compactMap { doc in
                    try? doc.data(as: SharedMoodEntry.self)
                } ?? []

                onUpdate(entries)
            }
    }
}

// MARK: - Mock Mood Listener

final class MockMoodListenerService: MoodListenerService {

    private var timer: Timer?

    private let mockMoods: [SharedMoodEntry] = [
        SharedMoodEntry(
            from: MoodEntry(mood: .happy, energy: .high, note: "Great day at work!"),
            userId: UserSession.demo.partnerId
        ),
        SharedMoodEntry(
            from: MoodEntry(mood: .sad, energy: .low, note: "Feeling overwhelmed today"),
            userId: UserSession.demo.partnerId
        ),
        SharedMoodEntry(
            from: MoodEntry(mood: .stressed, energy: .medium, note: "Deadline pressure"),
            userId: UserSession.demo.partnerId
        ),
        SharedMoodEntry(
            from: MoodEntry(mood: .neutral, energy: .medium),
            userId: UserSession.demo.partnerId
        ),
    ]

    func listenToPartnerMood(
        coupleId: String,
        partnerId: String,
        onUpdate: @escaping (SharedMoodEntry?) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        // Deliver the first mock mood immediately
        let initial = mockMoods.first
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            onUpdate(initial)
        }

        // Cycle through moods every 8 seconds to simulate real-time updates
        var index = 1
        timer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let mood = self.mockMoods[index % self.mockMoods.count]
            onUpdate(mood)
            index += 1
        }

        return MockListenerRegistration { [weak self] in
            self?.timer?.invalidate()
            self?.timer = nil
        }
    }

    func listenToAllPartnerMoods(
        coupleId: String,
        partnerId: String,
        limit: Int = 10,
        onUpdate: @escaping ([SharedMoodEntry]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            onUpdate(Array(self.mockMoods.prefix(limit)))
        }

        return MockListenerRegistration {}
    }
}

// MARK: - Mock Listener Registration

final class MockListenerRegistration: NSObject, ListenerRegistration {
    private let onRemove: () -> Void

    init(onRemove: @escaping () -> Void) {
        self.onRemove = onRemove
    }

    func remove() {
        onRemove()
    }
}
