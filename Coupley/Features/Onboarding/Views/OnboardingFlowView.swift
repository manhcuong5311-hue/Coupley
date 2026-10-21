//
//  OnboardingFlowView.swift
//  Coupley
//
//  Container for the post-login onboarding flow. Owns a single
//  `OnboardingViewModel` and routes to the right step view based on
//  `viewModel.step`. Each step renders inside `OnboardingStepScaffold`,
//  so this view only handles step→step transitions and final completion.
//
//  Completion: when `viewModel.complete()` succeeds, it calls
//  `onCompleted`, which is wired to flip
//  `@AppStorage("hasCompletedOnboarding")` in RootView. The session state
//  is otherwise unchanged — pairing / premium / Firebase data are all
//  untouched, so the 5-tap reset gesture in Settings is safe.
//
//  Since 1.1 there is no paywall step: every feature is free, and the last
//  setup step ("Coupley is better when you're connected") completes the flow.
//

import SwiftUI

struct OnboardingFlowView: View {

    @StateObject private var viewModel: OnboardingViewModel

    /// Closure RootView passes to flip `hasCompletedOnboarding` once the
    /// terminal Firestore write lands. Kept on the view (instead of
    /// `@AppStorage` directly inside the VM) so the VM is testable without
    /// SwiftUI environment dependencies.
    let onCompleted: () -> Void

    init(userId: String,
         initialName: String = "",
         onCompleted: @escaping () -> Void) {
        _viewModel = StateObject(
            wrappedValue: OnboardingViewModel(userId: userId, initialName: initialName)
        )
        self.onCompleted = onCompleted
    }

    var body: some View {
        ZStack {
            currentStep
                .id(viewModel.step)
                .transition(transition(for: viewModel.step))
        }
        .brandBackground()
        .onAppear { viewModel.onCompleted = onCompleted }
        .onChange(of: viewModel.step) { _, _ in
            // Persist after every transition. The VM debounces internally,
            // so rapid taps coalesce into a single Firestore write.
        }
        .task {
            // Mirror the closure on every render; `onAppear` covers cold
            // starts but not preview/SwiftUI re-inits.
            viewModel.onCompleted = onCompleted
        }
    }

    // MARK: - Step routing

    @ViewBuilder
    private var currentStep: some View {
        switch viewModel.step {
        // Why
        case .welcome:           WelcomeStepView(viewModel: viewModel)
        case .benefits:          BenefitsStepView(viewModel: viewModel)
        case .moodSync:          MoodSyncStepView(viewModel: viewModel)
        case .memories:          MemoriesStepView(viewModel: viewModel)
        case .communication:     CommunicationStepView(viewModel: viewModel)
        case .aiAssistance:      AIAssistanceStepView(viewModel: viewModel)
        case .dailyConnection:   DailyConnectionStepView(viewModel: viewModel)
        // Setup
        case .nameInput:         NameInputStepView(viewModel: viewModel)
        case .partnerInput:      PartnerInputStepView(viewModel: viewModel)
        case .goals:             GoalsStepView(viewModel: viewModel)
        case .communicationStyle:CommunicationStyleStepView(viewModel: viewModel)
        case .dailyHabit:        DailyHabitStepView(viewModel: viewModel)
        case .notifications:     NotificationsStepView(viewModel: viewModel)
        case .widget:            WidgetStepView(viewModel: viewModel)
        case .partnerExpectation:PartnerExpectationStepView(viewModel: viewModel)
        }
    }

    /// Slide steps in from the trailing edge when moving forward, leading
    /// when moving back. We approximate "direction" from step rawValue
    /// changes elsewhere; here we always animate forward since the VM owns
    /// the state and back-taps re-render the previous step's view.
    private func transition(for step: OnboardingStep) -> AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal:   .move(edge: .leading).combined(with: .opacity)
        )
    }
}
