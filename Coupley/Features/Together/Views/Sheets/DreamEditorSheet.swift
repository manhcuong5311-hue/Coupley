//
//  DreamEditorSheet.swift
//  Coupley
//
//  Sheet for creating and editing a dream. Distinct from goals/challenges in
//  vibe — fewer numeric fields, more narrative ones (inspiration, first
//  step). The hero preview at the top is intentional: dreams are visual, so
//  let the user see what their card will look like as they type.
//

import SwiftUI

enum DreamEditorMode {
    case create
    case edit(Dream)
}

struct DreamEditorSheet: View {

    @ObservedObject var viewModel: TogetherViewModel
    let mode: DreamEditorMode

    @EnvironmentObject private var premiumStore: PremiumStore
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var category: DreamCategory = .travel
    @State private var colorway: TogetherColorway = .ocean
    @State private var horizon: DreamHorizon = .nextYear
    @State private var note: String = ""
    @State private var inspiration: String = ""
    @State private var firstStep: String = ""

    @State private var isSubmitting: Bool = false
    @State private var showLimitAlert: Bool = false

    @FocusState private var focusedField: Field?
    enum Field { case title, note, inspiration, firstStep }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    cardPreview
                    if isCreate { suggestionTray }
                    titleField
                    categoryPicker
                    horizonPicker
                    colorwayPicker
                    inspirationField
                    noteField
                    firstStepField
                    Text("Both partners can see and add to the dream board.")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Brand.textTertiary)
                        .multilineTextAlignment(.center)
                    saveButton
                    if case .edit(let dream) = mode {
                        deleteButton(for: dream)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Brand.bgGradient.ignoresSafeArea())
            .navigationTitle(isCreate ? "New Dream" : "Edit Dream")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Brand.textSecondary)
                }
            }
            .alert("Free plan includes 1 dream",
                   isPresented: $showLimitAlert) {
                Button("Upgrade", role: .none) {
                    dismiss()
                    NotificationCenter.default.post(name: .togetherShowPaywall, object: nil)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Upgrade to Premium to keep an unlimited dream board.")
            }
            .onAppear { applyMode() }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: - Card preview

    private var cardPreview: some View {
        ZStack {
            colorway.gradient
                .overlay(
                    LinearGradient(colors: [.clear, .black.opacity(0.40)],
                                   startPoint: .top, endPoint: .bottom)
                )

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(horizon.shortLabel)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .kerning(0.4)
                        .textCase(.uppercase)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.white.opacity(0.20)))
                    Spacer()
                }
                .padding(.top, 14)
                .padding(.horizontal, 14)

                Spacer()

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: category.icon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(category.label)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(.white.opacity(0.85))

                    Text(title.isEmpty ? "Your dream title" : title)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    if !inspiration.isEmpty {
                        Text(inspiration)
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(.white.opacity(0.78))
                            .lineLimit(2)
                            .padding(.top, 1)
                    }
                }
                .padding(14)
            }
        }
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: colorway.deep.opacity(0.30), radius: 14, y: 6)
    }

    // MARK: - Suggestion Tray

    private var suggestionTray: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Start")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .kerning(0.6)
                .textCase(.uppercase)
                .foregroundStyle(Brand.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(DreamSuggestion.library) { suggestion in
                        Button(action: { applySuggestion(suggestion) }) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Text(suggestion.emoji)
                                    Text(suggestion.title)
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .foregroundStyle(Brand.textPrimary)
                                }
                                Text(suggestion.inspiration)
                                    .font(.system(size: 11, design: .rounded))
                                    .foregroundStyle(Brand.textSecondary)
                                    .lineLimit(2)
                                    .frame(width: 200, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(14)
                            .frame(width: 220, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Brand.surfaceLight)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .strokeBorder(Brand.divider, lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(BouncyButtonStyle(scale: 0.97))
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    // MARK: - Fields

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Title")
            TextField("e.g. Japan Together", text: $title)
                .focused($focusedField, equals: .title)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(fieldBackground(focused: focusedField == .title))
        }
    }

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Category")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(DreamCategory.allCases) { cat in
                        chip(label: cat.label, icon: cat.icon, selected: category == cat) {
                            category = cat
                            colorway = TogetherColorway.suggested(for: cat)
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private var horizonPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("When")
            HStack(spacing: 0) {
                ForEach(DreamHorizon.allCases, id: \.self) { h in
                    Button(action: { horizon = h }) {
                        Text(h.label)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(horizon == h ? Brand.textPrimary : Brand.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(
                                Group {
                                    if horizon == h {
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(Brand.surfaceMid)
                                            .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
                                    }
                                }
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Brand.surfaceLight)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Brand.divider, lineWidth: 1)
                    )
            )
        }
    }

    private var colorwayPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Colorway")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(TogetherColorway.allCases) { c in
                        Button(action: { colorway = c }) {
                            ZStack {
                                Circle()
                                    .fill(c.gradient)
                                    .frame(width: 36, height: 36)
                                if colorway == c {
                                    Circle().stroke(.white, lineWidth: 2)
                                        .frame(width: 36, height: 36)
                                    Circle().stroke(c.deep, lineWidth: 2)
                                        .frame(width: 42, height: 42)
                                }
                            }
                        }
                        .buttonStyle(BouncyButtonStyle(scale: 0.92))
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
            }
        }
    }

    private var inspirationField: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Inspiration line")
            TextField("Cherry blossoms with you.", text: $inspiration)
                .focused($focusedField, equals: .inspiration)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(fieldBackground(focused: focusedField == .inspiration))
        }
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("The picture in your head")
            ZStack(alignment: .topLeading) {
                if note.isEmpty {
                    Text("A line, a paragraph, the picture in your head.")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(Brand.textTertiary)
                        .padding(.horizontal, 18)
                        .padding(.top, 16)
                }
                TextField("", text: $note, axis: .vertical)
                    .focused($focusedField, equals: .note)
                    .lineLimit(3...8)
                    .font(.system(size: 14, design: .rounded))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            .frame(minHeight: 100)
            .background(fieldBackground(focused: focusedField == .note))
        }
    }

    private var firstStepField: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("First step")
            TextField("Open the savings goal — we already started.", text: $firstStep)
                .focused($focusedField, equals: .firstStep)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(fieldBackground(focused: focusedField == .firstStep))
        }
    }

    private var saveButton: some View {
        PrimaryButton(
            title: isCreate ? "Add to dream board" : "Save changes",
            isLoading: isSubmitting,
            isEnabled: isFormValid,
            action: handleSave
        )
        .padding(.top, 6)
    }

    private func deleteButton(for dream: Dream) -> some View {
        Button(role: .destructive) {
            Task {
                await viewModel.deleteDream(dream)
                dismiss()
            }
        } label: {
            Text("Delete dream")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 1.0, green: 0.40, blue: 0.40))
        }
        .padding(.top, 6)
    }

    // MARK: - Helpers

    private var isCreate: Bool {
        if case .create = mode { return true }
        return false
    }

    private var isFormValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func applyMode() {
        if case .edit(let dream) = mode {
            title       = dream.title
            category    = dream.category
            colorway    = dream.colorway
            horizon     = dream.horizon
            note        = dream.note ?? ""
            inspiration = dream.inspiration ?? ""
            firstStep   = dream.firstStep ?? ""
        }
    }

    private func applySuggestion(_ suggestion: DreamSuggestion) {
        title       = suggestion.title
        category    = suggestion.category
        colorway    = TogetherColorway.suggested(for: suggestion.category)
        horizon     = suggestion.horizon
        inspiration = suggestion.inspiration
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func fieldBackground(focused: Bool) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Brand.surfaceLight)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(focused ? Brand.accentStart.opacity(0.5) : Brand.divider, lineWidth: 1)
            )
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .kerning(0.6)
            .textCase(.uppercase)
            .foregroundStyle(Brand.textSecondary)
    }

    private func chip(label: String, icon: String, selected: Bool, onTap: @escaping () -> Void) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTap()
        }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(selected ? .white : Brand.textPrimary)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(selected
                          ? AnyShapeStyle(Brand.accentGradient)
                          : AnyShapeStyle(Brand.surfaceLight))
                    .overlay(
                        Capsule().strokeBorder(
                            selected ? Brand.accentStart.opacity(0.3) : Brand.divider,
                            lineWidth: 1
                        )
                    )
            )
        }
        .buttonStyle(BouncyButtonStyle(scale: 0.95))
    }

    private func handleSave() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        // Free dream limit (1) is enforced here as well as in the section UI
        // so a paywall-skipping race can't exceed the cap.
        let isPremium = premiumStore.hasAccess(to: .togetherDreamBoard)

        Task {
            isSubmitting = true
            defer { isSubmitting = false }

            switch mode {
            case .create:
                if !isPremium && viewModel.dreams.count >= 1 {
                    showLimitAlert = true
                    return
                }
                let success = await viewModel.createDream(
                    title: trimmedTitle,
                    category: category,
                    colorway: colorway,
                    horizon: horizon,
                    note: note,
                    inspiration: inspiration,
                    firstStep: firstStep
                )
                if success { dismiss() }
            case .edit(var dream):
                dream.title = trimmedTitle
                dream.category = category
                dream.colorway = colorway
                dream.horizon = horizon
                dream.note = note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note
                dream.inspiration = inspiration.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : inspiration
                dream.firstStep = firstStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : firstStep
                await viewModel.updateDream(dream)
                dismiss()
            }
        }
    }
}
