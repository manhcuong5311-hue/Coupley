//
//  AICoachHomeView.swift
//  Coupley
//
//  Entry screen for the AI Relationship Coach. Hero + quick-action issue
//  cards that open the guided coaching flow, plus shortcuts to the
//  premium-only features (rewrite, health check, recovery plan).
//

import SwiftUI

struct AICoachHomeView: View {

    @EnvironmentObject var premiumStore: PremiumStore
    @ObservedObject var viewModel: AICoachViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedIssue: CoachIssueType?
    @State private var showChat = false
    @State private var showRewrite = false
    @State private var showHealth = false
    @State private var showRecovery = false
    @State private var showPaywall = false

    var body: some View {
        ZStack {
            Brand.bgGradient.ignoresSafeArea()
            ambientGlows

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    hero
                        .padding(.top, 8)
                        .padding(.horizontal, 20)

                    if !viewModel.messages.isEmpty {
                        resumeCard
                            .padding(.horizontal, 20)
                    }

                    quickActions
                        .padding(.horizontal, 20)

                    premiumTools
                        .padding(.horizontal, 20)

                    footer
                        .padding(.horizontal, 32)
                        .padding(.bottom, 32)
                }
                .padding(.top, 12)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Brand.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Brand.surfaceLight))
                        .overlay(Circle().strokeBorder(Brand.divider, lineWidth: 1))
                }
            }
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    CoachAvatar(size: 24)
                    Text("AI Relationship Coach")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                }
            }
            if !viewModel.messages.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            viewModel.clearTranscript()
                        } label: {
                            Label("Clear conversation", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Brand.textSecondary)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Brand.surfaceLight))
                            .overlay(Circle().strokeBorder(Brand.divider, lineWidth: 1))
                    }
                }
            }
        }
        .sheet(isPresented: $showChat) {
            NavigationStack {
                AICoachChatView(viewModel: viewModel, initialIssue: selectedIssue)
            }
            .presentationDragIndicator(.visible)
            .presentationBackground(Brand.backgroundTop)
        }
        .sheet(isPresented: $showRewrite) {
            NavigationStack {
                AICoachRewriteView(viewModel: viewModel)
            }
            .presentationDragIndicator(.visible)
            .presentationBackground(Brand.backgroundTop)
        }
        .sheet(isPresented: $showHealth) {
            NavigationStack {
                AICoachHealthCheckView(viewModel: viewModel)
            }
            .presentationDragIndicator(.visible)
            .presentationBackground(Brand.backgroundTop)
        }
        .sheet(isPresented: $showRecovery) {
            NavigationStack {
                AICoachRecoveryPlanView(viewModel: viewModel)
            }
            .presentationDragIndicator(.visible)
            .presentationBackground(Brand.backgroundTop)
        }
        .sheet(isPresented: $showPaywall) {
            NavigationStack { PremiumPaywallView() }
                .environmentObject(premiumStore)
                .presentationDragIndicator(.visible)
        }
        .onAppear { viewModel.load() }
    }

    // MARK: - Ambient glows

    private var ambientGlows: some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.95, green: 0.55, blue: 0.72).opacity(0.14))
                .frame(width: 320, height: 320)
                .blur(radius: 90)
                .offset(x: -80, y: -220)
            Circle()
                .fill(Color(red: 0.52, green: 0.44, blue: 0.95).opacity(0.12))
                .frame(width: 260, height: 260)
                .blur(radius: 80)
                .offset(x: 100, y: 260)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 14) {
            CoachAvatar(size: 64)
                .padding(.top, 6)

            VStack(spacing: 6) {
                Text("Let's work through this together.")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)

                Text("Real support for real relationship problems.")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 8)
        }
    }

    // MARK: - Resume card

    private var resumeCard: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            selectedIssue = nil
            showChat = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Brand.accentStart.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Brand.accentStart)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Continue where you left off")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                    Text("\(viewModel.messages.count) message\(viewModel.messages.count == 1 ? "" : "s") saved")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Brand.textTertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Brand.surfaceLight)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(Brand.accentStart.opacity(0.35), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(BouncyButtonStyle(scale: 0.97))
    }

    // MARK: - Quick actions

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 14) {
            CoachSectionTitle(text: "What do you need help with?")
                .padding(.leading, 4)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(CoachIssueType.allCases.filter { $0 != .custom }) { issue in
                    issueCard(issue)
                }
            }

            customCard
        }
    }

    private func issueCard(_ issue: CoachIssueType) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            tapIssue(issue)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(issue.tint.primary.opacity(0.15))
                        .frame(width: 42, height: 42)
                    Image(systemName: issue.icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(issue.tint.primary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(issue.title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(issue.subtitle)
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Brand.surfaceLight)
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Brand.divider, lineWidth: 1))
                    .shadow(color: .black.opacity(0.06), radius: 10, y: 3)
            )
        }
        .buttonStyle(BouncyButtonStyle(scale: 0.96))
    }

    private var customCard: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            tapIssue(.custom)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [Brand.accentStart.opacity(0.22), Brand.accentEnd.opacity(0.22)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 42, height: 42)
                    Image(systemName: CoachIssueType.custom.icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Brand.accentStart)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(CoachIssueType.custom.title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                    Text(CoachIssueType.custom.subtitle)
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Brand.textTertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Brand.surfaceLight)
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Brand.divider, lineWidth: 1))
            )
        }
        .buttonStyle(BouncyButtonStyle(scale: 0.97))
    }

    // MARK: - Premium tools

    private var premiumTools: some View {
        VStack(alignment: .leading, spacing: 14) {
            CoachSectionTitle(text: "Coach Toolkit")
                .padding(.leading, 4)

            VStack(spacing: 10) {
                toolRow(
                    icon: "wand.and.stars",
                    tint: Color(red: 0.52, green: 0.44, blue: 0.95),
                    title: "Rewrite my message",
                    subtitle: "Say it the way you meant it",
                    isPremium: true
                ) { openPremiumTool { showRewrite = true } }

                toolRow(
                    icon: "heart.circle.fill",
                    tint: Color(red: 0.95, green: 0.45, blue: 0.60),
                    title: "Relationship health check",
                    subtitle: "Trust, communication, intimacy & more",
                    isPremium: true
                ) { openPremiumTool { showHealth = true } }

                toolRow(
                    icon: "calendar.badge.plus",
                    tint: Color(red: 0.48, green: 0.75, blue: 0.56),
                    title: "Conflict recovery plan",
                    subtitle: "3 or 7 day reconnect roadmap",
                    isPremium: true
                ) { openPremiumTool { showRecovery = true } }
            }
        }
    }

    private func toolRow(
        icon: String,
        tint: Color,
        title: String,
        subtitle: String,
        isPremium: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(tint.opacity(0.16))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(Brand.textPrimary)
                        if isPremium && !premiumStore.isActive {
                            CoachPremiumBadge()
                        }
                    }
                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: premiumStore.isActive || !isPremium ? "arrow.right" : "lock.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Brand.textTertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Brand.surfaceLight)
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Brand.divider, lineWidth: 1))
            )
        }
        .buttonStyle(BouncyButtonStyle(scale: 0.97))
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Text("Your conversations are private and saved only on this device.")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(Brand.textTertiary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
    }

    // MARK: - Actions

    private func tapIssue(_ issue: CoachIssueType) {
        if !premiumStore.hasAccess(to: .aiCoach) {
            showPaywall = true
            return
        }
        if !premiumStore.isActive {
            // Free users: each full session consumes the daily quota.
            premiumStore.recordUsage(for: .aiCoach)
        }
        selectedIssue = issue
        showChat = true
    }

    private func openPremiumTool(_ open: () -> Void) {
        if premiumStore.isActive {
            open()
        } else {
            showPaywall = true
        }
    }
}
