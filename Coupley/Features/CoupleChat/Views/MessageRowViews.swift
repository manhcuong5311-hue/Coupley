//
//  MessageRowViews.swift
//  Coupley
//
//  Bubbles + cards used inside the chat feed. One entry point (`MessageRow`)
//  dispatches on `ChatMessageKind`.
//

import SwiftUI

struct MessageRow: View {

    let message: ChatMessage
    let isMine: Bool
    let quiz: ChatQuiz?
    let viewerId: String
    let partnerId: String
    let onAnswerTapped: (String) -> Void

    var body: some View {
        switch message.kind {
        case .text:
            TextBubble(text: message.text ?? "", isMine: isMine)
        case .system:
            SystemLine(text: message.text ?? "")
        case .quiz:
            QuizCardBubble(quiz: quiz, viewerId: viewerId, partnerId: partnerId,
                           onAnswerTapped: onAnswerTapped)
        case .result:
            ResultCardBubble(message: message)
        }
    }
}

// MARK: - Text bubble

struct TextBubble: View {
    let text: String
    let isMine: Bool

    var body: some View {
        HStack {
            if isMine { Spacer(minLength: 48) }
            Text(text)
                .font(.system(size: 16, design: .rounded))
                .foregroundStyle(isMine ? Color.white : Brand.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Group {
                        if isMine {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Brand.accentGradient)
                        } else {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Brand.surfaceLight)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .strokeBorder(Brand.divider, lineWidth: 1)
                                )
                        }
                    }
                )
            if !isMine { Spacer(minLength: 48) }
        }
    }
}

// MARK: - System line

struct SystemLine: View {
    let text: String
    var body: some View {
        HStack {
            Spacer()
            Text(text)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Brand.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(Brand.surfaceLight)
                )
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Quiz card

struct QuizCardBubble: View {
    let quiz: ChatQuiz?
    let viewerId: String
    let partnerId: String
    let onAnswerTapped: (String) -> Void

    var body: some View {
        if let quiz {
            HStack {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        Text(quiz.topic.emoji)
                        Text(quiz.topic.label)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Brand.accentStart)
                            .textCase(.uppercase)
                            .kerning(0.5)
                    }

                    Text(quiz.question)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !quiz.subtitle.isEmpty {
                        Text(quiz.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(Brand.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    statusLine

                    Button {
                        onAnswerTapped(quiz.id)
                    } label: {
                        Text(hasAnswered ? "You've answered" : "Answer")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(hasAnswered ? Brand.textSecondary : .white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: Brand.buttonCornerRadius)
                                    .fill(hasAnswered
                                          ? AnyShapeStyle(Brand.surfaceMid)
                                          : AnyShapeStyle(Brand.accentGradient))
                            )
                    }
                    .disabled(hasAnswered)
                    .buttonStyle(BouncyButtonStyle())
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: Brand.cardCornerRadius)
                        .fill(Brand.surfaceLight)
                        .overlay(
                            RoundedRectangle(cornerRadius: Brand.cardCornerRadius)
                                .strokeBorder(Brand.divider, lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.05), radius: 12, y: 4)
                )
                Spacer(minLength: 16)
            }
        } else {
            // Fallback: quiz doc not yet loaded
            SystemLine(text: "Loading quiz…")
        }
    }

    private var hasAnswered: Bool {
        quiz?.hasAnswered(viewerId) ?? false
    }

    @ViewBuilder
    private var statusLine: some View {
        if let quiz {
            let mine    = quiz.hasAnswered(viewerId)
            let partner = quiz.hasAnswered(partnerId)
            HStack(spacing: 6) {
                Circle().fill(mine ? Brand.accentStart : Brand.textTertiary).frame(width: 6, height: 6)
                Text(mine ? "You answered" : "Your turn")
                    .font(.caption)
                    .foregroundStyle(Brand.textSecondary)

                Text("•").foregroundStyle(Brand.textTertiary)

                Circle().fill(partner ? Brand.accentStart : Brand.textTertiary).frame(width: 6, height: 6)
                Text(partner ? "Partner answered" : "Waiting on partner")
                    .font(.caption)
                    .foregroundStyle(Brand.textSecondary)
            }
        }
    }
}

// MARK: - Result card

struct ResultCardBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            Spacer(minLength: 16)
            VStack(spacing: 10) {
                Text(message.resultEmoji ?? "✨")
                    .font(.system(size: 34))

                Text(message.resultSummary ?? "")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if let match = message.resultMatch {
                    Text(match ? "In sync" : "Worth discussing")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(match ? Brand.accentStart : Brand.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(match
                                           ? Brand.accentStart.opacity(0.12)
                                           : Brand.surfaceMid)
                        )
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Brand.cardCornerRadius)
                    .fill(Brand.surfaceLight)
                    .overlay(
                        RoundedRectangle(cornerRadius: Brand.cardCornerRadius)
                            .strokeBorder(Brand.accentStart.opacity(0.25), lineWidth: 1)
                    )
            )
            Spacer(minLength: 16)
        }
    }
}
