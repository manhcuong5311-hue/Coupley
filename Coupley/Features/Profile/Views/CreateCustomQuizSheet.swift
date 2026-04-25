//
//  CreateCustomQuizSheet.swift
//  Coupley
//
//  Lets the user author their own quiz: a question, a set of answer options
//  they type in, and which option(s) represent their personal answer. Saves
//  into `PartnerProfileDetail.customAnswers`. Gated by `customQuizzes`
//  premium — the profile view presents the paywall before this sheet is
//  shown.
//

import SwiftUI

struct CreateCustomQuizSheet: View {

    let onSave: (_ question: String, _ options: [String], _ selected: [String]) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var question: String = ""
    @State private var options: [String] = ["", ""]
    @State private var selected: Set<String> = []
    @State private var allowsMultiple: Bool = false

    private let maxOptions = 8

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.bgGradient.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        intro
                        questionCard
                        optionsCard
                        modeCard
                        selectionCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Create a quiz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Brand.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .foregroundStyle(canSave ? Brand.accentStart : Brand.textTertiary)
                        .disabled(!canSave)
                }
            }
        }
    }

    // MARK: - Sections

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your own Q&A")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Brand.textPrimary)
            Text("Write a question, add the choices, then pick what's true for you. It'll show up on your profile.")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Brand.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var questionCard: some View {
        card(title: "QUESTION", icon: "questionmark.bubble.fill", tint: Brand.accentStart) {
            TextField("e.g. What do you like about flowers?", text: $question, axis: .vertical)
                .lineLimit(1...4)
                .font(.system(size: 16, design: .rounded))
                .foregroundStyle(Brand.textPrimary)
        }
    }

    private var optionsCard: some View {
        card(title: "CHOICES", icon: "list.bullet", tint: Color(red: 1.0, green: 0.55, blue: 0.25)) {
            VStack(spacing: 10) {
                ForEach(options.indices, id: \.self) { index in
                    optionRow(index: index)
                }

                if options.count < maxOptions {
                    Button {
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
            TextField("Choice \(index + 1)", text: Binding(
                get: { options[index] },
                set: { newValue in
                    let old = options[index]
                    options[index] = newValue
                    // Keep `selected` in sync if the text the user had picked
                    // gets renamed, so selection is never silently lost.
                    if selected.contains(old) {
                        selected.remove(old)
                        let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty { selected.insert(trimmed) }
                    }
                }
            ))
            .font(.system(size: 15, design: .rounded))
            .foregroundStyle(Brand.textPrimary)
            .textFieldStyle(.plain)
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
                    // Collapse to a single selection when switching off multi-pick.
                    if !newValue, selected.count > 1, let keep = selected.first {
                        selected = [keep]
                    }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Allow multiple answers")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                    Text(allowsMultiple ? "Pick any number of options below" : "Pick a single option below")
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
                Text("Add at least one choice above, then select the one(s) that match you.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Brand.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
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

    // MARK: - Save

    private var validOptions: [String] {
        options
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var canSave: Bool {
        !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && validOptions.count >= 2
        && !selected.isEmpty
    }

    private func save() {
        let cleanOptions = validOptions
        let chosen = cleanOptions.filter { selected.contains($0) }
        onSave(question, cleanOptions, chosen)
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

#Preview {
    CreateCustomQuizSheet { _, _, _ in }
}
