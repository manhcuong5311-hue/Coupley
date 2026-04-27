//
//  QuizHubView.swift
//  Coupley
//
//  Quiz Hub — the dedicated entry point reachable from the Chat tab. Presents
//  four flows in one premium-feeling surface:
//
//    1. Daily Quiz       → curated bank picker (existing QuizPickerSheet)
//    2. AI Suggested     → orchestrator-picked next quiz + one-tap send
//    3. Custom Quiz      → user-authored quiz that posts to chat
//    4. Quiz History     → list of completed quizzes with their results
//
//  This screen replaces the old `QuizPickerSheet`-as-toolbar-action wiring.
//  Custom Quiz is intentionally placed here, NOT on Profile, because it is a
//  relationship interaction (not a profile element).
//
//  Premium gating:
//    • Custom Quiz: free users get 1 per day (PremiumFeature.customQuizzes
//      now gated through PremiumStore daily-usage tracking).
//    • Daily Quiz topics: existing fullQuizAccess gate.
//    • AI Suggested: free for now (it's a single-tap suggestion; no quota).
//

import SwiftUI

struct QuizHubView: View {

    @ObservedObject var viewModel: ChatViewModel
    @EnvironmentObject private var premiumStore: PremiumStore
    @Environment(\.dismiss) private var dismiss

    @State private var showDailyPicker = false
    @State private var showCustomBuilder = false
    @State private var showHistory = false
    @State private var showPaywall = false
    @State private var showAIConfirmation = false
    @State private var aiSuggestion: ChatQuizTemplate?
    @State private var dailyLimitAlert = false

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.bgGradient.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        hero
                        entryGrid
                        recentQuizSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Quiz Hub")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Brand.textSecondary)
                }
            }
            .sheet(isPresented: $showDailyPicker) {
                QuizPickerSheet { template in
                    viewModel.sendQuiz(template: template)
                    dismiss()
                }
                .environmentObject(premiumStore)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Brand.backgroundTop)
            }
            .sheet(isPresented: $showCustomBuilder) {
                CustomChatQuizBuilderSheet { title, question, options, authorAnswer, allowsMultiple, note in
                    viewModel.sendCustomQuiz(
                        title: title,
                        question: question,
                        options: options,
                        authorAnswer: authorAnswer,
                        allowsMultiple: allowsMultiple,
                        note: note
                    )
                    // Burn one daily slot for free users.
                    if !premiumStore.isActive {
                        premiumStore.recordUsage(for: .customQuizzes)
                    }
                    dismiss()
                }
            }
            .sheet(isPresented: $showHistory) {
                QuizHistorySheet(quizzes: viewModel.quizzes,
                                 viewerId: viewModel.myUserId,
                                 partnerId: viewModel.partnerUserId)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(Brand.backgroundTop)
            }
            .sheet(isPresented: $showPaywall) {
                NavigationStack { PremiumPaywallView() }
                    .environmentObject(premiumStore)
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showAIConfirmation) {
                if let suggestion = aiSuggestion {
                    AISuggestionConfirmationSheet(template: suggestion) {
                        viewModel.sendQuiz(template: suggestion)
                        showAIConfirmation = false
                        dismiss()
                    } onCancel: {
                        showAIConfirmation = false
                    }
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                }
            }
            .alert("Free plan includes 1 custom quiz/day",
                   isPresented: $dailyLimitAlert) {
                Button("Upgrade", role: .none) { showPaywall = true }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Upgrade to Premium for unlimited custom quizzes, AI suggestions, and advanced quiz packs.")
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1.00, green: 0.62, blue: 0.74),
                            Color(red: 0.96, green: 0.42, blue: 0.55)
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
            Circle()
                .fill(.white.opacity(0.20))
                .frame(width: 200, height: 200)
                .blur(radius: 60)
                .offset(x: -70, y: -80)

            VStack(alignment: .leading, spacing: 10) {
                Text("Quizzes")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .kerning(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.85))
                Text("Discover\neach other")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineSpacing(2)
                Text("A few well-asked questions can move a relationship forward more than a hundred small talks.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(.white.opacity(0.20), lineWidth: 1)
        )
        .shadow(color: Color(red: 0.96, green: 0.42, blue: 0.55).opacity(0.30), radius: 18, y: 8)
    }

    // MARK: - Entry Grid

    private var entryGrid: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                entryCard(
                    title: "Daily Quiz",
                    subtitle: "Hand-picked from our library",
                    icon: "sparkles",
                    accent: Color(red: 0.95, green: 0.55, blue: 0.30),
                    isPremium: false,
                    action: { showDailyPicker = true }
                )
                entryCard(
                    title: "AI Suggested",
                    subtitle: "We'll pick what fits you both",
                    icon: "wand.and.stars",
                    accent: Color(red: 0.55, green: 0.74, blue: 0.95),
                    isPremium: false,
                    action: presentAISuggestion
                )
            }

            HStack(spacing: 12) {
                entryCard(
                    title: "Custom Quiz",
                    subtitle: customQuizSubtitle,
                    icon: "heart.text.square.fill",
                    accent: Brand.accentStart,
                    isPremium: !canCreateCustomQuiz && !premiumStore.isActive,
                    action: presentCustomBuilder
                )
                entryCard(
                    title: "History",
                    subtitle: "Your past quizzes & results",
                    icon: "clock.fill",
                    accent: Color(red: 0.40, green: 0.76, blue: 0.55),
                    isPremium: false,
                    action: { showHistory = true }
                )
            }
        }
    }

    private func entryCard(
        title: String,
        subtitle: String,
        icon: String,
        accent: Color,
        isPremium: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(accent.gradient)
                            .frame(width: 40, height: 40)
                            .shadow(color: accent.opacity(0.45), radius: 8, y: 3)
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    if isPremium {
                        premiumPill
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Brand.surfaceLight)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [accent.opacity(0.30), Brand.divider.opacity(0.40)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: accent.opacity(0.10), radius: 14, y: 5)
            )
        }
        .buttonStyle(BouncyButtonStyle(scale: 0.97))
    }

    private var premiumPill: some View {
        HStack(spacing: 4) {
            Image(systemName: "crown.fill")
                .font(.system(size: 9, weight: .semibold))
            Text("Premium")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .kerning(0.3)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1.00, green: 0.78, blue: 0.30),
                            Color(red: 0.92, green: 0.50, blue: 0.18)
                        ],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
        )
    }

    // MARK: - Recent quiz section

    /// Surface the most recent in-flight or just-completed quiz so the hub
    /// has a "live" feel even when the user already has work going.
    @ViewBuilder
    private var recentQuizSection: some View {
        if let recent = mostRecentQuiz {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(Brand.accentStart)
                    Text("Most recent")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .kerning(0.4)
                        .textCase(.uppercase)
                        .foregroundStyle(Brand.textSecondary)
                }

                recentRow(recent)
            }
            .padding(.top, 6)
        }
    }

    private var mostRecentQuiz: ChatQuiz? {
        viewModel.quizzes.max(by: { $0.createdAt < $1.createdAt })
    }

    private func recentRow(_ quiz: ChatQuiz) -> some View {
        Button(action: {
            // Just close — the quiz card lives in chat. The user already sees it.
            dismiss()
        }) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Brand.accentStart.opacity(0.14))
                        .frame(width: 38, height: 38)
                    Text(quiz.isCustom ? "❤️" : quiz.topic.emoji)
                        .font(.system(size: 18))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(quiz.question)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                        .lineLimit(1)
                    Text(quiz.statusLabel(viewerId: viewModel.myUserId,
                                          partnerId: viewModel.partnerUserId))
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Brand.textTertiary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Brand.surfaceLight)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Brand.divider, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(BouncyButtonStyle(scale: 0.98))
    }

    // MARK: - Custom Quiz gate

    /// Free users get exactly 1 custom quiz per day. Premium is unlimited.
    /// PremiumStore.hasAccess(.customQuizzes) returns true under both paths
    /// (premium OR a free user with their daily slot still available), so
    /// we use it as the unified gate.
    private var canCreateCustomQuiz: Bool {
        premiumStore.hasAccess(to: .customQuizzes)
    }

    private var customQuizSubtitle: String {
        if premiumStore.isActive {
            return "Create your own — unlimited"
        }
        if canCreateCustomQuiz {
            return "Create your own — 1 free today"
        }
        return "Daily limit reached — upgrade for unlimited"
    }

    private func presentCustomBuilder() {
        if canCreateCustomQuiz {
            showCustomBuilder = true
        } else {
            dailyLimitAlert = true
        }
    }

    private func presentAISuggestion() {
        // Pick a quiz the couple hasn't done lately. We avoid running the
        // full orchestrator transaction here (that's reserved for the
        // automatic background suggestion) and just sample from the bank
        // by recency-of-use.
        let usedIds = Set(viewModel.quizzes.map(\.questionId))
        let candidates = ChatQuizBank.all.filter { !usedIds.contains($0.questionId) }
        let pool = candidates.isEmpty ? ChatQuizBank.all : candidates
        guard let pick = pool.randomElement() else { return }
        aiSuggestion = pick
        showAIConfirmation = true
    }
}

// MARK: - AI Suggestion Confirmation

/// Quick confirmation step before posting an AI-suggested quiz to chat.
/// Gives the user one tap to accept or reroll.
struct AISuggestionConfirmationSheet: View {

    let template: ChatQuizTemplate
    let onSend: () -> Void
    let onCancel: () -> Void

    @State private var current: ChatQuizTemplate

    init(template: ChatQuizTemplate, onSend: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.template = template
        self.onSend = onSend
        self.onCancel = onCancel
        _current = State(initialValue: template)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.bgGradient.ignoresSafeArea()

                VStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 6) {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 12, weight: .semibold))
                            Text(current.topic.label.uppercased())
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .kerning(0.5)
                        }
                        .foregroundStyle(Brand.accentStart)

                        Text(current.question)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(Brand.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(current.subtitle)
                            .font(.system(size: 14, design: .rounded))
                            .foregroundStyle(Brand.textSecondary)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Brand.surfaceLight)
                            .overlay(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .strokeBorder(Brand.accentStart.opacity(0.25), lineWidth: 1)
                            )
                    )

                    HStack(spacing: 12) {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            current = ChatQuizBank.all.randomElement() ?? current
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.clockwise")
                                Text("Try another")
                            }
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(Brand.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                Capsule().fill(Brand.surfaceLight)
                                    .overlay(Capsule().strokeBorder(Brand.divider, lineWidth: 1))
                            )
                        }
                        .buttonStyle(BouncyButtonStyle())

                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            onSend()
                        } label: {
                            Text("Send to chat")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    Capsule().fill(Brand.accentGradient)
                                        .shadow(color: Brand.accentStart.opacity(0.40), radius: 10, y: 3)
                                )
                        }
                        .buttonStyle(BouncyButtonStyle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .navigationTitle("AI Suggestion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { onCancel() }
                        .foregroundStyle(Brand.textSecondary)
                }
            }
        }
    }
}

// MARK: - Quiz History Sheet

struct QuizHistorySheet: View {

    let quizzes: [ChatQuiz]
    let viewerId: String
    let partnerId: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.bgGradient.ignoresSafeArea()

                if quizzes.isEmpty {
                    emptyState
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 10) {
                            ForEach(sortedQuizzes) { quiz in
                                historyRow(quiz)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                    }
                }
            }
            .navigationTitle("Your Quizzes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Brand.textSecondary)
                }
            }
        }
    }

    private var sortedQuizzes: [ChatQuiz] {
        quizzes.sorted { $0.createdAt > $1.createdAt }
    }

    private func historyRow(_ quiz: ChatQuiz) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Text(quiz.isCustom ? "❤️" : quiz.topic.emoji)
                    Text(quiz.isCustom ? "Custom" : quiz.topic.label)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(quiz.isCustom ? Brand.accentStart : Brand.textSecondary)
                        .textCase(.uppercase)
                        .kerning(0.5)
                }
                Spacer()
                statusChip(for: quiz)
            }

            Text(quiz.question)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Brand.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            if let result = quiz.result {
                HStack(spacing: 8) {
                    Text(result.emoji)
                        .font(.system(size: 16))
                    Text(result.summary)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)
                        .lineLimit(2)
                }
                .padding(.top, 2)
            }

            Text(quiz.createdAt.formatted(.relative(presentation: .named)))
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(Brand.textTertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Brand.surfaceLight)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Brand.divider, lineWidth: 1)
                )
        )
    }

    private func statusChip(for quiz: ChatQuiz) -> some View {
        let label: String
        let color: Color
        switch quiz.status {
        case .pending:
            label = "Waiting"
            color = Brand.textTertiary
        case .partial:
            label = "1 of 2"
            color = Color(red: 0.95, green: 0.55, blue: 0.30)
        case .complete:
            label = "Complete"
            color = Color(red: 0.30, green: 0.78, blue: 0.50)
        }
        return Text(label)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.14)))
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.fill")
                .font(.system(size: 38))
                .foregroundStyle(Brand.accentStart.opacity(0.6))
            Text("No quizzes yet")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Brand.textPrimary)
            Text("Send your first quiz from the Hub to start your history.")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Brand.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
                .lineSpacing(2)
        }
    }
}

// MARK: - ChatQuiz status helper

private extension ChatQuiz {
    /// Short row-status used by the recent-quiz tile and the history list.
    func statusLabel(viewerId: String, partnerId: String) -> String {
        switch status {
        case .pending:
            return hasAnswered(viewerId) ? "Waiting on partner" : "Your turn"
        case .partial:
            return hasAnswered(viewerId) ? "Waiting on partner" : "Your turn"
        case .complete:
            if let summary = result?.summary { return summary }
            return "Complete"
        }
    }
}
