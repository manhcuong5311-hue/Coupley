//
//  CustomChatQuizBuilderSheet.swift
//  Coupley
//
//  Couple-facing quiz authoring flow. Distinct from the old profile-only
//  CreateCustomQuizSheet (now removed) because this one posts an interactive
//  quiz directly into the chat thread for the partner to answer.
//
//  After posting:
//    • a system line announces the quiz in chat
//    • the quiz card renders with a "Custom from your partner" badge
//    • the optional romantic note appears above the question
//    • the partner taps Answer → existing answer flow → result card
//
//  Premium gating lives in the host (ChatView's QuizHub), not here. We
//  trust the parent to only present this sheet when the user can post.
//

import SwiftUI

struct CustomChatQuizBuilderSheet: View {

    /// Called once the form is valid and the user taps Send. Receives the
    /// raw form values; the parent ChatView model stamps author + posts.
    let onSend: (
        _ title: String?,
        _ question: String,
        _ options: [String],
        _ authorAnswer: [String],
        _ allowsMultiple: Bool,
        _ note: String?
    ) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var question: String = ""
    @State private var options: [String] = ["", ""]
    @State private var selected: Set<String> = []
    @State private var allowsMultiple: Bool = false
    @State private var note: String = ""

    @FocusState private var focusedField: Field?
    enum Field: Hashable { case title, question, option(Int), note }

    private let maxOptions = 6

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.bgGradient.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        intro
                        previewCard
                        titleCard
                        questionCard
                        optionsCard
                        modeCard
                        selectionCard
                        noteCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 36)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Create a Quiz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Brand.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Send") { handleSend() }
                        .fontWeight(.semibold)
                        .foregroundStyle(canSend ? Brand.accentStart : Brand.textTertiary)
                        .disabled(!canSend)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Sections

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Make a quiz, just for them ❤️")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Brand.textPrimary)
            Text("It'll show up in your chat as a beautiful card. They tap, they answer, you both see how aligned you are.")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Brand.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Live preview of how the quiz card will render in chat. Helps the
    /// author see how their note + question land before sending.
    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text("Custom from you")
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

            if !trimmedNote.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "quote.opening")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Brand.accentStart)
                    Text(trimmedNote)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                        .lineSpacing(2)
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Brand.accentStart.opacity(0.08))
                )
            }

            Text(trimmedQuestion.isEmpty ? "Your question will appear here…" : trimmedQuestion)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(trimmedQuestion.isEmpty ? Brand.textTertiary : Brand.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if !trimmedTitle.isEmpty {
                Text(trimmedTitle)
                    .font(.subheadline)
                    .foregroundStyle(Brand.textSecondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Brand.cardCornerRadius)
                .fill(Brand.surfaceLight)
                .overlay(
                    RoundedRectangle(cornerRadius: Brand.cardCornerRadius)
                        .strokeBorder(Brand.accentStart.opacity(0.45), lineWidth: 1.5)
                )
                .shadow(color: Brand.accentStart.opacity(0.15), radius: 14, y: 5)
        )
    }

    private var titleCard: some View {
        card(title: "TITLE (OPTIONAL)", icon: "textformat", tint: Color(red: 0.55, green: 0.74, blue: 0.95)) {
            TextField("e.g. Just for you ❤️", text: $title)
                .focused($focusedField, equals: .title)
                .font(.system(size: 16, design: .rounded))
                .foregroundStyle(Brand.textPrimary)
        }
    }

    private var questionCard: some View {
        card(title: "QUESTION", icon: "questionmark.bubble.fill", tint: Brand.accentStart) {
            TextField("What do you think I love most about you?", text: $question, axis: .vertical)
                .focused($focusedField, equals: .question)
                .lineLimit(1...4)
                .font(.system(size: 16, design: .rounded))
                .foregroundStyle(Brand.textPrimary)
        }
    }

    private var optionsCard: some View {
        card(title: "ANSWER CHOICES", icon: "list.bullet", tint: Color(red: 1.0, green: 0.55, blue: 0.25)) {
            VStack(spacing: 10) {
                ForEach(options.indices, id: \.self) { index in
                    optionRow(index: index)
                }

                if options.count < maxOptions {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(response: 0.3)) {
                            options.append("")
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                            Text("Add option")
                        }
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Brand.accentStart)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func optionRow(index: Int) -> some View {
        HStack(spacing: 10) {
            TextField("Option \(index + 1)", text: Binding(
                get: { options[index] },
                set: { newValue in
                    let oldTrimmed = options[index].trimmingCharacters(in: .whitespaces)
                    options[index] = newValue
                    // Keep `selected` aligned if the user renamed an option
                    // they had already picked.
                    if !oldTrimmed.isEmpty, selected.contains(oldTrimmed) {
                        selected.remove(oldTrimmed)
                        let newTrimmed = newValue.trimmingCharacters(in: .whitespaces)
                        if !newTrimmed.isEmpty { selected.insert(newTrimmed) }
                    }
                }
            ))
            .focused($focusedField, equals: .option(index))
            .font(.system(size: 15, design: .rounded))
            .foregroundStyle(Brand.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Brand.backgroundTop.opacity(0.6))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Brand.divider, lineWidth: 1))
            )

            if options.count > 2 {
                Button {
                    let removed = options.remove(at: index)
                    selected.remove(removed.trimmingCharacters(in: .whitespaces))
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Brand.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var modeCard: some View {
        card(title: "PICK MODE", icon: "checkmark.square.fill", tint: Color(red: 0.40, green: 0.70, blue: 1.0)) {
            Toggle(isOn: Binding(
                get: { allowsMultiple },
                set: { newValue in
                    allowsMultiple = newValue
                    // Collapse to one when switching off multi-select.
                    if !newValue, selected.count > 1, let keep = selected.first {
                        selected = [keep]
                    }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Allow multiple answers")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                    Text(allowsMultiple ? "Partner can pick more than one" : "Partner picks one")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)
                }
            }
            .tint(Brand.accentStart)
        }
    }

    private var selectionCard: some View {
        card(title: "YOUR ANSWER", icon: "heart.fill", tint: Brand.accentStart) {
            let valid = validOptions
            if valid.isEmpty {
                Text("Add at least two choices above, then pick the answer that's true for you. Your partner gets a 💖 if they match.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Brand.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineSpacing(2)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(valid, id: \.self) { option in
                        selectRow(option: option)
                    }
                }
            }
        }
    }

    private func selectRow(option: String) -> some View {
        let isOn = selected.contains(option)
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if allowsMultiple {
                if isOn { selected.remove(option) } else { selected.insert(option) }
            } else {
                selected = isOn ? [] : [option]
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: allowsMultiple
                      ? (isOn ? "checkmark.square.fill" : "square")
                      : (isOn ? "largecircle.fill.circle" : "circle"))
                    .font(.system(size: 20))
                    .foregroundStyle(isOn ? Brand.accentStart : Brand.textTertiary)
                Text(option)
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isOn ? Brand.accentStart.opacity(0.10) : Brand.backgroundTop.opacity(0.6))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(isOn ? Brand.accentStart.opacity(0.35) : Brand.divider,
                                      lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }

    private var noteCard: some View {
        card(title: "ROMANTIC NOTE (OPTIONAL)", icon: "envelope.fill", tint: Color(red: 0.85, green: 0.40, blue: 0.80)) {
            TextField("Just because I was thinking about you…", text: $note, axis: .vertical)
                .focused($focusedField, equals: .note)
                .lineLimit(1...4)
                .font(.system(size: 15, design: .rounded))
                .foregroundStyle(Brand.textPrimary)
        }
    }

    // MARK: - Validation + Send

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedQuestion: String {
        question.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedNote: String {
        note.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var validOptions: [String] {
        options
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var canSend: Bool {
        !trimmedQuestion.isEmpty
        && validOptions.count >= 2
        && !selected.isEmpty
    }

    private func handleSend() {
        guard canSend else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let cleanOptions = validOptions
        let chosen = cleanOptions.filter { selected.contains($0) }
        onSend(
            trimmedTitle.isEmpty ? nil : trimmedTitle,
            trimmedQuestion,
            cleanOptions,
            chosen,
            allowsMultiple,
            trimmedNote.isEmpty ? nil : trimmedNote
        )
        dismiss()
    }

    // MARK: - Card wrapper

    @ViewBuilder
    private func card<Content: View>(
        title: String,
        icon: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
                    .tracking(0.5)
                Spacer()
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Brand.cardCornerRadius)
                .fill(Brand.surfaceLight)
                .overlay(RoundedRectangle(cornerRadius: Brand.cardCornerRadius)
                    .strokeBorder(Brand.divider, lineWidth: 1))
        )
    }
}
