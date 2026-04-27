//
//  TogetherView.swift
//  Coupley
//
//  Main container for the Together tab. Composes the four sections in order:
//
//    1. Today Together Hero      — TogetherTodayHero
//    2. Active Goals             — ActiveGoalsSection
//       Couple Challenges        — ActiveChallengesSection (visually paired)
//    3. Dream Board              — DreamBoardSection
//    4. AI Couple Coach          — CoupleCoachSection
//
//  Sheet routing is centralized here using a single `presentedSheet` enum
//  rather than a stack of @State Bools — avoids the SwiftUI footgun where
//  two sheets get presented in the same tick and one disappears.
//

import SwiftUI

// MARK: - Sheet Route

private enum TogetherSheet: Identifiable {
    case createGoal(prefilledTitle: String?)
    case editGoal(TogetherGoal)
    case goalDetail(TogetherGoal)
    case createChallenge(prefilledTitle: String?)
    case challengeDetail(CoupleChallenge)
    case createDream(prefilledTitle: String?)
    case dreamDetail(Dream)
    case paywall

    var id: String {
        switch self {
        case .createGoal:                 return "create-goal"
        case .editGoal(let g):            return "edit-goal-\(g.id)"
        case .goalDetail(let g):          return "detail-goal-\(g.id)"
        case .createChallenge:            return "create-challenge"
        case .challengeDetail(let c):     return "detail-challenge-\(c.id)"
        case .createDream:                return "create-dream"
        case .dreamDetail(let d):         return "detail-dream-\(d.id)"
        case .paywall:                    return "paywall"
        }
    }
}

// MARK: - Together View

struct TogetherView: View {

    @StateObject private var viewModel: TogetherViewModel
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var premiumStore: PremiumStore
    @Environment(\.scenePhase) private var scenePhase

    private let session: UserSession

    @State private var presentedSheet: TogetherSheet?
    @State private var didAppear = false

    // MARK: - Init

    init(session: UserSession) {
        self.session = session
        _viewModel = StateObject(wrappedValue: TogetherViewModel(session: session))
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.bgGradient.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 28) {
                        Color.clear.frame(height: 4)

                        if !session.isPaired {
                            notPairedCard
                                .padding(.horizontal, 20)
                        } else if viewModel.goals.isEmpty &&
                                    viewModel.challenges.isEmpty &&
                                    viewModel.dreams.isEmpty {

                            // Brand-new state — empty hero + the four placeholder sections.
                            TogetherEmptyHero(
                                onAddDream: { presentedSheet = .createDream(prefilledTitle: nil) },
                                onAddGoal:  { presentedSheet = .createGoal(prefilledTitle: nil) }
                            )
                            .padding(.horizontal, 20)

                            ActiveGoalsSection(
                                goals: [],
                                userId: viewModel.sessionUserId,
                                isPremium: hasUnlimitedGoals,
                                onSelect: { _ in },
                                onCreate: { presentedSheet = .createGoal(prefilledTitle: nil) },
                                onShowPaywall: { presentedSheet = .paywall }
                            )
                            .padding(.horizontal, 20)

                            ActiveChallengesSection(
                                challenges: [],
                                userId: viewModel.sessionUserId,
                                isPremium: hasUnlimitedChallenges,
                                onSelect: { _ in },
                                onCheckIn: { _ in },
                                onCreate: { presentedSheet = .createChallenge(prefilledTitle: nil) },
                                onShowPaywall: { presentedSheet = .paywall }
                            )
                            .padding(.horizontal, 20)

                            DreamBoardSection(
                                dreams: [],
                                isPremium: hasFullDreamBoard,
                                onSelect: { _ in },
                                onCreate: { presentedSheet = .createDream(prefilledTitle: nil) },
                                onShowPaywall: { presentedSheet = .paywall }
                            )
                            .padding(.horizontal, 20)

                            CoupleCoachSection(
                                insights: viewModel.insights,
                                stats: viewModel.stats,
                                isPremium: hasCoach,
                                onAction: handleInsightAction,
                                onShowPaywall: { presentedSheet = .paywall }
                            )
                            .padding(.horizontal, 20)
                        } else {
                            // Section 1 — Today Together
                            TogetherTodayHero(
                                stats: viewModel.stats,
                                headline: viewModel.headlineInsight,
                                leadingGoal: leadingGoal,
                                longestStreakChallenge: longestStreakChallenge,
                                onOpenLeadingGoal: {
                                    if let g = leadingGoal {
                                        presentedSheet = .goalDetail(g)
                                    }
                                },
                                onOpenLongestStreakChallenge: {
                                    if let c = longestStreakChallenge {
                                        presentedSheet = .challengeDetail(c)
                                    }
                                },
                                onTapHeadline: {
                                    if let action = viewModel.headlineInsight?.action {
                                        handleInsightAction(action)
                                    }
                                }
                            )
                            .padding(.horizontal, 20)

                            // Section 2 — Active Goals + Challenges
                            VStack(spacing: 22) {
                                ActiveGoalsSection(
                                    goals: viewModel.activeGoals,
                                    userId: viewModel.sessionUserId,
                                    isPremium: hasUnlimitedGoals,
                                    onSelect: { presentedSheet = .goalDetail($0) },
                                    onCreate: { presentedSheet = .createGoal(prefilledTitle: nil) },
                                    onShowPaywall: { presentedSheet = .paywall }
                                )

                                ActiveChallengesSection(
                                    challenges: viewModel.activeChallenges,
                                    userId: viewModel.sessionUserId,
                                    isPremium: hasUnlimitedChallenges,
                                    onSelect: { presentedSheet = .challengeDetail($0) },
                                    onCheckIn: { challenge in
                                        Task { await viewModel.checkInToChallenge(challenge) }
                                    },
                                    onCreate: { presentedSheet = .createChallenge(prefilledTitle: nil) },
                                    onShowPaywall: { presentedSheet = .paywall }
                                )
                            }
                            .padding(.horizontal, 20)

                            // Section 3 — Dream Board
                            DreamBoardSection(
                                dreams: viewModel.dreams,
                                isPremium: hasFullDreamBoard,
                                onSelect: { presentedSheet = .dreamDetail($0) },
                                onCreate: { presentedSheet = .createDream(prefilledTitle: nil) },
                                onShowPaywall: { presentedSheet = .paywall }
                            )
                            .padding(.horizontal, 20)

                            // Section 4 — AI Couple Coach
                            CoupleCoachSection(
                                insights: viewModel.insights,
                                stats: viewModel.stats,
                                isPremium: hasCoach,
                                onAction: handleInsightAction,
                                onShowPaywall: { presentedSheet = .paywall }
                            )
                            .padding(.horizontal, 20)
                        }

                        // Bottom spacer so the last card clears the tab bar.
                        Color.clear.frame(height: 100)
                    }
                    .opacity(didAppear ? 1 : 0)
                    .offset(y: didAppear ? 0 : 12)
                }

                // Streak celebration overlay
                if let challenge = viewModel.pendingStreakCelebration {
                    StreakCelebrationOverlay(
                        challenge: challenge,
                        onDismiss: { viewModel.acknowledgeStreakCelebration() }
                    )
                    .zIndex(900)
                }
            }
            .navigationTitle("Together")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if session.isPaired {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button {
                                presentedSheet = .createGoal(prefilledTitle: nil)
                            } label: {
                                Label("New goal", systemImage: "target")
                            }
                            Button {
                                presentedSheet = .createChallenge(prefilledTitle: nil)
                            } label: {
                                Label("New challenge", systemImage: "flame.fill")
                            }
                            Button {
                                presentedSheet = .createDream(prefilledTitle: nil)
                            } label: {
                                Label("New dream", systemImage: "sparkles")
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Brand.accentGradient)
                                    .frame(width: 34, height: 34)
                                    .shadow(color: Brand.accentStart.opacity(0.35), radius: 8, y: 3)
                                Image(systemName: "plus")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                }
            }
            .onAppear {
                viewModel.startListening()
                withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) {
                    didAppear = true
                }
            }
            .onDisappear {
                viewModel.stopListening()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { viewModel.refresh() }
            }
            .onChange(of: sessionStore.isPaired) { _, paired in
                if paired { viewModel.startListening() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .togetherShowPaywall)) { _ in
                presentedSheet = .paywall
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.85),
                       value: viewModel.pendingStreakCelebration?.id)
            .sheet(item: $presentedSheet) { sheet in
                sheetContent(for: sheet)
            }
        }
    }

    // MARK: - Sheet Content

    @ViewBuilder
    private func sheetContent(for sheet: TogetherSheet) -> some View {
        switch sheet {
        case .createGoal:
            GoalEditorSheet(viewModel: viewModel, mode: .create)
                .environmentObject(premiumStore)
                .presentationDetents([.large])
        case .editGoal(let goal):
            GoalEditorSheet(viewModel: viewModel, mode: .edit(goal))
                .environmentObject(premiumStore)
                .presentationDetents([.large])
        case .goalDetail(let goal):
            GoalDetailSheet(goal: goal, viewModel: viewModel)
                .environmentObject(premiumStore)
                .presentationDetents([.large])
        case .createChallenge:
            ChallengeEditorSheet(viewModel: viewModel)
                .environmentObject(premiumStore)
                .presentationDetents([.large])
        case .challengeDetail(let challenge):
            ChallengeDetailSheet(challenge: challenge, viewModel: viewModel)
                .presentationDetents([.large])
        case .createDream:
            DreamEditorSheet(viewModel: viewModel, mode: .create)
                .environmentObject(premiumStore)
                .presentationDetents([.large])
        case .dreamDetail(let dream):
            DreamDetailSheet(
                dream: dream,
                viewModel: viewModel,
                onTurnIntoGoal: { dreamToConvert in
                    // Re-present a goal editor pre-filled with this dream's title.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        presentedSheet = .createGoal(prefilledTitle: dreamToConvert.title)
                    }
                }
            )
            .environmentObject(premiumStore)
            .presentationDetents([.large])
        case .paywall:
            NavigationStack {
                PremiumPaywallView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { presentedSheet = nil }
                                .foregroundStyle(Brand.accentStart)
                        }
                    }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Insight Routing

    private func handleInsightAction(_ action: InsightAction) {
        switch action {
        case .openGoal(let id):
            if let g = viewModel.goals.first(where: { $0.id == id }) {
                presentedSheet = .goalDetail(g)
            }
        case .openChallenge(let id):
            if let c = viewModel.challenges.first(where: { $0.id == id }) {
                presentedSheet = .challengeDetail(c)
            }
        case .openDream(let id):
            if let d = viewModel.dreams.first(where: { $0.id == id }) {
                presentedSheet = .dreamDetail(d)
            }
        case .createGoal(let suggestion):
            presentedSheet = .createGoal(prefilledTitle: suggestion)
        case .createChallenge(let suggestion):
            presentedSheet = .createChallenge(prefilledTitle: suggestion)
        case .createDream(let suggestion):
            presentedSheet = .createDream(prefilledTitle: suggestion)
        case .openPaywall:
            presentedSheet = .paywall
        }
    }

    // MARK: - Selectors

    private var leadingGoal: TogetherGoal? {
        viewModel.activeGoals.first
    }

    private var longestStreakChallenge: CoupleChallenge? {
        viewModel.activeChallenges.max(by: { $0.streak.current < $1.streak.current })
    }

    // MARK: - Premium accessors

    private var hasUnlimitedGoals: Bool { premiumStore.hasAccess(to: .togetherGoalsUnlimited) }
    private var hasUnlimitedChallenges: Bool { premiumStore.hasAccess(to: .togetherChallengesUnlimited) }
    private var hasFullDreamBoard: Bool { premiumStore.hasAccess(to: .togetherDreamBoard) }
    private var hasCoach: Bool { premiumStore.hasAccess(to: .togetherCoach) }

    // MARK: - Not Paired Card

    private var notPairedCard: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Brand.accentStart.opacity(0.10))
                    .frame(width: 88, height: 88)
                Image(systemName: "infinity")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(Brand.accentStart.opacity(0.85))
            }

            VStack(spacing: 8) {
                Text("Connect with your partner first")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                Text("Goals, challenges, and dreams live across both of you. Pair up to start building together.")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Brand.surfaceLight)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Brand.divider, lineWidth: 1)
                )
        )
        .padding(.top, 12)
    }
}

// MARK: - Preview

#Preview {
    TogetherView(session: .demo)
        .environmentObject(SessionStore())
        .environmentObject(PremiumStore())
}
