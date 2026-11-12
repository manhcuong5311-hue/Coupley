//
//  QuizPickerSheet.swift
//  Coupley
//
//  User-initiated quiz selection. Free users access the first half of topic
//  categories; premium unlocks all topics.
//

import SwiftUI

struct QuizPickerSheet: View {

    let coupleId: String
    let viewerId: String
    let partnerId: String
    let onPick: (ChatQuizTemplate) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTopic: QuizTopic? = nil
    @State private var progress: QuizProgress = .empty
    /// Default on: the common case is looking for something new to ask.
    @State private var hideAnswered = true

    private let service: CoupleChatServicing = FirestoreCoupleChatService()

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.bgGradient.ignoresSafeArea()

                List {
                    topicFilterSection

                    ForEach(topicsToShow, id: \.self) { topic in
                        Section {
                            ForEach(templates(in: topic), id: \.questionId) { template in
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
                                Spacer()
                                Text("\(progress.answeredCount(in: topic))/\(progress.total(in: topic))")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(progress.isFullyAnswered(topic)
                                                     ? Brand.accentStart
                                                     : Brand.textTertiary)
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .task {
                progress = (try? await service.fetchQuizProgress(
                    coupleId: coupleId, viewerId: viewerId, partnerId: partnerId
                )) ?? .empty
            }
            .navigationTitle("Pick a Quiz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Brand.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation { hideAnswered.toggle() }
                    } label: {
                        Label(hideAnswered ? "Show answered" : "Hide answered",
                              systemImage: hideAnswered ? "eye.slash" : "eye")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(Brand.accentStart)
                    }
                    .accessibilityLabel(hideAnswered ? "Show answered questions"
                                                     : "Hide answered questions")
                }
            }
        }
    }

    // MARK: - Locked Topic Row

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

            if progress.isAnswered(template.questionId) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(red: 0.25, green: 0.75, blue: 0.50))
                    .accessibilityLabel("Already answered")
            } else if progress.isPending(template.questionId) {
                Image(systemName: "hourglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Brand.textTertiary)
                    .accessibilityLabel("Waiting on an answer")
            } else {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Brand.accentStart)
            }
        }
        .opacity(progress.isAnswered(template.questionId) ? 0.55 : 1)
        .contentShape(Rectangle())
    }

    // MARK: - Data

    private var availableTopics: [QuizTopic] {
        let covered = Set(ChatQuizBank.all.map { $0.topic })
        return QuizTopic.allCases.filter { covered.contains($0) }
    }

    private var topicsToShow: [QuizTopic] {
        if let selectedTopic { return [selectedTopic] }
        // Least-explored first: the reason to open this screen is almost
        // always to find new ground, not to re-read finished topics. Ties
        // keep the enum's own order so the list doesn't reshuffle at random.
        return availableTopics
            .filter { !templates(in: $0).isEmpty }
            .enumerated()
            .sorted { a, b in
                let ca = progress.completion(in: a.element)
                let cb = progress.completion(in: b.element)
                return ca == cb ? a.offset < b.offset : ca < cb
            }
            .map(\.element)
    }

    /// Questions to list for a topic, honouring the hide-answered toggle.
    private func templates(in topic: QuizTopic) -> [ChatQuizTemplate] {
        let all = ChatQuizBank.byTopic(topic)
        guard hideAnswered else { return all }
        return all.filter { !progress.isAnswered($0.questionId) }
    }

    private func pick(_ template: ChatQuizTemplate) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onPick(template)
        dismiss()
    }
}
