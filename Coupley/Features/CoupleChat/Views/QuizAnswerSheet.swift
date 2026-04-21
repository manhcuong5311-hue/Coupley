//
//  QuizAnswerSheet.swift
//  Coupley
//
//  Modal sheet presented when the user taps "Answer" on a quiz card in chat.
//  Supports single-select, multi-select, and free-text quizzes.
//

import SwiftUI

struct QuizAnswerSheet: View {

    let quiz: ChatQuiz
    let onSubmit: (ChatQuizAnswer) -> Void
    let onCancel: () -> Void

    @State private var selected: Set<String> = []
    @State private var freeText: String = ""
    @State private var submitting = false

    var body: some View {
        ZStack {
            Brand.bgGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        topicChip
                        Text(quiz.question)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(Brand.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        if !quiz.subtitle.isEmpty {
                            Text(quiz.subtitle)
                                .font(.system(size: 15, design: .rounded))
                                .foregroundStyle(Brand.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if quiz.options.isEmpty {
                            freeTextField
                        } else {
                            optionsList
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }

                submitBar
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button("Cancel") { onCancel() }
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Brand.textSecondary)
            Spacer()
            Text("Quiz")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Brand.textPrimary)
            Spacer()
            // Symmetry spacer
            Text("Cancel").opacity(0)
                .font(.system(size: 15, weight: .medium, design: .rounded))
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private var topicChip: some View {
        HStack(spacing: 6) {
            Text(quiz.topic.emoji)
            Text(quiz.topic.label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Brand.accentStart)
                .textCase(.uppercase)
                .kerning(0.5)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(Brand.accentStart.opacity(0.12))
        )
    }

    // MARK: - Options

    private var optionsList: some View {
        VStack(spacing: 10) {
            ForEach(quiz.options, id: \.self) { option in
                optionRow(option)
            }
            if quiz.allowsMultiple {
                Text("Select one or more")
                    .font(.caption)
                    .foregroundStyle(Brand.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
        }
    }

    private func optionRow(_ option: String) -> some View {
        let isSelected = selected.contains(option)
        return Button {
            toggle(option)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? Brand.accentStart : Brand.divider,
                                      lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle()
                            .fill(Brand.accentStart)
                            .frame(width: 12, height: 12)
                    }
                }
                Text(option)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: Brand.cardCornerRadius)
                    .fill(isSelected
                          ? Brand.accentStart.opacity(0.08)
                          : Brand.surfaceLight)
                    .overlay(
                        RoundedRectangle(cornerRadius: Brand.cardCornerRadius)
                            .strokeBorder(isSelected ? Brand.accentStart.opacity(0.6)
                                                     : Brand.divider,
                                          lineWidth: 1)
                    )
            )
        }
        .buttonStyle(BouncyButtonStyle())
    }

    // MARK: - Free text

    private var freeTextField: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Type your answer…", text: $freeText, axis: .vertical)
                .lineLimit(2...6)
                .font(.system(size: 16, design: .rounded))
                .foregroundStyle(Brand.textPrimary)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: Brand.cardCornerRadius)
                        .fill(Brand.surfaceLight)
                        .overlay(
                            RoundedRectangle(cornerRadius: Brand.cardCornerRadius)
                                .strokeBorder(Brand.divider, lineWidth: 1)
                        )
                )
            Text("Your partner will see this once they've answered too.")
                .font(.caption)
                .foregroundStyle(Brand.textTertiary)
        }
    }

    // MARK: - Submit

    private var submitBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Brand.divider).frame(height: 0.5)
            PrimaryButton(title: submitting ? "Sending…" : "Submit",
                          isLoading: submitting,
                          isEnabled: canSubmit) {
                submit()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .background(Brand.backgroundTop.opacity(0.95))
    }

    private var canSubmit: Bool {
        if quiz.options.isEmpty {
            return !freeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return !selected.isEmpty
    }

    private func toggle(_ option: String) {
        if quiz.allowsMultiple {
            if selected.contains(option) { selected.remove(option) }
            else { selected.insert(option) }
        } else {
            selected = [option]
        }
    }

    private func submit() {
        guard canSubmit else { return }
        submitting = true
        let answer = ChatQuizAnswer(
            options: Array(selected),
            text: freeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : freeText.trimmingCharacters(in: .whitespacesAndNewlines),
            answeredAt: Date()
        )
        onSubmit(answer)
    }
}
