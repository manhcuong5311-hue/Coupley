//
//  QuestionOfTheDayCard.swift
//  Coupley
//
//  The first thing on Home. Four states, each with exactly one thing to do:
//
//    awaitingMe       → the question, and a button to answer it
//    awaitingPartner  → what your answer says about you, while you wait
//    complete         → whether you matched, and what you each picked
//    loading / hidden → nothing (the card removes itself)
//
//  The "awaitingPartner" state is the one that matters: it has to feel like
//  a reward rather than a waiting room, otherwise answering first is a
//  punishment. It shows the hint attached to the option you picked — a small
//  insight about yourself you didn't have a second ago.
//

import SwiftUI

struct QuestionOfTheDayCard: View {

    @ObservedObject var viewModel: QuestionOfTheDayViewModel
    let partnerName: String
    var tier: SurfaceTier = .card

    private var isHero: Bool { tier == .hero }

    var body: some View {
        Group {
            switch viewModel.state {
            case .hidden:
                EmptyView()
            case .loading:
                loadingCard
            case .awaitingMe(let quiz):
                card(accent: Brand.accentStart) { awaitingMeContent(quiz) }
            case .awaitingPartner(let quiz):
                card(accent: waitingAccent) { awaitingPartnerContent(quiz) }
            case .complete(let quiz):
                card(accent: completeAccent) { completeContent(quiz) }
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.85), value: viewModel.state)
        .sheet(item: $viewModel.quizBeingAnswered) { quiz in
            QuizAnswerSheet(
                quiz: quiz,
                partnerName: partnerName,
                onSubmit: { viewModel.submit(answer: $0, for: quiz) },
                onCancel: { viewModel.quizBeingAnswered = nil }
            )
            .presentationDetents([.medium, .large])
            .presentationBackground(Brand.backgroundTop)
        }
    }

    // MARK: - Palette

    private var waitingAccent: Color { Color(red: 0.52, green: 0.44, blue: 0.95) }
    private var completeAccent: Color { Color(red: 0.25, green: 0.75, blue: 0.50) }

    // MARK: - Container

    private func card<Content: View>(
        accent: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            header(accent: accent)
            content()
        }
        .modifier(TierContainer(tier: tier, accent: accent))
    }

    private func header(accent: Color) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                // Was a 13pt uppercase tracked eyebrow, identical to the five
                // others on this screen. Only the dateline keeps small caps.
                Text("Question of the day")
                    .font(BrandType.label)
                    .foregroundStyle(Brand.textSecondary)

                if !isHero {
                    Text(headerSubtitle)
                        .font(BrandType.meta)
                        .foregroundStyle(Brand.textTertiary)
                }
            }

            Spacer()

            if case .complete = viewModel.state {
                statusBadge("Both answered",
                            icon: "checkmark.circle.fill",
                            tint: completeAccent)
            } else if case .awaitingPartner = viewModel.state {
                statusBadge("Waiting",
                            icon: "hourglass",
                            tint: waitingAccent)
            } else if let quiz = currentQuiz {
                topicBadge(quiz.topic, tint: accent)
            }
        }
    }

    private var headerSubtitle: String {
        switch viewModel.state {
        case .awaitingMe:      return "Answer separately, compare after"
        case .awaitingPartner: return "\(partnerName) hasn't answered yet"
        case .complete:        return "Here's how you two lined up"
        case .loading, .hidden: return " "
        }
    }

    private var currentQuiz: ChatQuiz? {
        switch viewModel.state {
        case .awaitingMe(let q), .awaitingPartner(let q), .complete(let q): return q
        case .loading, .hidden: return nil
        }
    }

    private func topicBadge(_ topic: QuizTopic, tint: Color) -> some View {
        HStack(spacing: 5) {
            Text(topic.emoji).font(.system(size: 10))
            Text(topic.label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Brand.textTertiary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Brand.backgroundTop)
                .overlay(Capsule().strokeBorder(Brand.divider, lineWidth: 1))
        )
    }

    private func statusBadge(_ text: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(tint.opacity(0.12)))
    }

    // MARK: - State: awaiting me

    private func awaitingMeContent(_ quiz: ChatQuiz) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(quiz.question)
                .font(isHero ? BrandType.hero : BrandType.title)
                .foregroundStyle(Brand.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if quiz.hasAnswered(partnerIdPlaceholder) {
                Text("\(partnerName) already answered. Yours stays hidden until you do.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                viewModel.beginAnswering()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "pencil.and.scribble")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Answer")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: Brand.buttonCornerRadius)
                        .fill(Brand.accentGradient)
                )
            }
            .buttonStyle(BouncyButtonStyle())
        }
    }

    /// The card only knows the partner's answers through the quiz document,
    /// and the view model owns identity. This resolves to the partner's id by
    /// elimination: any answerer who isn't me.
    private var partnerIdPlaceholder: String {
        currentQuiz?.answers.keys.first { $0 != viewModel.myUserId } ?? ""
    }

    // MARK: - State: awaiting partner

    private func awaitingPartnerContent(_ quiz: ChatQuiz) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(quiz.question)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Brand.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let picked = quiz.answer(for: viewModel.myUserId)?.options.first {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(waitingAccent)
                    Text("You said: \(picked)")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let hint = viewModel.myAnswerHint {
                Text(hint)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(waitingAccent.opacity(0.10))
                    )
            }

            Text("\(partnerName)'s answer unlocks when they've picked theirs.")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(Brand.textTertiary)
        }
    }

    // MARK: - State: complete

    private func completeContent(_ quiz: ChatQuiz) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(quiz.question)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Brand.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let result = quiz.result {
                HStack(spacing: 8) {
                    Text(result.emoji).font(.system(size: 20))
                    Text(result.summary)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(completeAccent.opacity(0.10))
                )
            }

            VStack(spacing: 8) {
                answerRow(
                    label: "You",
                    options: quiz.answer(for: viewModel.myUserId)?.options ?? []
                )
                answerRow(
                    label: partnerName,
                    options: quiz.answer(for: viewModel.partnerUserId)?.options ?? []
                )
            }

            // The point of answering blind: you now learn something about
            // them, not just which word they tapped.
            //
            // The card is titled with the *option*, never with a name. The
            // bank's hints are written in the second person to whoever picked
            // ("You thrive on being told… don't make them guess"), so framing
            // one as "what this says about Linh" inverts both pronouns. Under
            // the option it reads as the generic you, which is what it is.
            GuessOutcomeRow(quiz: quiz,
                            viewerId: viewModel.myUserId,
                            partnerId: viewModel.partnerUserId)

            if let option = quiz.answer(for: viewModel.partnerUserId)?.options.first,
               let insight = viewModel.partnerAnswerInsight {
                insightCard(option: option, body: insight)
            }
        }
    }

    private func insightCard(option: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text("What \u{201C}\(option)\u{201D} means")
                    .font(BrandType.meta)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(completeAccent)

            Text(body)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Brand.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(completeAccent.opacity(0.10))
        )
    }

    private func answerRow(label: String, options: [String]) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Brand.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                // Fixed width keeps the two rows aligned; the shrink keeps a
                // two-word name from breaking mid-word inside it.
                .frame(width: 64, alignment: .leading)

            Text(options.isEmpty ? "—" : options.joined(separator: ", "))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Brand.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Loading

    private var loadingCard: some View {
        HStack(spacing: 12) {
            ProgressView().tint(Brand.accentStart)
            Text("Loading today's question…")
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(Brand.textSecondary)
            Spacer()
        }
        .modifier(TierContainer(tier: tier))
    }
}
