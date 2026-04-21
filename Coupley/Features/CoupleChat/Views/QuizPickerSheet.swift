//
//  QuizPickerSheet.swift
//  Coupley
//
//  User-initiated quiz selection. Lets either partner pick a specific
//  question from the bundled bank, grouped by topic.
//

import SwiftUI

struct QuizPickerSheet: View {

    let onPick: (ChatQuizTemplate) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTopic: QuizTopic? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.bgGradient.ignoresSafeArea()

                List {
                    topicFilterSection

                    ForEach(topicsToShow, id: \.self) { topic in
                        Section {
                            ForEach(ChatQuizBank.byTopic(topic), id: \.questionId) { template in
                                Button { pick(template) } label: {
                                    row(for: template)
                                }
                                .listRowBackground(Brand.surfaceLight)
                            }
                        } header: {
                            HStack(spacing: 6) {
                                Text(topic.emoji)
                                Text(topic.label)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Brand.textSecondary)
                                    .textCase(.uppercase)
                                    .tracking(0.5)
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
            }
        }
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
        // Only topics that have at least one template.
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
