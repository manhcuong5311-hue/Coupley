//
//  FAQView.swift
//  Coupley
//
//  Standalone FAQ screen linked from SettingsView.
//

import SwiftUI

struct FAQView: View {

    @State private var expandedFAQ: String? = nil

    private struct FAQItem {
        let question: String
        let answer: String
    }

    private let faqItems: [FAQItem] = [

        // MARK: - Pairing

        FAQItem(
            question: "How do I connect with my partner?",
            answer: "Open Settings → Partner, then either generate an invite code and share it, or tap 'Use a code' to enter the one your partner sent you. Codes are good for 24 hours and consume on first use."
        ),
        FAQItem(
            question: "Can I switch partners later?",
            answer: "Yes. Disconnect from your current partner in Settings → Partner, then create or accept a new invite code. Each new pairing creates a fresh shared workspace; old shared data stays with the previous couple and isn't visible to the new one."
        ),

        // MARK: - Mood & Nudges

        FAQItem(
            question: "How does the Thinking of You button work?",
            answer: "Tapping 'Thinking of you' sends your partner an instant nudge. They'll see it appear on their Home screen so they know you're on their mind right now."
        ),
        FAQItem(
            question: "What do the reaction buttons (Love, Hug, Call me, Coffee) do?",
            answer: "When your partner logs a mood, you can react with a Love, Hug, Call me, or Coffee nudge. Your partner receives it instantly so they feel supported without you needing to type anything."
        ),
        FAQItem(
            question: "What is the daily streak?",
            answer: "Your streak grows by one for every day both of you check in with a mood. Miss a day and it resets — the longest streak you've ever hit is still saved as your record."
        ),

        // MARK: - Together (goals, challenges, dreams)

        FAQItem(
            question: "What's the difference between a Goal, a Challenge, and a Dream?",
            answer: "Goals are progress trackers (a savings target, a count of activities). Challenges are streak-based commitments with a fixed duration (e.g. 30 days of gratitude). Dreams are aspirational mood-board entries — things you imagine doing one day, with a horizon instead of a deadline."
        ),
        FAQItem(
            question: "Which currency does my goal use?",
            answer: "Each money goal has its own currency, picked when you create it (defaulted from your device locale). Both partners always see the same currency on a shared goal — independent of where either of you is. Tap Edit on a goal to change it later."
        ),
        FAQItem(
            question: "How many goals and challenges can we have?",
            answer: "Free plan: up to 2 active goals, 1 active challenge, 1 dream. Premium removes those limits and unlocks the full Dream Board with photos."
        ),
        FAQItem(
            question: "Can both of us add to the same goal?",
            answer: "Yes — that's the point. Every contribution is tagged with who added it, so the goal card shows the split between you and your partner. The total moves the progress bar regardless of who contributed."
        ),

        // MARK: - Time Tree & Anniversaries

        FAQItem(
            question: "What is the Time Tree?",
            answer: "Time Tree is your shared timeline of memories — the moments worth keeping. Each memory can have a date, a note, and (on Premium) a cover photo. The anchor date marks when you started; everything else lives relative to it."
        ),
        FAQItem(
            question: "What's a Memory Capsule?",
            answer: "A capsule is a memory you write today that locks until a future date you choose. Perfect for letters to your future selves, anniversary surprises, or notes meant to be read on a specific day. Capsules are a Premium feature."
        ),
        FAQItem(
            question: "Can I add anniversaries beyond the main one?",
            answer: "Yes. Add as many anniversaries as you like — first kiss, moving in together, a favorite trip — and each one shows a countdown on your dashboard. Premium lets you add a cover photo to each anniversary."
        ),

        // MARK: - Chat & Quizzes

        FAQItem(
            question: "What can I do in the Couple Chat?",
            answer: "Send messages, react with emojis, share photos, and start quick quizzes together. Quizzes pull from a curated library; tapping the same option as your partner builds a shared 'couple profile' over time."
        ),
        FAQItem(
            question: "Can I create my own quiz?",
            answer: "Yes — tap the + in the chat and choose Custom Quiz. Free users can create one custom quiz per day; Premium is unlimited and unlocks the full library of pre-built topics."
        ),

        // MARK: - AI features

        FAQItem(
            question: "What does the AI Relationship Coach do?",
            answer: "The Coach reads your recent mood patterns, your partner profile, and your shared activity to suggest small, specific actions tailored to you both. Free users get 1 session per day; Premium gets unlimited plus deeper analysis features."
        ),
        FAQItem(
            question: "Are AI suggestions personal?",
            answer: "They use your couple profile, mood history, love-language signals, and partner preferences — never any data from outside your couple. The AI doesn't share your history with anyone, including other Coupley users."
        ),

        // MARK: - Premium

        FAQItem(
            question: "What does Coupley Premium include?",
            answer: "Unlimited shared goals and challenges, the full Dream Board with photos, Memory Capsules, all themes, custom avatar and anniversary photos, the AI Couple Coach, unlimited chat photos and custom quizzes, 50 AI mood suggestions and 25 date ideas per day, and unlimited AI Relationship Coach sessions."
        ),
        FAQItem(
            question: "Does my partner get Premium too?",
            answer: "Yes. One subscription covers both partners. When you subscribe, your partner automatically inherits Premium access through your shared couple connection."
        ),
        FAQItem(
            question: "What happens if we disconnect?",
            answer: "If either of you disconnects, both users return to the free tier on the shared workspace. The original purchaser keeps Premium on any new pairing they create; the partner who didn't pay reverts to free until they pair again with someone who has Premium."
        ),
        FAQItem(
            question: "Why does the price look different from what I expected?",
            answer: "Prices on the paywall are pulled live from the App Store in your local currency (e.g. ₫99,000 in Vietnam, £2.99 in the UK, ¥600 in Japan). Apple sets the per-region pricing; Coupley shows what they'll actually charge."
        ),
        FAQItem(
            question: "How do I cancel my subscription?",
            answer: "Go to your iPhone Settings → Apple ID → Subscriptions → Coupley. You can cancel anytime; you'll retain access until the end of the current billing period."
        ),
        FAQItem(
            question: "How do I restore a previous purchase?",
            answer: "Tap 'Upgrade to Premium' in Settings, then 'Restore purchases' at the bottom of the paywall. Your purchase will restore if it was made with the same Apple ID."
        ),

        // MARK: - Privacy

        FAQItem(
            question: "Is my data private?",
            answer: "Your moods, messages, goals, memories, and photos are visible only to you and your connected partner. We never sell or share your personal data with third parties, and AI suggestions are generated without revealing your data outside your couple."
        ),
    ]

    var body: some View {
        ZStack {
            Brand.bgGradient.ignoresSafeArea(.all)

            List {
                Section {
                    ForEach(faqItems, id: \.question) { item in
                        faqRow(item)
                    }
                } header: {
                    Text("Tap a question to expand the answer")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Brand.textTertiary)
                        .textCase(nil)
                }
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 12).fill(Brand.surfaceLight)
                )
            }
            .scrollContentBackground(.hidden)
            .listRowSpacing(8)
        }
        .navigationTitle("FAQ")
        .navigationBarTitleDisplayMode(.large)
    }

    private func faqRow(_ item: FAQItem) -> some View {
        let isExpanded = expandedFAQ == item.question
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                expandedFAQ = isExpanded ? nil : item.question
            }
        } label: {
            VStack(alignment: .leading, spacing: isExpanded ? 10 : 0) {
                HStack(spacing: 10) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Brand.accentStart)
                        .frame(width: 22)
                    Text(item.question)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Brand.textTertiary)
                }
                if isExpanded {
                    Text(item.answer)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 32)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
