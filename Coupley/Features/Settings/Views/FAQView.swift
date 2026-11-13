//
//  FAQView.swift
//  Coupley
//
//  Standalone FAQ screen linked from SettingsView.
//

import SwiftUI

struct FAQView: View {

    /// The expanded item's `id`.
    @State private var expandedFAQ: String? = nil

    private struct FAQItem: Identifiable {
        let question: LocalizedStringResource
        let answer: LocalizedStringResource

        /// The question's catalog key: stable whatever the language.
        var id: String { question.key }
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
            answer: "As many as you like. Goals, challenges and the full Dream Board with photos are free for everyone."
        ),
        FAQItem(
            question: "Can both of us add to the same goal?",
            answer: "Yes — that's the point. Every contribution is tagged with who added it, so the goal card shows the split between you and your partner. The total moves the progress bar regardless of who contributed."
        ),

        // MARK: - Journey

        FAQItem(
            question: "What is Journey?",
            answer: "Journey is your story together. Your tree grows with every day since the start date you set, and the countdowns show your next anniversary and milestone. Memories you add appear on the timeline and as stars around the tree. Future letters between you show up there too: sealed ones hang from the branches until they open, then they bloom."
        ),
        FAQItem(
            question: "What's a Memory Capsule?",
            answer: "A memory sealed until a day you pick, for both of you. Until then the app keeps its note, photo and feelings out of sight; only whoever sealed it can still edit it. It opens at 9:00 that morning in the time zone it was sealed in, so a partner in another time zone sees it open at a different hour, and capsules sealed with an older version of Coupley open at the time of day they were sealed. Want something only your partner can open, locked on our servers rather than just hidden in the app? Write a Future Letter instead."
        ),
        FAQItem(
            question: "What's a Future Letter?",
            answer: "A letter to your partner that stays sealed until a date and time you pick. It's pinned on Home for both of you with a countdown, and it hangs on your tree on Journey until it opens. Only the person it's for can open it, and not a moment early: the lock is kept on our servers, so changing a phone's clock won't open it. You can always reread your own copy, and you can unsend it until it opens. A Memory Capsule is different: it's a shared memory that opens for both of you."
        ),
        FAQItem(
            question: "Where do our anniversary and other special dates go?",
            answer: "Your anniversary countdown comes from the start date you set on Journey, and milestones like 100 days, 1 year, 500 days and 1000 days are celebrated automatically. Other special days, like a first kiss or a trip, are memories: tap + on Journey to add them to your timeline."
        ),

        // MARK: - Chat & Quizzes

        FAQItem(
            question: "What can I do in the Couple Chat?",
            answer: "Send messages, react with emojis, share photos, and start quick quizzes together. Quizzes pull from a curated library; tapping the same option as your partner builds a shared 'couple profile' over time."
        ),
        FAQItem(
            question: "Can I create my own quiz?",
            answer: "Yes — tap the + in the chat and choose Custom Quiz. Custom quizzes and the full library of pre-built topics are free and unlimited."
        ),

        // MARK: - AI features

        FAQItem(
            question: "What does the AI Relationship Coach do?",
            answer: "The Coach reads your recent mood patterns, your partner profile, and your shared activity to suggest small, specific actions tailored to you both. Everyone gets 5 Coach replies a day (each message, rewrite, health check or recovery plan uses one) and 5 AI mood suggestions. The allowance resets at 7:00 Vietnam time."
        ),
        FAQItem(
            question: "Are AI suggestions personal?",
            answer: "They use your couple profile, recent moods, love-language signals and partner preferences. To write a reply, that context and anything you type to the Coach is sent to OpenAI through our servers. It is not shown to other Coupley users or advertisers, and OpenAI states it does not use it to train its models."
        ),

        // MARK: - Free & Remove Ads

        FAQItem(
            question: "Is Coupley free?",
            answer: "Yes. Every feature is free for both of you. Coupley shows ads to keep it that way; AI features have a fair daily limit because each request costs us money."
        ),
        FAQItem(
            question: "What does Remove Ads do?",
            answer: "It's a one-time purchase that turns off all banner and full-screen ads. It's not a subscription, and it covers your partner too while you're connected."
        ),
        FAQItem(
            question: "What happens if we disconnect?",
            answer: "The person who bought Remove Ads stays ad-free on any new pairing. The other partner sees ads again until they pair with someone who bought it."
        ),
        FAQItem(
            question: "I subscribed to Coupley Premium before. What now?",
            answer: "Thank you! Premium no longer exists because everything is free, and you stay ad-free forever. You can cancel it from the “Coupley is free now” card in Settings, or in iPhone Settings → Apple ID → Subscriptions."
        ),
        FAQItem(
            question: "How do I restore a previous purchase?",
            answer: "Open Settings → Remove Ads and tap 'Restore Purchases'. Purchases restore when you use the same Apple ID."
        ),

        // MARK: - Privacy

        FAQItem(
            question: "Is my data private?",
            answer: "Your moods, messages, goals, memories, and photos are visible only to you and your connected partner. We never sell your personal data. AI features send the context they need to OpenAI to write a reply, and nothing else. Ads are served by Google AdMob, which may use your device's advertising identifier only if you allow tracking; your moods, messages and memories are never shared with advertisers."
        ),
    ]

    var body: some View {
        ZStack {
            Brand.bgGradient.ignoresSafeArea(.all)

            List {
                Section {
                    ForEach(faqItems) { item in
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
        let isExpanded = expandedFAQ == item.id
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                expandedFAQ = isExpanded ? nil : item.id
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
