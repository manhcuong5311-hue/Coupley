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
    /// Status for the sender's own outgoing message (nil for incoming / non-text).
    let outgoingStatus: ChatViewModel.OutgoingStatus?
    let onAnswerTapped: (String) -> Void

    var body: some View {
        switch message.kind {
        case .text:
            VStack(alignment: isMine ? .trailing : .leading, spacing: 2) {
                TextBubble(text: message.text ?? "", isMine: isMine)
                if isMine, let status = outgoingStatus {
                    OutgoingStatusLabel(status: status)
                        .padding(.trailing, 8)
                }
            }
        case .system:
            SystemLine(text: message.text ?? "")
        case .quiz:
            QuizCardBubble(quiz: quiz, viewerId: viewerId, partnerId: partnerId,
                           onAnswerTapped: onAnswerTapped)
        case .result:
            ResultCardBubble(message: message)
        case .photo:
            PhotoBubble(imageURL: message.imageURL ?? "", isMine: isMine)
        }
    }
}

// MARK: - Outgoing status label

struct OutgoingStatusLabel: View {
    let status: ChatViewModel.OutgoingStatus

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
        }
        .foregroundStyle(status == .seen ? Brand.accentStart : Brand.textTertiary)
        .transition(.opacity)
    }

    private var icon: String {
        switch status {
        case .pending: return "clock"
        case .sent:    return "checkmark"
        case .seen:    return "checkmark.circle.fill"
        }
    }

    private var label: String {
        switch status {
        case .pending: return "Sending…"
        case .sent:    return "Sent"
        case .seen:    return "Seen"
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
                    headerRow(for: quiz)

                    if quiz.isCustom, let note = quiz.customNote, !note.isEmpty {
                        customNoteBlock(note)
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
                        Text(buttonLabel(for: quiz))
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(answerButtonDisabled(quiz) ? Brand.textSecondary : .white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: Brand.buttonCornerRadius)
                                    .fill(answerButtonDisabled(quiz)
                                          ? AnyShapeStyle(Brand.surfaceMid)
                                          : AnyShapeStyle(Brand.accentGradient))
                            )
                    }
                    .disabled(answerButtonDisabled(quiz))
                    .buttonStyle(BouncyButtonStyle())
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: Brand.cardCornerRadius)
                        .fill(Brand.surfaceLight)
                        .overlay(
                            RoundedRectangle(cornerRadius: Brand.cardCornerRadius)
                                .strokeBorder(
                                    quiz.isCustom
                                    ? Brand.accentStart.opacity(0.45)
                                    : Brand.divider,
                                    lineWidth: quiz.isCustom ? 1.5 : 1
                                )
                        )
                        .shadow(
                            color: quiz.isCustom
                                ? Brand.accentStart.opacity(0.18)
                                : .black.opacity(0.05),
                            radius: 12, y: 4
                        )
                )
                Spacer(minLength: 16)
            }
        } else {
            // Fallback: quiz doc not yet loaded
            SystemLine(text: "Loading quiz…")
        }
    }

    /// Top eyebrow row. Custom quizzes get a "Custom from your partner" pill;
    /// curated quizzes show the topic chip as before.
    @ViewBuilder
    private func headerRow(for quiz: ChatQuiz) -> some View {
        if quiz.isCustom {
            HStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text(customAuthorshipLabel(for: quiz))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .textCase(.uppercase)
                    .kerning(0.5)
            }
            .foregroundStyle(Brand.accentStart)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(Brand.accentStart.opacity(0.12))
                    .overlay(Capsule().strokeBorder(Brand.accentStart.opacity(0.30), lineWidth: 0.5))
            )
        } else {
            HStack(spacing: 6) {
                Text(quiz.topic.emoji)
                Text(quiz.topic.label)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.accentStart)
                    .textCase(.uppercase)
                    .kerning(0.5)
            }
        }
    }

    /// "Custom from you" when the viewer is the author, "Custom from your
    /// partner" otherwise. Keeps the model layer free of a name lookup.
    private func customAuthorshipLabel(for quiz: ChatQuiz) -> String {
        if quiz.authorId == viewerId {
            return "Custom from you"
        }
        return "Custom from your partner"
    }

    /// Romantic note panel shown above the question on custom quizzes.
    /// Quote-mark accent + soft accent-tinted card so it reads like a note,
    /// not a metadata field.
    private func customNoteBlock(_ note: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "quote.opening")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Brand.accentStart)
            Text(note)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Brand.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Brand.accentStart.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Brand.accentStart.opacity(0.20), lineWidth: 1)
                )
        )
    }

    /// CTA copy:
    ///   • "View result" when both have answered (always tap-able for replay)
    ///   • "You've answered" when only viewer has answered → disabled
    ///   • "Waiting on you" when viewer is the author and partner hasn't answered → disabled
    ///   • "Answer" otherwise
    private func buttonLabel(for quiz: ChatQuiz) -> String {
        if quiz.bothAnswered(userIds: [viewerId, partnerId]) {
            return "View result"
        }
        if quiz.hasAnswered(viewerId) {
            // Author who pre-answered, partner hasn't replied yet
            if quiz.isCustom && quiz.authorId == viewerId {
                return "Waiting on partner…"
            }
            return "You've answered"
        }
        return "Answer"
    }

    /// Disable the button when the viewer can't take action. Both-answered
    /// state still tappable so they can re-open the result card.
    private func answerButtonDisabled(_ quiz: ChatQuiz) -> Bool {
        let bothDone = quiz.bothAnswered(userIds: [viewerId, partnerId])
        return quiz.hasAnswered(viewerId) && !bothDone
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

// MARK: - Photo bubble

struct PhotoBubble: View {
    let imageURL: String
    let isMine: Bool

    var body: some View {
        HStack {
            if isMine { Spacer(minLength: 48) }
            CachedAsyncImage(url: URL(string: imageURL)) { phase in
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Brand.surfaceLight)
                        .frame(width: 200, height: 200)

                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 200, height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    case .failure:
                        Image(systemName: "photo.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(Brand.textTertiary)
                    case .empty:
                        ProgressView().tint(Brand.accentStart)
                    @unknown default:
                        ProgressView().tint(Brand.accentStart)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Brand.divider, lineWidth: 1)
                )
            }
            if !isMine { Spacer(minLength: 48) }
        }
    }
}
