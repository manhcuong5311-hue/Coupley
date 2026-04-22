//
//  QuizPickerSheet.swift
//  Coupley
//
//  User-initiated quiz selection. Free users access the first half of topic
//  categories; premium unlocks all topics.
//

import SwiftUI

struct QuizPickerSheet: View {

    let onPick: (ChatQuizTemplate) -> Void

    @EnvironmentObject private var premiumStore: PremiumStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTopic: QuizTopic? = nil
    @State private var showPaywall = false

    // Free-tier topics (first half of topics by relationship depth)
    private static let freeTopics: Set<QuizTopic> = [
        .loveLanguage, .communication, .conflict, .finance, .intimacy, .lifestyle
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.bgGradient.ignoresSafeArea()

                List {
                    topicFilterSection

                    ForEach(topicsToShow, id: \.self) { topic in
                        let isLocked = !premiumStore.hasAccess(to: .fullQuizAccess)
                                        && !Self.freeTopics.contains(topic)
                        Section {
                            if isLocked {
                                lockedTopicRow(topic)
                            } else {
                                ForEach(ChatQuizBank.byTopic(topic), id: \.questionId) { template in
                                    Button { pick(template) } label: {
                                        row(for: template)
                                    }
                                    .listRowBackground(Brand.surfaceLight)
                                }
                            }
                        } header: {
                            HStack(spacing: 6) {
                                Text(topic.emoji)
                                Text(topic.label)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Brand.textSecondary)
                                    .textCase(.uppercase)
                                    .tracking(0.5)
                                if isLocked {
                                    Spacer()
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(Brand.accentStart)
                                    Text("Premium")
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .foregroundStyle(Brand.accentStart)
                                }
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Pick a Quiz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Brand.textSecondary)
                }
                if !premiumStore.isActive {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showPaywall = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 11))
                                Text("Unlock All")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                            }
                            .foregroundStyle(Color(red: 0.95, green: 0.65, blue: 0.15))
                        }
                    }
                }
            }
            .sheet(isPresented: $showPaywall) {
                NavigationStack {
                    PremiumPaywallView()
                }
                .environmentObject(premiumStore)
                .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Locked Topic Row

    private func lockedTopicRow(_ topic: QuizTopic) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            showPaywall = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Brand.accentStart)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(ChatQuizBank.byTopic(topic).count) questions in \(topic.label)")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                    Text("Upgrade to Premium to unlock")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)
                }
                Spacer()
                Image(systemName: "crown.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(red: 0.95, green: 0.65, blue: 0.15))
            }
            .contentShape(Rectangle())
        }
        .listRowBackground(Brand.accentStart.opacity(0.06))
    }

    // MARK: - Topic filter chips

    private var topicFilterSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip(title: "All", emoji: "✨", isSelected: selectedTopic == nil) {
                        selectedTopic = nil
                    }
                    ForEach(availableTopics, id: \.self) { topic in
                        chip(title: topic.label,
                             emoji: topic.emoji,
                             isSelected: selectedTopic == topic) {
                            selectedTopic = (selectedTopic == topic) ? nil : topic
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowBackground(Color.clear)
        }
    }

    private func chip(title: String, emoji: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(emoji)
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(isSelected ? .white : Brand.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(isSelected
                               ? AnyShapeStyle(Brand.accentGradient)
                               : AnyShapeStyle(Brand.surfaceLight))
            )
            .overlay(
                Capsule().strokeBorder(Brand.divider, lineWidth: isSelected ? 0 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Row

    private func row(for template: ChatQuizTemplate) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(template.question)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                    .multilineTextAlignment(.leading)
                if !template.subtitle.isEmpty {
                    Text(template.subtitle)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)
                        .multilineTextAlignment(.leading)
                } else if !template.options.isEmpty {
                    Text("\(template.options.count) choices")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(Brand.textTertiary)
                } else {
                    Text("Free-text answer")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(Brand.textTertiary)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "paperplane.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Brand.accentStart)
        }
        .contentShape(Rectangle())
    }

    // MARK: - Data

    private var availableTopics: [QuizTopic] {
        let covered = Set(ChatQuizBank.all.map { $0.topic })
        return QuizTopic.allCases.filter { covered.contains($0) }
    }

    private var topicsToShow: [QuizTopic] {
        if let selectedTopic { return [selectedTopic] }
        return availableTopics
    }

    private func pick(_ template: ChatQuizTemplate) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onPick(template)
        dismiss()
    }
}
