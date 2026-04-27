//
//  GoalEditorSheet.swift
//  Coupley
//
//  Sheet for creating and editing a goal. Handles both flows in one view by
//  reading from a `Mode` enum — keeps the layout, validation, and persistence
//  paths identical, which is what users expect.
//
//  We intentionally include the suggestion tray on *create* mode only. Once a
//  goal exists, swapping to a different suggestion would feel weird (it's the
//  same goal, just renamed); the user is better served by editing the title.
//

import SwiftUI

// MARK: - Mode

enum GoalEditorMode {
    case create
    case edit(TogetherGoal)
}

// MARK: - Sheet

struct GoalEditorSheet: View {

    @ObservedObject var viewModel: TogetherViewModel
    let mode: GoalEditorMode

    @EnvironmentObject private var premiumStore: PremiumStore
    @Environment(\.dismiss) private var dismiss

    // Form state
    @State private var title: String = ""
    @State private var category: GoalCategory = .savings
    @State private var colorway: TogetherColorway = .sunset
    @State private var trackingMode: GoalTrackingMode = .currency
    @State private var targetText: String = ""
    @State private var hasDueDate: Bool = false
    @State private var dueDate: Date = Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date()
    @State private var note: String = ""

    @State private var isSubmitting: Bool = false
    @State private var showLimitAlert: Bool = false

    @FocusState private var focusedField: Field?

    enum Field { case title, target, note }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {

                    if isCreate {
                        suggestionTray
                            .padding(.top, 6)
                    }

                    titleField
                    categoryPicker
                    colorwayPicker
                    trackingPicker
                    targetField
                    dueDateField
                    noteField

                    if isCreate {
                        Text("Both partners can see this goal and contribute to it. You can edit or delete it anytime.")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(Brand.textTertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .padding(.top, 4)
                    }

                    saveButton

                    if case .edit(let goal) = mode {
                        deleteButton(for: goal)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Brand.bgGradient.ignoresSafeArea())
            .navigationTitle(isCreate ? "New Goal" : "Edit Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Brand.textSecondary)
                }
            }
            .alert("Free plan includes 2 active goals",
                   isPresented: $showLimitAlert) {
                Button("Upgrade", role: .none) {
                    dismiss()
                    NotificationCenter.default.post(name: .togetherShowPaywall, object: nil)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Upgrade to Premium to track unlimited goals together.")
            }
            .onAppear { applyMode() }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: - Sections

    private var suggestionTray: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Start")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .kerning(0.6)
                .textCase(.uppercase)
                .foregroundStyle(Brand.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(GoalSuggestion.library) { suggestion in
                        Button(action: {
                            applySuggestion(suggestion)
                        }) {
                            HStack(spacing: 8) {
                                Text(suggestion.emoji)
                                    .font(.system(size: 18))
                                Text(suggestion.title)
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Brand.textPrimary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                Capsule().fill(Brand.surfaceLight)
                                    .overlay(Capsule().strokeBorder(Brand.divider, lineWidth: 1))
                            )
                        }
                        .buttonStyle(BouncyButtonStyle(scale: 0.96))
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Title")
            TextField("e.g. Japan Trip Fund", text: $title)
                .focused($focusedField, equals: .title)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Brand.surfaceLight)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(focusedField == .title
                                              ? Brand.accentStart.opacity(0.5)
                                              : Brand.divider, lineWidth: 1)
                        )
                )
        }
    }

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Category")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(GoalCategory.allCases) { cat in
                        chip(label: cat.label, icon: cat.icon, selected: category == cat) {
                            category = cat
                            colorway = TogetherColorway.suggested(for: cat)
                            if cat.defaultIsFinancial {
                                trackingMode = .currency
                            }
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
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
                                    .shadow(color: c.primary.opacity(0.4), radius: 6, y: 2)
                                if colorway == c {
                                    Circle()
                                        .stroke(.white, lineWidth: 2)
                                        .frame(width: 36, height: 36)
                                    Circle()
                                        .stroke(c.deep, lineWidth: 2)
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

    private var trackingPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Track as")
            HStack(spacing: 0) {
                ForEach(GoalTrackingMode.allCases, id: \.self) { mode in
                    trackingSegment(for: mode)
                }
            }
            .padding(4)
            .background(trackingPickerBackground)
        }
    }

    /// Pulled out so the type checker doesn't try to infer the whole HStack +
    /// segmented control + background in one expression (it gives up).
    private func trackingSegment(for mode: GoalTrackingMode) -> some View {
        let isSelected = trackingMode == mode
        return Button(action: { trackingMode = mode }) {
            Text(label(for: mode))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(isSelected ? Brand.textPrimary : Brand.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(trackingSegmentHighlight(isSelected: isSelected))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func trackingSegmentHighlight(isSelected: Bool) -> some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Brand.surfaceMid)
                .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
        } else {
            Color.clear
        }
    }

    private var trackingPickerBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Brand.surfaceLight)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Brand.divider, lineWidth: 1)
            )
    }

    private func label(for mode: GoalTrackingMode) -> String {
        switch mode {
        case .currency: return "Money"
        case .count:    return "Steps"
        }
    }

    private var targetField: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(trackingMode == .currency ? "Target amount" : "Target count")
            HStack(spacing: 8) {
                Text(trackingMode == .currency ? "$" : "#")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
                TextField("0", text: $targetText)
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: .target)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Brand.surfaceLight)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(focusedField == .target
                                          ? Brand.accentStart.opacity(0.5)
                                          : Brand.divider, lineWidth: 1)
                    )
            )
        }
    }

    private var dueDateField: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Due date")
            VStack(spacing: 0) {
                Toggle(isOn: $hasDueDate) {
                    Text("Set a target date")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                }
                .tint(Brand.accentStart)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                if hasDueDate {
                    Divider().opacity(0.4)
                    DatePicker(
                        "By",
                        selection: $dueDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.compact)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Brand.surfaceLight)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Brand.divider, lineWidth: 1)
                    )
            )
        }
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Why this matters")
            ZStack(alignment: .topLeading) {
                if note.isEmpty {
                    Text("A line that reminds you why you started.")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(Brand.textTertiary)
                        .padding(.horizontal, 18)
                        .padding(.top, 16)
                }
                TextField("", text: $note, axis: .vertical)
                    .focused($focusedField, equals: .note)
                    .lineLimit(2...5)
                    .font(.system(size: 14, design: .rounded))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            .frame(minHeight: 80)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Brand.surfaceLight)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(focusedField == .note
                                          ? Brand.accentStart.opacity(0.5)
                                          : Brand.divider, lineWidth: 1)
                    )
            )
        }
    }

    private var saveButton: some View {
        PrimaryButton(
            title: isCreate ? "Create goal" : "Save changes",
            isLoading: isSubmitting,
            isEnabled: isFormValid,
            action: handleSave
        )
        .padding(.top, 6)
    }

    private func deleteButton(for goal: TogetherGoal) -> some View {
        Button(role: .destructive) {
            Task {
                await viewModel.deleteGoal(goal)
                dismiss()
            }
        } label: {
            Text("Delete goal")
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
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = Double(targetText) ?? 0
        return !trimmed.isEmpty && target > 0
    }

    private func applyMode() {
        if case .edit(let goal) = mode {
            title        = goal.title
            category     = goal.category
            colorway     = goal.colorway
            trackingMode = goal.trackingMode
            targetText   = String(Int(goal.target))
            hasDueDate   = goal.dueDate != nil
            dueDate      = goal.dueDate ?? Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date()
            note         = goal.note ?? ""
        }
    }

    private func applySuggestion(_ suggestion: GoalSuggestion) {
        title        = suggestion.title
        category     = suggestion.category
        colorway     = TogetherColorway.suggested(for: suggestion.category)
        trackingMode = suggestion.trackingMode
        targetText   = String(Int(suggestion.target))
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
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

    // MARK: - Save

    private func handleSave() {
        let target = Double(targetText) ?? 0
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let due = hasDueDate ? dueDate : nil
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let canExceed = premiumStore.hasAccess(to: .togetherGoalsUnlimited)

        Task {
            isSubmitting = true
            defer { isSubmitting = false }

            switch mode {
            case .create:
                let success = await viewModel.createGoal(
                    title: trimmed,
                    category: category,
                    colorway: colorway,
                    trackingMode: trackingMode,
                    target: target,
                    dueDate: due,
                    note: trimmedNote,
                    canExceedFreeLimit: canExceed
                )
                if !success && !canExceed {
                    showLimitAlert = true
                } else {
                    dismiss()
                }
            case .edit(var goal):
                goal.title = trimmed
                goal.category = category
                goal.colorway = colorway
                goal.trackingMode = trackingMode
                goal.target = target
                goal.dueDate = due
                goal.note = trimmedNote.isEmpty ? nil : trimmedNote
                await viewModel.updateGoal(goal)
                dismiss()
            }
        }
    }
}

// MARK: - Notification name (used to bubble paywall request out of sheets)

extension Notification.Name {
    static let togetherShowPaywall = Notification.Name("coupley.together.showPaywall")
}
