//
//  AISuggestionService.swift
//  Coupley
//
//  Created by Sam Manh Cuong on 1/4/26.
//

import Foundation

// MARK: - AI Suggestion Service Protocol

protocol AISuggestionService {
    func generateSuggestions(
        context: MoodContext,
        profile: PartnerProfile
    ) async throws -> AISuggestionResult
}

// MARK: - Mock AI Suggestion Service

final class MockAISuggestionService: AISuggestionService {

    func generateSuggestions(
        context: MoodContext,
        profile: PartnerProfile
    ) async throws -> AISuggestionResult {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 1_200_000_000)

        let messages = generateMessages(context: context, profile: profile)
        let action = generateAction(context: context, profile: profile)

        return AISuggestionResult(messages: messages, action: action)
    }

    // MARK: - Private Generators

    private func generateMessages(
        context: MoodContext,
        profile: PartnerProfile
    ) -> [MessageSuggestion] {
        switch (context.mood, profile.communicationStyle) {
        case (.sad, .introvert):
            return [
                MessageSuggestion(
                    text: "Hey \(profile.name), just wanted you to know I'm here. No pressure to talk \u{2014} I'm just a text away.",
                    tone: .supportive
                ),
                MessageSuggestion(
                    text: "I know today's been tough. Want me to bring you a \(profile.favoriteThings.drink) later?",
                    tone: .warm
                ),
                MessageSuggestion(
                    text: "Sending you a quiet hug. Take all the time you need.",
                    tone: .warm
                ),
            ]

        case (.sad, .expressive):
            return [
                MessageSuggestion(
                    text: "I can feel something's off and I really care. Tell me everything when you're ready?",
                    tone: .supportive
                ),
                MessageSuggestion(
                    text: "Hey love, bad days happen but we've got this. Want to talk about it over \(profile.favoriteThings.food) tonight?",
                    tone: .warm
                ),
                MessageSuggestion(
                    text: "You're my favorite person and I hate seeing you down. What can I do right now?",
                    tone: .playful
                ),
            ]

        case (.stressed, .introvert):
            return [
                MessageSuggestion(
                    text: "I know things are hectic. Just want you to know I'm thinking of you.",
                    tone: .supportive
                ),
                MessageSuggestion(
                    text: "No need to reply \u{2014} just sending some calm your way. We can decompress together later.",
                    tone: .warm
                ),
                MessageSuggestion(
                    text: "You handle so much and I admire that. Let me take something off your plate today.",
                    tone: .supportive
                ),
            ]

        case (.stressed, .expressive):
            return [
                MessageSuggestion(
                    text: "You sound stressed and I want to help! Let's vent together \u{2014} I'll bring snacks.",
                    tone: .playful
                ),
                MessageSuggestion(
                    text: "Hey, deep breath. You're amazing even on your worst days. Want to do something fun tonight?",
                    tone: .warm
                ),
                MessageSuggestion(
                    text: "Stressed out? Let's fix that. Pick: \(profile.favoriteThings.activities.first ?? "movie night") or a walk? Your call!",
                    tone: .playful
                ),
            ]

        case (.stressed, .avoidant):
            return [
                MessageSuggestion(
                    text: "Hey \(profile.name), no pressure at all. Just wanted to say I'm around if you need anything.",
                    tone: .supportive
                ),
                MessageSuggestion(
                    text: "I'll give you space but I'm not going anywhere. Let me know when you're ready.",
                    tone: .warm
                ),
                MessageSuggestion(
                    text: "Left a little something for you in the kitchen. Hope it helps even a tiny bit.",
                    tone: .warm
                ),
            ]

        case (.sad, .avoidant):
            return [
                MessageSuggestion(
                    text: "No need to talk about it. I just want you to know you matter to me \u{2014} always.",
                    tone: .supportive
                ),
                MessageSuggestion(
                    text: "I made you a playlist. Sometimes music says it better than words.",
                    tone: .warm
                ),
                MessageSuggestion(
                    text: "I put on some \(profile.favoriteThings.music) and saved you a spot on the couch. Join whenever.",
                    tone: .playful
                ),
            ]

        default:
            return [
                MessageSuggestion(
                    text: "Hey \(profile.name), just checking in. How are you really doing?",
                    tone: .warm
                ),
                MessageSuggestion(
                    text: "Thinking about you! Want to grab \(profile.favoriteThings.drink) together?",
                    tone: .playful
                ),
                MessageSuggestion(
                    text: "I appreciate you. Just wanted you to know that today.",
                    tone: .supportive
                ),
            ]
        }
    }

    private func generateAction(
        context: MoodContext,
        profile: PartnerProfile
    ) -> ActionSuggestion {
        let activity = profile.favoriteThings.activities.first ?? "a relaxing evening"

        switch context.mood {
        case .sad:
            return ActionSuggestion(
                title: "Surprise with their favorite",
                description: "Pick up \(profile.favoriteThings.food) and \(profile.favoriteThings.drink) on your way home. Put on some \(profile.favoriteThings.music) and create a cozy moment together.",
                icon: "gift.fill"
            )

        case .stressed:
            return ActionSuggestion(
                title: "Plan a decompression activity",
                description: "Suggest \(activity) tonight. Take care of dinner so they have one less thing to worry about.",
                icon: "leaf.fill"
            )

        default:
            return ActionSuggestion(
                title: "Quality time moment",
                description: "Set aside 30 minutes for \(activity) together \u{2014} phones off, full attention.",
                icon: "heart.circle.fill"
            )
        }
    }
}

// MARK: - Hybrid AI Suggestion Service (Remote + Fallback)

/// Tries the remote OpenAI-backed service first, falls back to mock data
/// if the network call fails. Ensures the user always sees suggestions.
final class HybridAISuggestionService: AISuggestionService {

    private let remote: AISuggestionService
    private let fallback: AISuggestionService

    init(
        remote: AISuggestionService = RemoteAISuggestionService(),
        fallback: AISuggestionService = MockAISuggestionService()
    ) {
        self.remote = remote
        self.fallback = fallback
    }

    func generateSuggestions(
        context: MoodContext,
        profile: PartnerProfile
    ) async throws -> AISuggestionResult {
        do {
            return try await remote.generateSuggestions(context: context, profile: profile)
        } catch {
            print("[HybridAI] Remote failed: \(error.localizedDescription). Using fallback.")
            return try await fallback.generateSuggestions(context: context, profile: profile)
        }
    }
}
