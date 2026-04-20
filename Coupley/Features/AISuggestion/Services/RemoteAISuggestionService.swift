//
//  RemoteAISuggestionService.swift
//  Coupley
//
//  Created by Sam Manh Cuong on 1/4/26.
//

import Foundation

// MARK: - API Configuration

enum AIAPIConfig {
    // Set this to your deployed Cloud Function URL
    // Example: https://us-central1-your-project.cloudfunctions.net/generateSuggestion
    static var baseURL: String {
        // In production, load from Firebase Remote Config or Info.plist
        Bundle.main.object(forInfoDictionaryKey: "AI_SUGGESTION_URL") as? String
            ?? "https://us-central1-YOUR_PROJECT.cloudfunctions.net/generateSuggestion"
    }

    static let timeoutInterval: TimeInterval = 25
}

// MARK: - API Request Body

private struct SuggestionRequestBody: Encodable {
    let mood: String
    let energy: String
    let note: String?
    let profile: ProfilePayload

    struct ProfilePayload: Encodable {
        let communicationStyle: String
        let likes: [String]
        let dislikes: [String]
    }
}

// MARK: - API Response Body

private struct SuggestionResponseBody: Decodable {
    let messages: MessagesPayload
    let action: String
    let mood: String?
    let energy: String?
    let generatedAt: String?
    let cached: Bool?

    struct MessagesPayload: Decodable {
        let gentle: String
        let playful: String
        let direct: String
    }
}

// MARK: - API Error Response

private struct APIErrorResponse: Decodable {
    let error: String
    let details: [String]?
}

// MARK: - Remote AI Suggestion Errors

enum RemoteAISuggestionError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case serverError(Int, String)
    case decodingError
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API configuration"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        case .decodingError:
            return "Failed to parse response"
        case .rateLimited:
            return "Too many requests. Please wait a moment."
        }
    }
}

// MARK: - Remote AI Suggestion Service

final class RemoteAISuggestionService: AISuggestionService {

    private let session: URLSession
    private let authTokenProvider: (() async throws -> String)?

    init(
        session: URLSession = .shared,
        authTokenProvider: (() async throws -> String)? = nil
    ) {
        self.session = session
        self.authTokenProvider = authTokenProvider
    }

    // MARK: - AISuggestionService

    func generateSuggestions(
        context: MoodContext,
        profile: PartnerProfile
    ) async throws -> AISuggestionResult {
        let requestBody = SuggestionRequestBody(
            mood: context.mood.rawValue,
            energy: context.energy.rawValue,
            note: context.note,
            profile: SuggestionRequestBody.ProfilePayload(
                communicationStyle: profile.communicationStyle.rawValue,
                likes: profile.allLikes,
                dislikes: profile.dislikes
            )
        )

        guard let url = URL(string: AIAPIConfig.baseURL) else {
            throw RemoteAISuggestionError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = AIAPIConfig.timeoutInterval

        // Attach Firebase Auth token if available
        if let tokenProvider = authTokenProvider {
            let token = try await tokenProvider()
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw RemoteAISuggestionError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RemoteAISuggestionError.decodingError
        }

        // Handle error responses
        if httpResponse.statusCode == 429 {
            throw RemoteAISuggestionError.rateLimited
        }

        if httpResponse.statusCode != 200 {
            let errorMessage: String
            if let apiError = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                errorMessage = apiError.error
            } else {
                errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            }
            throw RemoteAISuggestionError.serverError(httpResponse.statusCode, errorMessage)
        }

        // Decode success response
        let responseBody: SuggestionResponseBody
        do {
            responseBody = try JSONDecoder().decode(SuggestionResponseBody.self, from: data)
        } catch {
            throw RemoteAISuggestionError.decodingError
        }

        return mapToResult(responseBody)
    }

    // MARK: - Response Mapping

    private func mapToResult(_ response: SuggestionResponseBody) -> AISuggestionResult {
        let messages = [
            MessageSuggestion(
                text: response.messages.gentle,
                tone: .warm
            ),
            MessageSuggestion(
                text: response.messages.playful,
                tone: .playful
            ),
            MessageSuggestion(
                text: response.messages.direct,
                tone: .supportive
            ),
        ]

        let action = ActionSuggestion(
            title: "Suggested Action",
            description: response.action,
            icon: "sparkles"
        )

        return AISuggestionResult(messages: messages, action: action)
    }
}
