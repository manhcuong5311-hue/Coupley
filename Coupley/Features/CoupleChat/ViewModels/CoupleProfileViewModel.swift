//
//  CoupleProfileViewModel.swift
//  Coupley
//
//  Listens to the aggregated couple profile at
//  couples/{coupleId}/coupleProfile/current.
//

import Foundation
import FirebaseFirestore
import Combine

@MainActor
final class CoupleProfileViewModel: ObservableObject {

    @Published private(set) var profile: CoupleInsightProfile = .empty
    @Published private(set) var errorMessage: String?

    private let coupleId: String
    private let aggregator: CoupleInsightAggregating
    private var listener: ListenerRegistration?

    init(coupleId: String,
         aggregator: CoupleInsightAggregating? = nil) {
        self.coupleId = coupleId
        self.aggregator = aggregator ?? FirestoreCoupleInsightAggregator()
    }

    deinit { listener?.remove() }

    func start() {
        guard listener == nil else { return }
        listener = aggregator.listenToProfile(
            coupleId: coupleId,
            onUpdate: { [weak self] profile in
                Task { @MainActor in self?.profile = profile }
            },
            onError: { [weak self] err in
                Task { @MainActor in self?.errorMessage = err.localizedDescription }
            }
        )
    }

    func stop() {
        listener?.remove(); listener = nil
    }

    /// Topics sorted by answeredCount desc, then by QuizTopic.allCases order.
    var sortedTopics: [(topic: QuizTopic, insight: CoupleInsightProfile.TopicInsight?)] {
        QuizTopic.allCases.map { topic in
            (topic, profile.topics[topic.rawValue])
        }
        .sorted { lhs, rhs in
            (lhs.1?.answeredCount ?? 0) > (rhs.1?.answeredCount ?? 0)
        }
    }
}
