//
//  MoodViewModel.swift
//  Coupley
//

import Foundation
import Combine

// MARK: - Submission State

enum SubmissionState: Equatable {
    case idle
    case loading
    case success
    case queued        // saved locally, will sync when online
    case error(String)
}

// MARK: - Mood ViewModel

@MainActor
final class MoodViewModel: ObservableObject {

    static let dailyLimit = 3

    // MARK: - Published Properties

    @Published var selectedMood: Mood?
    @Published var selectedEnergy: EnergyLevel = .medium
    @Published var noteText: String = ""
    @Published var submissionState: SubmissionState = .idle
    @Published private(set) var todayCheckinCount: Int = 0

    // MARK: - Computed Properties

    var hasReachedDailyLimit: Bool { todayCheckinCount >= Self.dailyLimit }

    var isSubmitEnabled: Bool {
        selectedMood != nil && submissionState != .loading && !hasReachedDailyLimit
    }

    // MARK: - Dependencies

    private let moodService: MoodService
    private let aiService: AIService
    private let notificationService: NotificationServiceProtocol
    private let session: UserSession

    // MARK: - Init

    init(
        moodService: MoodService,
        aiService: (any AIService)? = nil,
        notificationService: (any NotificationServiceProtocol)? = nil,
        session: UserSession? = nil
    ) {
        self.moodService = moodService
        self.aiService = aiService ?? PlaceholderAIService()
        self.notificationService = notificationService ?? NotificationService.shared
        self.session = session ?? .demo
    }

    // MARK: - Lifecycle

    func loadTodayCount() {
        Task {
            let count = (try? await moodService.countTodayEntries()) ?? 0
            todayCheckinCount = count
        }
    }

    // MARK: - Actions

    func submitMood() {
        guard let mood = selectedMood, !hasReachedDailyLimit else { return }

        let entry = MoodEntry(
            mood: mood,
            energy: selectedEnergy,
            note: noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        submissionState = .loading

        Task {
            do {
                try await moodService.save(entry: entry)
                todayCheckinCount += 1
                submissionState = .success
            } catch let writeError as MoodWriteError where writeError.isQueued {
                todayCheckinCount += 1
                submissionState = .queued
            } catch {
                submissionState = .error("Failed to save. Please try again.")
                return
            }

            // Update activity timestamps for nudge system
            try? await notificationService.updateLastActive(userId: session.userId)

            resetForm()

            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if submissionState == .success || submissionState == .queued {
                submissionState = .idle
            }
        }
    }

    // MARK: - Private

    private func resetForm() {
        selectedMood = nil
        selectedEnergy = .medium
        noteText = ""
    }
}
