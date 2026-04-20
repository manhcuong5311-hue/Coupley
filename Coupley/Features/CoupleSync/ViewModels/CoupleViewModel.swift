//
//  CoupleViewModel.swift
//  Coupley
//
//  Created by Sam Manh Cuong on 1/4/26.
//

import Foundation
import FirebaseFirestore
import Combine

// MARK: - Partner Mood State

enum PartnerMoodState: Equatable {
    case unknown
    case loading
    case available(SharedMoodEntry)
    case error(String)

    static func == (lhs: PartnerMoodState, rhs: PartnerMoodState) -> Bool {
        switch (lhs, rhs) {
        case (.unknown, .unknown), (.loading, .loading):
            return true
        case (.available(let a), .available(let b)):
            return a == b
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - Couple ViewModel

@MainActor
final class CoupleViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var partnerMoodState: PartnerMoodState = .unknown
    @Published var partnerMoodHistory: [SharedMoodEntry] = []
    @Published var showAISuggestions: Bool = false
    @Published var partnerNeedsAttention: Bool = false
    @Published var suggestionContext: MoodContext?

    // Auto-fetched suggestions ready when partner logs a low mood.
    @Published var prefetchedSuggestions: AISuggestionResult?
    @Published var isPrefetchingSuggestions: Bool = false

    // Presence
    @Published var partnerLastSeen: Date?
    @Published var partnerIsOnline: Bool = false

    // MARK: - Computed Properties

    var partnerMood: SharedMoodEntry? {
        if case .available(let entry) = partnerMoodState {
            return entry
        }
        return nil
    }

    var isListening: Bool {
        listener != nil
    }

    /// Mood entries for the last 7 days (oldest → newest).
    var weeklyHistory: [SharedMoodEntry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return partnerMoodHistory
            .filter { $0.timestamp >= cutoff }
            .sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: - Dependencies

    private let session: UserSession
    private let listenerService: MoodListenerService
    private let coupleService: CoupleService
    private let suggestionService: AISuggestionService
    private let profileService: ProfileService
    private let presenceService: PresenceService?

    // MARK: - State

    nonisolated(unsafe) private var listener: ListenerRegistration?
    nonisolated(unsafe) private var historyListener: ListenerRegistration?
    nonisolated(unsafe) private var presenceListener: ListenerRegistration?
    private var lastHandledMoodId: String?

    // MARK: - Init

    init(
        session: UserSession? = nil,
        listenerService: (any MoodListenerService)? = nil,
        coupleService: (any CoupleService)? = nil,
        suggestionService: (any AISuggestionService)? = nil,
        profileService: (any ProfileService)? = nil,
        presenceService: (any PresenceService)? = nil
    ) {
        self.session = session ?? .demo
        self.listenerService = listenerService ?? MockMoodListenerService()
        self.coupleService = coupleService ?? MockCoupleService()
        self.suggestionService = suggestionService ?? MockAISuggestionService()
        self.profileService = profileService ?? LocalProfileService()
        self.presenceService = presenceService
    }

    deinit {
        listener?.remove()
        historyListener?.remove()
        presenceListener?.remove()
        listener = nil
        historyListener = nil
        presenceListener = nil
    }

    // MARK: - Listening

    func startListening() {
        guard listener == nil else { return }

        partnerMoodState = .loading

        listener = listenerService.listenToPartnerMood(
            coupleId: session.coupleId,
            partnerId: session.partnerId,
            onUpdate: { [weak self] entry in
                Task { @MainActor in
                    self?.handlePartnerMoodUpdate(entry)
                }
            },
            onError: { [weak self] error in
                Task { @MainActor in
                    self?.partnerMoodState = .error(error.localizedDescription)
                }
            }
        )

        historyListener = listenerService.listenToAllPartnerMoods(
            coupleId: session.coupleId,
            partnerId: session.partnerId,
            limit: 14,
            onUpdate: { [weak self] entries in
                Task { @MainActor in
                    self?.partnerMoodHistory = entries
                }
            },
            onError: { _ in /* history errors non-fatal */ }
        )

        if let presence = presenceService {
            presenceListener = presence.observePartnerPresence(
                partnerId: session.partnerId,
                onUpdate: { [weak self] lastSeen, online in
                    Task { @MainActor in
                        self?.partnerLastSeen = lastSeen
                        self?.partnerIsOnline = online
                    }
                }
            )
        }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
        historyListener?.remove()
        historyListener = nil
        presenceListener?.remove()
        presenceListener = nil
    }

    // MARK: - AI Suggestion Trigger

    func openSuggestions() {
        guard let mood = partnerMood else { return }
        suggestionContext = mood.toMoodContext()
        showAISuggestions = true
    }

    /// Auto-fetches suggestions when partner mood indicates they need attention.
    func triggerAISuggestionIfNeeded(for entry: SharedMoodEntry) {
        guard entry.needsAttention else {
            partnerNeedsAttention = false
            return
        }

        partnerNeedsAttention = true

        // Avoid re-fetching for the same mood entry
        guard lastHandledMoodId != entry.id else { return }
        lastHandledMoodId = entry.id

        Task { [weak self] in
            guard let self else { return }
            self.isPrefetchingSuggestions = true
            defer { self.isPrefetchingSuggestions = false }

            do {
                let profile = (try? await self.profileService.loadProfile()) ?? .samplePartner
                let context = entry.toMoodContext()
                let result = try await self.suggestionService.generateSuggestions(
                    context: context,
                    profile: profile
                )
                self.prefetchedSuggestions = result
                self.suggestionContext = context
            } catch {
                // Silent: user can still manually open suggestions
                print("[CoupleViewModel] Prefetch failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Private

    private func handlePartnerMoodUpdate(_ entry: SharedMoodEntry?) {
        guard let entry else {
            partnerMoodState = .unknown
            partnerNeedsAttention = false
            return
        }

        let previousMood = partnerMood
        partnerMoodState = .available(entry)

        // Only trigger attention alert on new low moods
        if previousMood?.id != entry.id || previousMood?.mood != entry.mood {
            triggerAISuggestionIfNeeded(for: entry)
        }
    }
}
