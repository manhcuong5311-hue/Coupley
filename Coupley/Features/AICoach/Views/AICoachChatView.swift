//
//  AICoachChatView.swift
//  Coupley
//
//  Chat-style coaching transcript. Renders both freeform replies (simple
//  bubbles) and structured guided responses (rich, multi-section cards).
//

import SwiftUI

struct AICoachChatView: View {

    @ObservedObject var viewModel: AICoachViewModel
    @EnvironmentObject var premiumStore: PremiumStore
    @Environment(\.dismiss) private var dismiss

    let initialIssue: CoachIssueType?

    @State private var pendingIssue: CoachIssueType?
    @State private var showCopiedToast = false
    @State private var copiedText: String?
    @FocusState private var inputFocused: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            Brand.bgGradient.ignoresSafeArea()

            transcript

            inputBar
        }
        .navigationTitle("Coach")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Brand.textSecondary)
                }
            }
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    CoachAvatar(size: 24)
                    Text("AI Coach")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                }
            }
        }
        .onAppear {
            viewModel.load()
            if let issue = initialIssue, pendingIssue == nil {
                pendingIssue = issue
                inputFocused = true
            }
        }
        .overlay(alignment: .top) {
            if showCopiedToast {
                copiedToast
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    if viewModel.messages.isEmpty {
                        emptyState
                            .padding(.top, 24)
                            .padding(.horizontal, 20)
                    }

                    if let issue = pendingIssue, !hasActiveMessagesFor(issue) {
                        issuePromptCard(issue: issue)
                            .padding(.horizontal, 16)
                    }

                    ForEach(viewModel.messages) { message in
                        messageRow(for: message)
                            .id(message.id)
                    }

                    if viewModel.isSending {
                        HStack(alignment: .top, spacing: 10) {
                            CoachAvatar(size: 28)
                            CoachTypingIndicator()
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 16)
                        .transition(.opacity)
                    }

                    Color.clear.frame(height: 130)
                        .id("bottom")
                }
                .padding(.vertical, 12)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: viewModel.isSending) { _, _ in
                withAnimation(.easeOut) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            CoachAvatar(size: 56)
            VStack(spacing: 6) {
                Text("I'm here. What's going on?")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                    .multilineTextAlignment(.center)
                Text("Tell me what happened — as much or as little as you want. I'll help you work through it.")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 20)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    // MARK: - Issue prompt (shown when user arrived with a specific issue selected)

    private func issuePromptCard(issue: CoachIssueType) -> some View {
        CoachCard(tint: issue.tint.primary) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(issue.tint.primary.opacity(0.15))
                            .frame(width: 36, height: 36)
                        Image(systemName: issue.icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(issue.tint.primary)
                    }
                    Text(issue.title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                    Spacer(minLength: 0)
                }

                Text("Before I respond, tell me a bit about what's going on. A few prompts to start:")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
                    .lineSpacing(3)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(issue.contextQuestions, id: \.self) { q in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(issue.tint.primary.opacity(0.5))
                                .frame(width: 4, height: 4)
                                .padding(.top, 7)
                            Text(q)
                                .font(.system(size: 13, design: .rounded))
                                .foregroundStyle(Brand.textPrimary)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Message rendering

    @ViewBuilder
    private func messageRow(for message: CoachChatMessage) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Brand.accentGradient)
                    )
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)

        case .coach:
            if let guided = message.guided {
                guidedResponseCard(guided)
                    .padding(.horizontal, 16)
            } else {
                HStack(alignment: .top, spacing: 10) {
                    CoachAvatar(size: 28)
                    Text(message.text)
                        .font(.system(size: 14.5, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                        .lineSpacing(4)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Brand.surfaceLight)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18)
                                        .strokeBorder(Brand.divider, lineWidth: 1)
                                )
                        )
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 16)
            }

        case .systemPrompt:
            HStack {
                Spacer()
                Text(message.text)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Brand.surfaceLight)
                            .overlay(Capsule().strokeBorder(Brand.divider, lineWidth: 1))
                    )
                Spacer()
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Guided response card

    private func guidedResponseCard(_ guided: GuidedResponse) -> some View {
        CoachCard(tint: guided.issue.tint.primary) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    CoachAvatar(size: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Coach reading")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Brand.textSecondary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                        Text(guided.issue.title)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(Brand.textPrimary)
                    }
                    Spacer()
                }

                guidedSection(
                    icon: "eye.fill",
                    tint: guided.issue.tint.primary,
                    title: "Situation",
                    body: guided.situationAnalysis
                )

                guidedSection(
                    icon: "heart.text.square",
                    tint: Color(red: 0.95, green: 0.45, blue: 0.60),
                    title: "Partner's perspective",
                    body: guided.partnerPerspective
                )

                guidedSection(
                    icon: "arrow.forward.circle.fill",
                    tint: Color(red: 0.48, green: 0.75, blue: 0.56),
                    title: "Best next action",
                    body: guided.bestNextAction
                )

                guidedSection(
                    icon: "exclamationmark.octagon.fill",
                    tint: Color(red: 0.95, green: 0.55, blue: 0.35),
                    title: "What NOT to do",
                    body: guided.whatNotToDo
                )

                suggestedMessageBlock(guided.suggestedMessage)

                guidedSection(
                    icon: "infinity",
                    tint: Color(red: 0.52, green: 0.44, blue: 0.95),
                    title: "Long-term advice",
                    body: guided.longTermAdvice
                )
            }
            .padding(18)
        }
    }

    private func guidedSection(icon: String, tint: Color, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
            Text(body)
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(Brand.textPrimary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func suggestedMessageBlock(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "quote.opening")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Brand.accentStart)
                Text("Suggested message")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer()
                Button {
                    copy(message)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Copy")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(Brand.accentStart)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Brand.accentStart.opacity(0.12))
                    )
                }
            }

            Text(message)
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(Brand.textPrimary)
                .italic()
                .lineSpacing(4)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            LinearGradient(
                                colors: [Brand.accentStart.opacity(0.08), Brand.accentEnd.opacity(0.08)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(Brand.accentStart.opacity(0.25), lineWidth: 1)
                        )
                )
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Input bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [Brand.backgroundTop.opacity(0), Brand.backgroundTop],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 22)
            .allowsHitTesting(false)

            HStack(alignment: .bottom, spacing: 10) {
                ZStack(alignment: .topLeading) {
                    if viewModel.input.isEmpty {
                        Text(placeholder)
                            .font(.system(size: 14, design: .rounded))
                            .foregroundStyle(Brand.textTertiary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $viewModel.input)
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .frame(minHeight: 42, maxHeight: 120)
                        .focused($inputFocused)
                }
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Brand.surfaceLight)
                        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Brand.divider, lineWidth: 1))
                )

                Button {
                    send()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(
                            Circle()
                                .fill(canSend ? Brand.accentGradient : LinearGradient(colors: [Brand.divider, Brand.divider], startPoint: .top, endPoint: .bottom))
                                .shadow(color: Brand.accentStart.opacity(canSend ? 0.4 : 0), radius: 10, y: 3)
                        )
                }
                .disabled(!canSend || viewModel.isSending)
                .buttonStyle(BouncyButtonStyle())
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 8)
            .background(
                Brand.backgroundTop
                    .overlay(
                        Rectangle()
                            .fill(Brand.divider.opacity(0.4))
                            .frame(height: 1),
                        alignment: .top
                    )
            )
        }
    }

    private var placeholder: String {
        if let issue = pendingIssue, !hasActiveMessagesFor(issue) {
            return "Describe what happened in your own words…"
        }
        return "Message the coach…"
    }

    private var canSend: Bool {
        !viewModel.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        Task {
            if let issue = pendingIssue, !hasActiveMessagesFor(issue) {
                let text = viewModel.input
                viewModel.input = ""
                await viewModel.runGuidedFlow(for: issue, userInput: text)
                pendingIssue = nil
            } else {
                await viewModel.sendChatMessage()
            }
        }
    }

    private func hasActiveMessagesFor(_ issue: CoachIssueType) -> Bool {
        // If the user already has *some* messages in this session, we don't
        // re-prompt them with the issue framing card — they're already in it.
        return !viewModel.messages.isEmpty && viewModel.activeIssue == issue
    }

    // MARK: - Copy toast

    private func copy(_ text: String) {
        UIPasteboard.general.string = text
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        copiedText = text
        withAnimation { showCopiedToast = true }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            withAnimation { showCopiedToast = false }
        }
    }

    private var copiedToast: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.white)
            Text("Copied")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Brand.accentGradient)
                .shadow(color: Brand.accentStart.opacity(0.4), radius: 12, y: 4)
        )
    }
}
