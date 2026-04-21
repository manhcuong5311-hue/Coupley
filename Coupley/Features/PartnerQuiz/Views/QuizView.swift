//
//  QuizView.swift
//  Coupley
//
//  Created by Sam Manh Cuong on 1/4/26.
//

import SwiftUI

// MARK: - Quiz View

struct QuizView: View {

    @StateObject private var viewModel: QuizViewModel

    init(profileService: ProfileService = LocalProfileService()) {
        _viewModel = StateObject(wrappedValue: QuizViewModel(profileService: profileService))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.bgGradient.ignoresSafeArea()

                Group {
                    switch viewModel.quizState {
                    case .nameEntry:
                        nameEntryView

                    case .inProgress:
                        questionView

                    case .saving:
                        savingView

                    case .completed:
                        completionView
                    }
                }
            }
            .navigationTitle("Partner Quiz")
            .navigationBarTitleDisplayMode(.inline)
            .animation(.easeInOut(duration: 0.3), value: viewModel.quizState)
            .animation(.easeInOut(duration: 0.3), value: viewModel.currentIndex)
        }
    }

    // MARK: - Name Entry

    private var nameEntryView: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 16) {
                Text("💑")
                    .font(.system(size: 64))

                Text("Let's learn about\nyour partner")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(Brand.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Answer fun questions so we can\nhelp you be the best partner ever")
                    .font(.subheadline)
                    .foregroundStyle(Brand.textSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("What's their name?")
                    .font(.headline)
                    .foregroundStyle(Brand.textPrimary)

                TextField("Partner's name", text: $viewModel.partnerName)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .foregroundStyle(Brand.textPrimary)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: Brand.cardCornerRadius)
                            .fill(Brand.surfaceLight)
                            .overlay(
                                RoundedRectangle(cornerRadius: Brand.cardCornerRadius)
                                    .strokeBorder(Brand.divider, lineWidth: 1)
                            )
                    )
                    .submitLabel(.continue)
                    .onSubmit {
                        if viewModel.canStartQuiz {
                            viewModel.startQuiz()
                        }
                    }
            }
            .padding(.horizontal, 20)

            Spacer()

            PrimaryButton(title: "Start Quiz", isEnabled: viewModel.canStartQuiz) {
                viewModel.startQuiz()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Question View

    private var questionView: some View {
        VStack(spacing: 0) {
            // Progress bar
            progressBar
                .padding(.horizontal, 20)
                .padding(.top, 8)

            if let question = viewModel.currentQuestion {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        questionHeader(question)
                        questionInput(question)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 120)
                }
                .scrollDismissesKeyboard(.interactively)
                .id(viewModel.currentIndex)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            }

            Spacer(minLength: 0)

            navigationButtons
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
                .background(
                    LinearGradient(
                        colors: [Brand.backgroundBottom.opacity(0), Brand.backgroundBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 80)
                    .allowsHitTesting(false),
                    alignment: .top
                )
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Brand.surfaceMid)
                        .frame(height: 6)

                    Capsule()
                        .fill(Brand.accentGradient)
                        .frame(
                            width: max(geo.size.width * viewModel.progress, 6),
                            height: 6
                        )
                        .animation(.spring(response: 0.4), value: viewModel.progress)
                }
            }
            .frame(height: 6)

            HStack {
                Text("Question \(viewModel.currentIndex + 1) of \(viewModel.totalQuestions)")
                    .font(.caption)
                    .foregroundStyle(Brand.textSecondary)
                Spacer()
                if let question = viewModel.currentQuestion {
                    Text("\(question.category.emoji) \(question.category.label)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(Brand.textSecondary)
                }
            }
        }
    }

    // MARK: - Question Header

    private func questionHeader(_ question: QuizQuestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(question.question)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(Brand.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if !question.subtitle.isEmpty {
                Text(question.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Brand.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Question Input

    @ViewBuilder
    private func questionInput(_ question: QuizQuestion) -> some View {
        switch question.inputType {
        case .freeText(let placeholder):
            freeTextInput(placeholder: placeholder, allowsMultiple: question.allowsMultiple)

        case .multipleChoice(let options):
            multipleChoiceInput(options: options, allowsMultiple: question.allowsMultiple)
        }
    }

    private func freeTextInput(placeholder: String, allowsMultiple: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(placeholder, text: Binding(
                get: { viewModel.currentAnswer.textValues.joined(separator: ", ") },
                set: { viewModel.updateTextInput($0) }
            ), axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.plain)
                .font(.body)
                .foregroundStyle(Brand.textPrimary)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: Brand.cardCornerRadius)
                        .fill(Brand.surfaceLight)
                        .overlay(
                            RoundedRectangle(cornerRadius: Brand.cardCornerRadius)
                                .strokeBorder(Brand.divider, lineWidth: 1)
                        )
                )

            if allowsMultiple {
                Text("Separate multiple items with commas")
                    .font(.caption)
                    .foregroundStyle(Brand.textTertiary)
            }

            // Show entered items as chips
            if !viewModel.currentAnswer.allValues.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(viewModel.currentAnswer.allValues.filter { !$0.isEmpty }, id: \.self) { item in
                        Text(item)
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Brand.accentStart.opacity(0.12))
                            )
                            .foregroundStyle(Brand.accentStart)
                    }
                }
            }
        }
    }

    private func multipleChoiceInput(options: [String], allowsMultiple: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if allowsMultiple {
                Text("Pick all that apply")
                    .font(.caption)
                    .foregroundStyle(Brand.textTertiary)
            }

            FlowLayout(spacing: 10) {
                ForEach(options, id: \.self) { option in
                    ChoiceChip(
                        label: option,
                        isSelected: viewModel.currentAnswer.selectedOptions.contains(option)
                    ) {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            viewModel.toggleOption(option)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack(spacing: 12) {
            if viewModel.currentIndex > 0 {
                GhostButton(title: "Back") {
                    viewModel.previousQuestion()
                }
            }

            PrimaryButton(
                title: viewModel.isLastQuestion ? "Finish" : "Next",
                isEnabled: viewModel.canProceed
            ) {
                viewModel.nextQuestion()
            }
        }
    }

    // MARK: - Saving View

    private var savingView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .controlSize(.large)
                .tint(Brand.accentStart)
            Text("Building \(viewModel.partnerName)'s profile...")
                .font(.subheadline)
                .foregroundStyle(Brand.textSecondary)
            Spacer()
        }
    }

    // MARK: - Completion View

    private var completionView: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 40)

                VStack(spacing: 16) {
                    Text("🎉")
                        .font(.system(size: 64))

                    Text("You know \(viewModel.partnerName)\npretty well!")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(Brand.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("We'll use this to give you\npersonalized suggestions")
                        .font(.subheadline)
                        .foregroundStyle(Brand.textSecondary)
                        .multilineTextAlignment(.center)
                }

                profileSummary

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Profile Summary

    private var profileSummary: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Here's what we learned")
                .font(.headline)
                .foregroundStyle(Brand.textPrimary)

            let profile = viewModel.profile

            SummaryRow(emoji: "🍜", label: "Food", values: profile.preferences.favoriteFood)
            SummaryRow(emoji: "🧋", label: "Drinks", values: profile.preferences.favoriteDrink)
            SummaryRow(emoji: "🎵", label: "Music", values: profile.preferences.favoriteMusic)
            SummaryRow(emoji: "🎯", label: "Activities", values: profile.preferences.favoriteActivities)

            if !profile.preferences.favoriteColor.isEmpty {
                SummaryRow(emoji: "🎨", label: "Color", values: [profile.preferences.favoriteColor])
            }

            SummaryRow(emoji: "💕", label: "Love Language", values: [profile.personality.loveLanguage.label])
            SummaryRow(emoji: "😮‍💨", label: "Under Stress", values: [profile.personality.stressResponse.label])
            SummaryRow(emoji: "💬", label: "Communication", values: [profile.personality.communicationStyle.label])
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: Brand.cardCornerRadius)
                .fill(Brand.surfaceLight)
                .overlay(
                    RoundedRectangle(cornerRadius: Brand.cardCornerRadius)
                        .strokeBorder(Brand.divider, lineWidth: 1)
                )
        )
    }
}

// MARK: - Summary Row

private struct SummaryRow: View {
    let emoji: String
    let label: String
    let values: [String]

    var body: some View {
        if !values.isEmpty && !values.allSatisfy({ $0.isEmpty }) {
            HStack(alignment: .top, spacing: 10) {
                Text(emoji)
                    .font(.body)

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(Brand.textSecondary)

                    Text(values.filter { !$0.isEmpty }.joined(separator: ", "))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Brand.textPrimary)
                }
            }
        }
    }
}

// MARK: - Choice Chip

private struct ChoiceChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(isSelected ? Brand.accentStart.opacity(0.15) : Brand.surfaceLight)
                )
                .overlay(
                    Capsule()
                        .strokeBorder(
                            isSelected ? Brand.accentStart : Brand.divider,
                            lineWidth: isSelected ? 1.5 : 1
                        )
                )
                .foregroundStyle(isSelected ? Brand.accentStart : Brand.textPrimary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> ArrangementResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }

            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
        }

        return ArrangementResult(
            positions: positions,
            size: CGSize(width: maxX, height: y + rowHeight)
        )
    }

    private struct ArrangementResult {
        let positions: [CGPoint]
        let size: CGSize
    }
}

// MARK: - Previews

#Preview("Name Entry") {
    QuizView()
}
