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
        FAQItem(
            question: "What is Coupley Premium?",
            answer: "Coupley Premium unlocks the full app experience: custom avatars, anniversary cover photos, all theme styles, the complete quiz library, unlimited date ideas, and up to 50 AI mood suggestions per day."
        ),
        FAQItem(
            question: "Does my partner get Premium too?",
            answer: "Yes! One subscription covers both partners. When you subscribe, your partner automatically inherits Premium access through your shared couple connection."
        ),
        FAQItem(
            question: "What happens if we disconnect?",
            answer: "If you or your partner disconnect, both users return to the free tier. If you reconnect with a new partner, your active subscription will share again with the new connection."
        ),
        FAQItem(
            question: "How do I cancel my subscription?",
            answer: "Go to your iPhone Settings → Apple ID → Subscriptions → Coupley. You can cancel anytime; you'll retain access until the end of the current billing period."
        ),
        FAQItem(
            question: "How do I restore a previous purchase?",
            answer: "Tap 'Upgrade to Premium' in Settings, then use the 'Restore purchases' button at the bottom of the paywall. Your purchase will be restored if it was made with the same Apple ID."
        ),
        FAQItem(
            question: "Is my mood data private?",
            answer: "Your mood check-ins are only visible to your connected partner. We never sell or share your personal data with third parties."
        ),
        FAQItem(
            question: "How does the Thinking of You button work?",
            answer: "Tapping 'Thinking of you' sends your partner an instant nudge. They'll see it appear in their Home screen so they know you're thinking about them right now."
        ),
        FAQItem(
            question: "What do the reaction buttons (Love, Hug, Call me, Coffee) do?",
            answer: "When your partner logs a mood, you can react with a Love, Hug, Call me, or Coffee nudge. Your partner receives it instantly so they feel supported."
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
