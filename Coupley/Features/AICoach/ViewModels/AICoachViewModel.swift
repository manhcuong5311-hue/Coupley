//
//  AICoachViewModel.swift
//  Coupley
//
//  Owns the AI Coach chat state, context, and interactions. Persists the
//  chat transcript in UserDefaults so conversations survive app relaunches.
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class AICoachViewModel: ObservableObject {

    // MARK: - Published state

    @Published var messages: [CoachChatMessage] = []
    @Published var activeIssue: CoachIssueType?
    @Published var input: String = ""
    @Published var isSending: Bool = false
    @Published var errorMessage: String?
    @Published var context: CoachContext = .empty

    // MARK: - Dependencies

    private var session: UserSession
    private let service: AICoachService
    private let store: AICoachChatStoring

    // MARK: - Init

    init(
        session: UserSession,
        service: AICoachService? = nil,
        store: AICoachChatStoring? = nil
    ) {
        self.session = session
        self.service = service ?? HybridAICoachService()
        self.store = store ?? AICoachChatStore()
    }

    /// Rebind to a fresh session (e.g. after login or when opening the coach
    /// from the dashboard where the real session comes from the environment).
    /// Safe to call repeatedly.
    func rebind(session: UserSession) {
        guard session.userId != self.session.userId else { return }
        self.session = session
        self.messages = []
        self.activeIssue = nil
    }

    // MARK: - Lifecycle

    /// Restore the transcript from UserDefaults. Called every time the coach
    /// sheet appears so returning users continue where they left off.
    func load() {
        let saved = store.load(for: session.userId)
        self.messages = saved.messages
        self.activeIssue = saved.activeIssue
    }

    /// Hydrate the coaching context from the user's profile + mood + partner
    /// profile. Safe to call repeatedly; later data simply overwrites earlier.
    func updateContext(
        myName: String,
        partnerName: String,
        partnerProfile: PartnerProfile? = nil,
        recentMoodNote: String? = nil
    ) {
        var ctx = context
        if !myName.isEmpty { ctx.myName = myName }
        if !partnerName.isEmpty { ctx.partnerName = partnerName }
        if let p = partnerProfile {
            ctx.partnerLoveLanguage = p.personality.loveLanguage
            ctx.partnerCommunicationStyle = p.personality.communicationStyle
        }
        if let note = recentMoodNote, !note.isEmpty {
            ctx.recentMoodNote = note
        }
        self.context = ctx
    }

    func setAttachmentStyle(_ style: AttachmentStyle, forPartner: Bool) {
        if forPartner {
            context.partnerAttachmentStyle = style
        } else {
            context.attachmentStyle = style
        }
    }

    // MARK: - Chat

    /// Send a freeform chat message. The coach replies inline in the transcript.
    func sendChatMessage() async {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        input = ""

        let userMessage = CoachChatMessage(role: .user, text: trimmed)
        messages.append(userMessage)
        persist()

        isSending = true
        defer { isSending = false }

        do {
            let reply = try await service.reply(
                to: trimmed,
                transcript: messages,
                context: context
            )
            let coachMessage = CoachChatMessage(role: .coach, text: reply)
            messages.append(coachMessage)
            persist()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Start a guided coaching flow for a specific issue. Appends a system
    /// prompt (shown as a framing card) and generates a structured response
    /// using the user's message as input.
    func runGuidedFlow(for issue: CoachIssueType, userInput: String) async {
        let trimmed = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        activeIssue = issue

        let framing = CoachChatMessage(
            role: .systemPrompt,
            text: issue.title
        )
        let userMessage = CoachChatMessage(role: .user, text: trimmed)
        messages.append(framing)
        messages.append(userMessage)
        persist()

        isSending = true
        defer { isSending = false }

        do {
            let guided = try await service.guidedResponse(
                issue: issue,
                userInput: trimmed,
                context: context
            )
            let response = CoachChatMessage(
                role: .coach,
                text: guided.situationAnalysis,
                guided: guided
            )
            messages.append(response)
            persist()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Rewrite

    func rewrite(_ message: String) async throws -> [MessageRewrite] {
        try await service.rewrite(message: message, context: context)
    }

    // MARK: - Health

    func runHealthCheck() async throws -> RelationshipHealth {
        try await service.healthCheck(context: context)
    }

    // MARK: - Recovery

    func runRecoveryPlan(length: RecoveryPlan.Length, issue: CoachIssueType?) async throws -> RecoveryPlan {
        try await service.recoveryPlan(length: length, issue: issue, context: context)
    }

    // MARK: - Session management

    func clearTranscript() {
        messages = []
        activeIssue = nil
        store.clear(for: session.userId)
    }

    // MARK: - Private

    private func persist() {
        let session = CoachChatSession(
            messages: messages,
            activeIssue: activeIssue,
            updatedAt: Date()
        )
        store.save(session, for: self.session.userId)
    }
}
