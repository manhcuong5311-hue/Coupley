//
//  SuggestionViewModel.swift
//  Coupley
//
//  Created by Sam Manh Cuong on 1/4/26.
//

import Foundation
import Combine
// MARK: - Suggestion Load State

enum SuggestionLoadState: Equatable {
    case idle
    case loading
    case loaded
    case error(String)
}

// MARK: - Suggestion ViewModel

@MainActor
final class SuggestionViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var loadState: SuggestionLoadState = .idle
    @Published var messages: [MessageSuggestion] = []
    @Published var action: ActionSuggestion?
    @Published var copiedMessageID: UUID?

    // MARK: - Input

    let moodContext: MoodContext
    let partnerProfile: PartnerProfile

    // MARK: - Dependencies

    private let suggestionService: AISuggestionService

    // MARK: - Cache

    private var cachedResult: AISuggestionResult?

    // MARK: - Init

    init(
        moodContext: MoodContext,
        partnerProfile: PartnerProfile,
        suggestionService: (any AISuggestionService)? = nil
    ) {
        self.moodContext = moodContext
        self.partnerProfile = partnerProfile
        self.suggestionService = suggestionService ?? MockAISuggestionService()
    }

    // MARK: - Actions

    func loadSuggestions() {
        // Return cached result if available
        if let cached = cachedResult {
            applyResult(cached)
            return
        }

        loadState = .loading

        Task {
            do {
                let result = try await suggestionService.generateSuggestions(
                    context: moodContext,
                    profile: partnerProfile
                )
                cachedResult = result
                applyResult(result)
            } catch {
                loadState = .error("Couldn't generate suggestions. Tap to retry.")
            }
        }
    }

    func retry() {
        cachedResult = nil
        loadSuggestions()
    }

    func copyMessage(_ message: MessageSuggestion) {
        UIPasteboard.general.string = message.text
        copiedMessageID = message.id

        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if copiedMessageID == message.id {
                copiedMessageID = nil
            }
        }
    }

    func markActionDone() {
        withOptionalAnimation {
            action?.isCompleted = true
        }
    }

    // MARK: - Private

    private func applyResult(_ result: AISuggestionResult) {
        messages = result.messages
        action = result.action
        loadState = .loaded
    }

    private func withOptionalAnimation(_ body: () -> Void) {
        body()
        objectWillChange.send()
    }
}

import UIKit
