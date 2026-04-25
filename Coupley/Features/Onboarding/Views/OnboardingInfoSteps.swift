//
//  OnboardingInfoSteps.swift
//  Coupley
//
//  The "why you'll love this" half of onboarding. Every screen here pitches
//  an outcome — what the user *gets* — rather than a feature. Copy is
//  retention-oriented and mirrors the language top relationship/lifestyle
//  apps use on the App Store: warm, grown-up, never gimmicky.
//

import SwiftUI

// MARK: - Welcome

struct WelcomeStepView: View {

    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        OnboardingStepScaffold(
            viewModel: viewModel,
            primaryTitle: "Let's begin",
            canAdvance: true,
            hideBack: true,
            hideProgress: true
        ) {
            VStack(spacing: 28) {
                Spacer(minLength: 20)

                OnboardingHeroIcon(icon: "heart.text.square.fill",
                                   tint: Brand.accentStart,
                                   size: 110)
                    .padding(.bottom, 4)

                VStack(spacing: 14) {
                    Text("Welcome to a kinder kind of love.")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Coupley helps the two of you stay close — quietly, every day. No drama, no streaks for the sake of streaks. Just little reminders that you're loved.")
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12)

                Spacer(minLength: 12)
            }
        }
    }
}

// MARK: - Benefits ("What you'll gain")

struct BenefitsStepView: View {

    @ObservedObject var viewModel: OnboardingViewModel

    private let tiles: [(icon: String, tint: Color, title: String, copy: String)] = [
        ("heart.fill",
         Color(red: 1.0, green: 0.42, blue: 0.55),
         "Closer, every day",
         "Small, daily moments of feeling thought-of."),
        ("calendar.badge.clock",
         Color(red: 0.95, green: 0.65, blue: 0.20),
         "Never forget what matters",
         "Anniversaries, birthdays, the little dates."),
        ("bubble.left.and.bubble.right.fill",
         Color(red: 0.45, green: 0.62, blue: 1.0),
         "Fewer misunderstandings",
         "Tools that nudge you toward kinder words."),
        ("sparkles",
         Color(red: 0.65, green: 0.45, blue: 1.0),
         "A little help when you need it",
         "Date ideas, gentle prompts, and AI on standby.")
    ]

    var body: some View {
        OnboardingStepScaffold(viewModel: viewModel) {
            VStack(alignment: .leading, spacing: 22) {
                StepHeader(
                    eyebrow: "What you'll gain",
                    title: "More of the good stuff,\nless of the noise.",
                    subtitle: "Coupley quietly takes care of the small things — so you can focus on each other."
                )
                .padding(.top, 8)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                    GridItem(.flexible(), spacing: 12)],
                          spacing: 12) {
                    ForEach(tiles, id: \.title) { tile in
                        BenefitTile(icon: tile.icon, tint: tile.tint, title: tile.title, copy: tile.copy)
                    }
                }
            }
        }
    }
}

// MARK: - Mood Sync

struct MoodSyncStepView: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        OnboardingStepScaffold(viewModel: viewModel) {
            infoLayout(
                icon: "heart.text.square.fill",
                tint: Color(red: 1.0, green: 0.42, blue: 0.55),
                eyebrow: "Mood Sync",
                title: "Know how they feel,\neven when you can't ask.",
                subtitle: "A glance at their mood is sometimes worth a thousand check-ins. You'll feel each other's day without lifting a finger.",
                bullets: [
                    "Share your mood in one tap",
                    "See theirs at the top of your home",
                    "Get a gentle nudge when something shifts"
                ]
            )
        }
    }
}

// MARK: - Memories

struct MemoriesStepView: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        OnboardingStepScaffold(viewModel: viewModel) {
            infoLayout(
                icon: "calendar.badge.clock",
                tint: Color(red: 0.95, green: 0.65, blue: 0.20),
                eyebrow: "Shared Memories",
                title: "Never forget the moments\nthat made you, you.",
                subtitle: "Anniversaries, first dates, the little inside-joke days. We'll remember them — quietly, in the background.",
                bullets: [
                    "Anniversaries with cover photos",
                    "Smart reminders, days ahead",
                    "Memory streaks you'll actually look forward to"
                ]
            )
        }
    }
}

// MARK: - Communication

struct CommunicationStepView: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        OnboardingStepScaffold(viewModel: viewModel) {
            infoLayout(
                icon: "bubble.left.and.bubble.right.fill",
                tint: Color(red: 0.45, green: 0.62, blue: 1.0),
                eyebrow: "Better conversations",
                title: "Less misreading.\nMore being heard.",
                subtitle: "Quizzes you both answer separately, gentle prompts when things feel quiet, and a place to share without the noise of social media.",
                bullets: [
                    "Daily quizzes built for two",
                    "Conversation starters, never cringe",
                    "A private space — no DMs, no feeds"
                ]
            )
        }
    }
}

// MARK: - AI Assistance

struct AIAssistanceStepView: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        OnboardingStepScaffold(viewModel: viewModel) {
            infoLayout(
                icon: "sparkles",
                tint: Color(red: 0.65, green: 0.45, blue: 1.0),
                eyebrow: "Smart Assistance",
                title: "An AI coach that\nactually knows you both.",
                subtitle: "Stuck on what to say? Need a date idea that isn't dinner-and-a-movie? Coupley's coach pulls from your shared history and suggests something thoughtful.",
                bullets: [
                    "Personalized date ideas",
                    "Kind reframes when things get heated",
                    "Help on important moments — birthdays, fights, the in-between"
                ]
            )
        }
    }
}

// MARK: - Daily Connection

struct DailyConnectionStepView: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        OnboardingStepScaffold(viewModel: viewModel) {
            infoLayout(
                icon: "sun.max.fill",
                tint: Color(red: 0.95, green: 0.55, blue: 0.30),
                eyebrow: "Daily Connection",
                title: "A two-minute habit\nyou'll both look forward to.",
                subtitle: "We'll keep it light. A check-in here, a little quiz there, a sweet reminder when you've been quiet. Connection without pressure.",
                bullets: [
                    "Pick your time — morning, evening, both",
                    "Small prompts, never homework",
                    "Skip days guilt-free"
                ]
            )
        }
    }
}

// MARK: - Partner Expectation

struct PartnerExpectationStepView: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        OnboardingStepScaffold(viewModel: viewModel) {
            infoLayout(
                icon: "person.2.fill",
                tint: Brand.accentStart,
                eyebrow: "One more thing",
                title: "Coupley is better\nwhen you're connected.",
                subtitle: "After this, we'll help you invite your partner with a private code. You can also explore solo first — most features are still yours either way.",
                bullets: [
                    "Invite by sharing a 6-character code",
                    "Connect now, or later from Settings",
                    "Disconnect any time — your data stays yours"
                ]
            )
        }
    }
}

// MARK: - Shared layout helper

@ViewBuilder
private func infoLayout(
    icon: String,
    tint: Color,
    eyebrow: String,
    title: String,
    subtitle: String,
    bullets: [String]
) -> some View {
    VStack(alignment: .leading, spacing: 24) {
        HStack {
            Spacer()
            OnboardingHeroIcon(icon: icon, tint: tint, size: 96)
            Spacer()
        }
        .padding(.top, 12)

        StepHeader(
            eyebrow: eyebrow,
            title: title,
            subtitle: subtitle
        )

        VStack(alignment: .leading, spacing: 12) {
            ForEach(bullets, id: \.self) { line in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 22, height: 22)
                    Text(line)
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Brand.surfaceLight)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(Brand.divider, lineWidth: 1)
                )
        )
    }
}
