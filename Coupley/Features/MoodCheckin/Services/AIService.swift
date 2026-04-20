//
//  AIService.swift
//  Coupley
//
//  Created by Sam Manh Cuong on 1/4/26.
//

import Foundation

// MARK: - AI Service Protocol

protocol AIService {
    func triggerAISuggestion(for entry: MoodEntry) async throws -> String?
}

// MARK: - Placeholder AI Service

final class PlaceholderAIService: AIService {

    /// Placeholder for future AI integration.
    /// Will analyze mood patterns and provide relationship suggestions.
    func triggerAISuggestion(for entry: MoodEntry) async throws -> String? {
        // Future: Call AI backend with mood data
        // Example: Suggest activities, conversation starters,
        //          or partner check-in prompts based on mood trends.
        return nil
    }
}
