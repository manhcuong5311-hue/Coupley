//
//  AICoachService.swift
//  Coupley
//
//  Service layer for the AI Relationship Coach. Mirrors the pattern used by
//  AISuggestionService: a protocol, a rich offline Mock, a remote
//  Cloud-Function-backed implementation, and a Hybrid that falls back to the
//  mock when the network fails or no backend is configured.
//

import Foundation

// MARK: - Service Protocol

protocol AICoachService {
    /// Free-form coach reply to an open user message (chat style).
    func reply(
        to userMessage: String,
        transcript: [CoachChatMessage],
        context: CoachContext
    ) async throws -> String

    /// Structured guided output for a specific coaching flow.
    func guidedResponse(
        issue: CoachIssueType,
        userInput: String,
        context: CoachContext
    ) async throws -> GuidedResponse

    /// Rewrite a user-supplied message in three tones.
    func rewrite(
        message: String,
        context: CoachContext
    ) async throws -> [MessageRewrite]

    /// Relationship health snapshot (5 pillars + summary).
    func healthCheck(
        context: CoachContext
    ) async throws -> RelationshipHealth

    /// 3- or 7-day reconnect plan.
    func recoveryPlan(
        length: RecoveryPlan.Length,
        issue: CoachIssueType?,
        context: CoachContext
    ) async throws -> RecoveryPlan
}

// MARK: - Remote Errors

enum AICoachServiceError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case serverError(Int, String)
    case decodingError
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return String(localized: "Coach is unavailable. Check your connection.")
        case .networkError(let e):
            return String(localized: "Network error: \(e.localizedDescription)",
                          comment: "AI coach error; the system's description of the network failure")
        case .serverError(_, let m):
            return m
        case .decodingError:
            return String(localized: "Couldn't read the coach's response.")
        case .rateLimited:
            return String(localized: "The coach has reached its limit for now. If you've used today's questions it resets tomorrow; otherwise try again in a moment.")
        }
    }

    /// True when the server answered and said no, as opposed to not being
    /// reachable. A refusal must be shown to the user, never papered over.
    var isRefusal: Bool {
        if case .rateLimited = self { return true }
        return false
    }
}

// MARK: - API Configuration

enum AICoachAPIConfig {
    static var baseURL: String {
        Bundle.main.object(forInfoDictionaryKey: "AI_COACH_URL") as? String
            ?? ""
    }
    static let timeoutInterval: TimeInterval = 30

    /// The user's preferred language (BCP-47), sent with every request so the
    /// backend can answer in it. Enum fields keep travelling as `rawValue`;
    /// only the reply language follows the user.
    static var replyLocale: String { Locale.preferredLanguages.first ?? "en" }
}

// MARK: - Remote Service

/// Hits a Cloud Function that wraps the LLM. The backend is expected to return
/// responses in the shapes this file decodes. If `AI_COACH_URL` is not
/// configured in Info.plist, the remote service throws `invalidURL` and the
/// hybrid falls through to the mock.
final class RemoteAICoachService: AICoachService {

    private let session: URLSession
    private let authTokenProvider: (() async throws -> String)?

    init(
        session: URLSession = .shared,
        authTokenProvider: (() async throws -> String)? = FirebaseIDTokenProvider.token
    ) {
        self.session = session
        self.authTokenProvider = authTokenProvider
    }

    func reply(
        to userMessage: String,
        transcript: [CoachChatMessage],
        context: CoachContext
    ) async throws -> String {
        let body = ReplyRequestBody(
            userMessage: userMessage,
            transcript: transcript.map { MessagePayload(role: $0.role.rawValue, text: $0.text) },
            context: ContextPayload(context),
            locale: AICoachAPIConfig.replyLocale
        )
        let response: ReplyResponseBody = try await post(path: "reply", body: body)
        return response.text
    }

    func guidedResponse(
        issue: CoachIssueType,
        userInput: String,
        context: CoachContext
    ) async throws -> GuidedResponse {
        let body = GuidedRequestBody(
            issue: issue.rawValue,
            input: userInput,
            context: ContextPayload(context),
            locale: AICoachAPIConfig.replyLocale
        )
        let r: GuidedResponseBody = try await post(path: "guided", body: body)
        return GuidedResponse(
            situationAnalysis: r.situationAnalysis,
            partnerPerspective: r.partnerPerspective,
            bestNextAction: r.bestNextAction,
            whatNotToDo: r.whatNotToDo,
            suggestedMessage: r.suggestedMessage,
            longTermAdvice: r.longTermAdvice,
            issue: issue
        )
    }

    func rewrite(
        message: String,
        context: CoachContext
    ) async throws -> [MessageRewrite] {
        let body = RewriteRequestBody(
            message: message,
            context: ContextPayload(context),
            locale: AICoachAPIConfig.replyLocale
        )
        let r: RewriteResponseBody = try await post(path: "rewrite", body: body)
        return [
            MessageRewrite(original: message, rewritten: r.soft, tone: .soft),
            MessageRewrite(original: message, rewritten: r.honest, tone: .honest),
            MessageRewrite(original: message, rewritten: r.repair, tone: .repair)
        ]
    }

    func healthCheck(context: CoachContext) async throws -> RelationshipHealth {
        let body = HealthRequestBody(
            context: ContextPayload(context),
            locale: AICoachAPIConfig.replyLocale
        )
        let r: HealthResponseBody = try await post(path: "health", body: body)
        return RelationshipHealth(
            trust: r.trust,
            communication: r.communication,
            emotionalIntimacy: r.emotionalIntimacy,
            support: r.support,
            consistency: r.consistency,
            summary: r.summary,
            redFlags: r.redFlags ?? [],
            generatedAt: Date()
        )
    }

    func recoveryPlan(
        length: RecoveryPlan.Length,
        issue: CoachIssueType?,
        context: CoachContext
    ) async throws -> RecoveryPlan {
        let body = RecoveryRequestBody(
            length: length.rawValue,
            issue: issue?.rawValue,
            context: ContextPayload(context),
            locale: AICoachAPIConfig.replyLocale
        )
        let r: RecoveryResponseBody = try await post(path: "recovery", body: body)
        return RecoveryPlan(
            length: length,
            title: r.title,
            intro: r.intro,
            days: r.days.map { RecoveryPlan.Day(dayNumber: $0.day, theme: $0.theme, actions: $0.actions, message: $0.message) }
        )
    }

    // MARK: - Private HTTP

    private func post<Req: Encodable, Res: Decodable>(path: String, body: Req) async throws -> Res {
        let base = AICoachAPIConfig.baseURL
        guard !base.isEmpty,
              let url = URL(string: base.hasSuffix("/") ? "\(base)\(path)" : "\(base)/\(path)") else {
            throw AICoachServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = AICoachAPIConfig.timeoutInterval

        if let tokenProvider = authTokenProvider {
            let token = try await tokenProvider()
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = try JSONEncoder().encode(body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AICoachServiceError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AICoachServiceError.decodingError
        }
        if httpResponse.statusCode == 429 { throw AICoachServiceError.rateLimited }
        guard httpResponse.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8)
                ?? String(localized: "Unknown error", comment: "Error message when the server gave no details")
            throw AICoachServiceError.serverError(httpResponse.statusCode, message)
        }

        do {
            return try JSONDecoder().decode(Res.self, from: data)
        } catch {
            throw AICoachServiceError.decodingError
        }
    }
}

// MARK: - Request/Response Payloads

private struct ContextPayload: Encodable {
    let myName: String
    let partnerName: String
    let attachmentStyle: String?
    let partnerAttachmentStyle: String?
    let loveLanguage: String?
    let partnerLoveLanguage: String?
    let communicationStyle: String?
    let partnerCommunicationStyle: String?
    let personalityPatterns: [String]
    let partnerPersonalityPatterns: [String]
    let recentMoodNote: String?
    let recurringThemes: [String]

    init(_ c: CoachContext) {
        self.myName = c.myName
        self.partnerName = c.partnerName
        self.attachmentStyle = c.attachmentStyle?.rawValue
        self.partnerAttachmentStyle = c.partnerAttachmentStyle?.rawValue
        self.loveLanguage = c.loveLanguage?.rawValue
        self.partnerLoveLanguage = c.partnerLoveLanguage?.rawValue
        self.communicationStyle = c.communicationStyle?.rawValue
        self.partnerCommunicationStyle = c.partnerCommunicationStyle?.rawValue
        self.personalityPatterns = c.personalityPatterns.map { $0.rawValue }
        self.partnerPersonalityPatterns = c.partnerPersonalityPatterns.map { $0.rawValue }
        self.recentMoodNote = c.recentMoodNote
        self.recurringThemes = c.recurringThemes
    }
}

private struct MessagePayload: Encodable {
    let role: String
    let text: String
}

private struct ReplyRequestBody: Encodable {
    let userMessage: String
    let transcript: [MessagePayload]
    let context: ContextPayload
    let locale: String
}
private struct ReplyResponseBody: Decodable {
    let text: String
}

private struct GuidedRequestBody: Encodable {
    let issue: String
    let input: String
    let context: ContextPayload
    let locale: String
}
private struct GuidedResponseBody: Decodable {
    let situationAnalysis: String
    let partnerPerspective: String
    let bestNextAction: String
    let whatNotToDo: String
    let suggestedMessage: String
    let longTermAdvice: String
}

private struct RewriteRequestBody: Encodable {
    let message: String
    let context: ContextPayload
    let locale: String
}
private struct RewriteResponseBody: Decodable {
    let soft: String
    let honest: String
    let repair: String
}

private struct HealthRequestBody: Encodable {
    let context: ContextPayload
    let locale: String
}
private struct HealthResponseBody: Decodable {
    let trust: Int
    let communication: Int
    let emotionalIntimacy: Int
    let support: Int
    let consistency: Int
    let summary: String
    let redFlags: [String]?
}

private struct RecoveryRequestBody: Encodable {
    let length: String
    let issue: String?
    let context: ContextPayload
    let locale: String
}
private struct RecoveryResponseBody: Decodable {
    let title: String
    let intro: String
    let days: [DayPayload]

    struct DayPayload: Decodable {
        let day: Int
        let theme: String
        let actions: [String]
        let message: String
    }
}

// MARK: - Hybrid Service

/// Tries the remote first, falls back to the mock so users always get a
/// response even before the Cloud Function is deployed.
///
/// The fallback is for an unreachable backend only. When the server refuses
/// (429: the daily allowance or the cooldown), the refusal is rethrown: the
/// mock used to answer in its place, so past the limit a user was reading
/// canned text presented as the real coach, with no sign anything had changed.
final class HybridAICoachService: AICoachService {

    private let remote: AICoachService
    private let fallback: AICoachService

    init(
        remote: AICoachService = RemoteAICoachService(),
        fallback: AICoachService = MockAICoachService()
    ) {
        self.remote = remote
        self.fallback = fallback
    }

    func reply(to m: String, transcript: [CoachChatMessage], context: CoachContext) async throws -> String {
        do {
            let served = try await remote.reply(to: m, transcript: transcript, context: context)
            NotificationCenter.default.post(name: .aiCoachRequestServed, object: nil)
            return served
        }
        catch let refusal as AICoachServiceError where refusal.isRefusal { throw refusal }
        catch {
            print("[AICoach] remote.reply failed: \(error.localizedDescription). Falling back.")
            return try await fallback.reply(to: m, transcript: transcript, context: context)
        }
    }

    func guidedResponse(issue: CoachIssueType, userInput: String, context: CoachContext) async throws -> GuidedResponse {
        do {
            let served = try await remote.guidedResponse(issue: issue, userInput: userInput, context: context)
            NotificationCenter.default.post(name: .aiCoachRequestServed, object: nil)
            return served
        }
        catch let refusal as AICoachServiceError where refusal.isRefusal { throw refusal }
        catch {
            print("[AICoach] remote.guided failed: \(error.localizedDescription). Falling back.")
            return try await fallback.guidedResponse(issue: issue, userInput: userInput, context: context)
        }
    }

    func rewrite(message: String, context: CoachContext) async throws -> [MessageRewrite] {
        do {
            let served = try await remote.rewrite(message: message, context: context)
            NotificationCenter.default.post(name: .aiCoachRequestServed, object: nil)
            return served
        }
        catch let refusal as AICoachServiceError where refusal.isRefusal { throw refusal }
        catch {
            print("[AICoach] remote.rewrite failed: \(error.localizedDescription). Falling back.")
            return try await fallback.rewrite(message: message, context: context)
        }
    }

    func healthCheck(context: CoachContext) async throws -> RelationshipHealth {
        do {
            let served = try await remote.healthCheck(context: context)
            NotificationCenter.default.post(name: .aiCoachRequestServed, object: nil)
            return served
        }
        catch let refusal as AICoachServiceError where refusal.isRefusal { throw refusal }
        catch {
            print("[AICoach] remote.health failed: \(error.localizedDescription). Falling back.")
            return try await fallback.healthCheck(context: context)
        }
    }

    func recoveryPlan(length: RecoveryPlan.Length, issue: CoachIssueType?, context: CoachContext) async throws -> RecoveryPlan {
        do {
            let served = try await remote.recoveryPlan(length: length, issue: issue, context: context)
            NotificationCenter.default.post(name: .aiCoachRequestServed, object: nil)
            return served
        }
        catch let refusal as AICoachServiceError where refusal.isRefusal { throw refusal }
        catch {
            print("[AICoach] remote.recovery failed: \(error.localizedDescription). Falling back.")
            return try await fallback.recoveryPlan(length: length, issue: issue, context: context)
        }
    }
}

extension Notification.Name {
    /// Posted each time the backend actually serves a coach request. The
    /// server charges the daily allowance per request, so this is what the
    /// app's own counter follows.
    static let aiCoachRequestServed = Notification.Name("coupley.aiCoachRequestServed")
}
