//
//  OnboardingViewModel.swift
//  Coupley
//
//  State machine driving the post-login onboarding flow. Owns the
//  `OnboardingProfile`, the current `step`, and a debounced partial-save
//  pipeline so the user's answers survive a force-quit between steps.
//
//  Steps fall into two buckets:
//    • `.info(...)` — emotional why-screens. No required input, just a
//      Continue tap. We still autosave so completion-state cookie crumbs
//      are written incrementally.
//    • `.input(...)` — collect a piece of profile data. The Continue
//      button's enable state is driven by the per-step `canAdvance`
//      computed property below.
//
//  After the final paywall step, `complete()` writes the terminal payload
//  and flips `@AppStorage("hasCompletedOnboarding")` to true, which the
//  RootView observes to pop us out of onboarding.
//

import Foundation
import Combine
import SwiftUI
import FirebaseAuth

// MARK: - Step

enum OnboardingStep: Int, CaseIterable, Identifiable {
    // Why
    case welcome
    case benefits
    case moodSync
    case memories
    case communication
    case aiAssistance
    case dailyConnection
    // Setup
    case nameInput
    case partnerInput          // partner name + anniversary on one screen
    case goals
    case communicationStyle
    case dailyHabit            // reminder time + mood-check toggle
    case notifications
    case widget
    case partnerExpectation
    // Pay
    case paywall

    var id: Int { rawValue }

    /// Soft-skip steps don't advance unless the user explicitly chooses;
    /// hard-skip steps auto-advance after a short tap.
    var allowsSkip: Bool {
        switch self {
        case .nameInput: return false                  // required
        case .paywall:   return false                  // explicit dismiss only
        default:         return true
        }
    }

    /// Display index for the progress dots (1..n inclusive). Hidden on the
    /// welcome and paywall steps so they read as standalone moments.
    var progressIndex: Int? {
        switch self {
        case .welcome, .paywall: return nil
        default: return rawValue
        }
    }
}

// MARK: - View Model

@MainActor
final class OnboardingViewModel: ObservableObject {

    // MARK: Published

    @Published var step: OnboardingStep = .welcome
    @Published var profile: OnboardingProfile = OnboardingProfile()
    @Published var isCompleting: Bool = false
    @Published var errorMessage: String?

    // MARK: Dependencies

    private let service: OnboardingServiceProtocol
    private let userId: String
    private var saveTask: Task<Void, Never>?

    /// Set by RootView via the `@AppStorage` wrapper after `complete()`.
    var onCompleted: () -> Void = {}

    // MARK: Init

    init(userId: String,
         initialName: String = "",
         service: OnboardingServiceProtocol? = nil) {
        self.userId = userId
        self.service = service ?? FirestoreOnboardingService()
        self.profile.firstName = initialName
    }

    deinit { saveTask?.cancel() }

    // MARK: - Step navigation

    func advance() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else {
            // No further step — caller should have invoked `complete()` instead.
            return
        }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            step = next
        }
        savePartial()
    }

    func back() {
        guard let prev = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            step = prev
        }
    }

    func skip() {
        guard step.allowsSkip else { return }
        advance()
    }

    func canAdvance() -> Bool {
        switch step {
        case .nameInput: return profile.hasName
        default:         return true
        }
    }

    // MARK: - Per-step helpers

    func toggle(goal: RelationshipGoal) {
        if profile.goals.contains(goal) {
            profile.goals.remove(goal)
        } else {
            profile.goals.insert(goal)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func setStyle(_ style: OnboardingCommunicationStyle) {
        profile.communicationStyle = style
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Updates `firstName` AND immediately mirrors to Auth + Firestore so the
    /// rest of the app reflects the chosen name (used by partner-pairing
    /// invites etc.). Returns when the write lands.
    func saveName() async {
        let trimmed = profile.firstName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        try? await service.updateDisplayName(trimmed, userId: userId)
    }

    // MARK: - Persistence

    /// Coalesce rapid taps into a single Firestore write. We want every tap
    /// to set up a write, but we don't want six writes in a row when the
    /// user races through screens — kick the save 250ms out and overwrite
    /// any earlier scheduled save.
    private func savePartial() {
        saveTask?.cancel()
        let snapshot = profile
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.service.savePartial(snapshot, userId: self.userId)
        }
    }

    /// Flush pending writes immediately. Called when the user dismisses the
    /// paywall or backgrounds the app mid-flow.
    func flush() async {
        saveTask?.cancel()
        await service.savePartial(profile, userId: userId)
    }

    // MARK: - Complete

    func complete() async {
        guard !isCompleting else { return }
        isCompleting = true
        errorMessage = nil
        do {
            try await service.complete(profile, userId: userId)
            onCompleted()
        } catch {
            errorMessage = error.localizedDescription
        }
        isCompleting = false
    }

    /// Allow paywall "Maybe Later" or any explicit dismiss to count as
    /// completion — onboarding *finished*, premium just wasn't purchased.
    func skipPaywallAndComplete() {
        Task { await complete() }
    }
}
