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
    let partnerName: String
    let onSubmit: (ChatQuizAnswer) -> Void
    let onCancel: () -> Void

    /// Answering happens in two passes: your own answer, then a prediction of
    /// theirs. The prediction is what turns a survey into a game — and it is
    /// skippable, so nobody is forced to guess to take part.
    private enum Phase { case mine, guessing }

    @State private var phase: Phase = .mine
    @State private var selected: Set<String> = []
    @State private var guessed: Set<String> = []
    @State private var freeText: String = ""
    @State private var submitting = false
    @State private var lastToggled: String?

    /// Free text cannot be scored against a prediction.
    private var supportsGuessing: Bool { !quiz.options.isEmpty }

    private var activeSelection: Set<String> {
        phase == .mine ? selected : guessed
    }

    private var template: ChatQuizTemplate? { ChatQuizBank.byId(quiz.questionId) }

    var body: some View {
        ZStack {
            Brand.bgGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        topicChip

                        if phase == .guessing {
                            Text("What will \(partnerName) pick?")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(Brand.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(quiz.question)
                                .font(.system(size: 14, design: .rounded))
                                .foregroundStyle(Brand.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
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
                        }

                        if quiz.options.isEmpty {
                            freeTextField
                        } else {
                            optionsList

                            // Hint card — animates in when an option is picked.
                            // Suppressed while guessing: it describes the
                            // person who picked, and here that is not you.
                            if phase == .mine, let hint = currentHint {
                                hintCard(hint)
                                    .transition(.scale(scale: 0.96, anchor: .top)
                                        .combined(with: .opacity))
                            }
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
            Button(phase == .guessing ? "Back" : "Cancel") {
                if phase == .guessing {
                    withAnimation { phase = .mine }
                } else {
                    onCancel()
                }
            }
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Brand.textSecondary)
            Spacer()
            Text("Quiz")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Brand.textPrimary)
            Spacer()
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
        .background(Capsule().fill(Brand.accentStart.opacity(0.12)))
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
                    .padding(.top, 2)
            }
        }
    }

    private func optionRow(_ option: String) -> some View {
        let isSelected = activeSelection.contains(option)
        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                toggle(option)
            }
        } label: {
            HStack(spacing: 14) {
                // Checkbox / radio
                ZStack {
                    if quiz.allowsMultiple {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(
                                isSelected ? Brand.accentStart : Brand.divider,
                                lineWidth: 1.5
                            )
                            .frame(width: 22, height: 22)
                        if isSelected {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Brand.accentStart)
                                .frame(width: 14, height: 14)
                        }
                    } else {
                        Circle()
                            .strokeBorder(
                                isSelected ? Brand.accentStart : Brand.divider,
                                lineWidth: 1.5
                            )
                            .frame(width: 22, height: 22)
                        if isSelected {
                            Circle()
                                .fill(Brand.accentStart)
                                .frame(width: 12, height: 12)
                        }
                    }
                }
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)

                Text(option)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(isSelected ? Brand.textPrimary : Brand.textPrimary.opacity(0.85))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                // Checkmark for selected
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Brand.accentStart)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: Brand.cardCornerRadius)
                    .fill(isSelected
                          ? Brand.accentStart.opacity(0.08)
                          : Brand.surfaceLight)
                    .overlay(
                        RoundedRectangle(cornerRadius: Brand.cardCornerRadius)
                            .strokeBorder(
                                isSelected ? Brand.accentStart.opacity(0.6) : Brand.divider,
                                lineWidth: isSelected ? 1.5 : 1
                            )
                    )
            )
        }
        .buttonStyle(BouncyButtonStyle())
    }

    // MARK: - Hint Card

    private var currentHint: String? {
        guard let tpl = template, !tpl.optionHints.isEmpty else { return nil }
        // For single select: hint of the one selected option
        if !quiz.allowsMultiple, let pick = selected.first {
            return tpl.optionHints[pick]
        }
        // For multi-select: hint of last toggled option
        if let last = lastToggled, selected.contains(last) {
            return tpl.optionHints[last]
        }
        return nil
    }

    private func hintCard(_ hint: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Brand.accentStart)
                .padding(.top, 1)

            Text(hint)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(Brand.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Brand.accentStart.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Brand.accentStart.opacity(0.20), lineWidth: 1)
                )
        )
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

            PrimaryButton(title: primaryTitle,
                          isLoading: submitting,
                          isEnabled: canAdvance) {
                advance()
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)

            if phase == .guessing {
                Button("Skip the guess") { submit() }
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
                    .padding(.top, 8)
            }

            Color.clear.frame(height: 14)
        }
        .background(Brand.backgroundTop.opacity(0.95))
    }

    private var primaryTitle: String {
        if submitting { return "Sending…" }
        if phase == .mine && supportsGuessing { return "Next — guess theirs" }
        return "Submit"
    }

    /// Gate for the primary button in whichever phase is showing.
    private var canAdvance: Bool {
        if submitting { return false }
        if quiz.options.isEmpty {
            return !freeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return phase == .mine ? !selected.isEmpty : !guessed.isEmpty
    }

    private func advance() {
        guard canAdvance else { return }
        if phase == .mine && supportsGuessing {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                phase = .guessing
                lastToggled = nil
            }
        } else {
            submit()
        }
    }

    private func toggle(_ option: String) {
        lastToggled = option
        if phase == .mine {
            selected = apply(option, to: selected)
        } else {
            guessed = apply(option, to: guessed)
        }
    }

    private func apply(_ option: String, to set: Set<String>) -> Set<String> {
        guard quiz.allowsMultiple else { return [option] }
        var next = set
        if next.contains(option) { next.remove(option) } else { next.insert(option) }
        return next
    }

    private func submit() {
        guard !submitting else { return }
        submitting = true
        let answer = ChatQuizAnswer(
            options: Array(selected),
            text: freeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : freeText.trimmingCharacters(in: .whitespacesAndNewlines),
            answeredAt: Date(),
            guess: guessed.isEmpty ? nil : Array(guessed)
        )
        onSubmit(answer)
    }
}
