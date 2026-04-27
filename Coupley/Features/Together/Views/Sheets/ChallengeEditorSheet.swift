//
//  ChallengeEditorSheet.swift
//  Coupley
//
//  Create-only sheet for couple challenges. We don't expose an "edit
//  challenge" path because changing the cadence or targetCount mid-flight
//  breaks the streak math; users can always delete + recreate, which is
//  the cleaner abstraction.
//

import SwiftUI

struct ChallengeEditorSheet: View {

    @ObservedObject var viewModel: TogetherViewModel

    @EnvironmentObject private var premiumStore: PremiumStore
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var category: ChallengeCategory = .gratitude
    @State private var colorway: TogetherColorway = .dawn
    @State private var cadence: ChallengeCadence = .daily
    @State private var targetCountText: String = "14"
    @State private var startNow: Bool = true
    @State private var startDate: Date = Date()

    @State private var isSubmitting: Bool = false
    @State private var showLimitAlert: Bool = false

    @FocusState private var titleFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    suggestionTray
                        .padding(.top, 6)

                    titleField
                    categoryPicker
                    colorwayPicker
                    cadencePicker
                    targetField
                    startDateField

                    Text("Both partners can check in. Streaks recover one missed day — break two and you'll restart.")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Brand.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    PrimaryButton(
                        title: "Start challenge",
                        isLoading: isSubmitting,
                        isEnabled: isFormValid,
                        action: handleSave
                    )
                    .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Brand.bgGradient.ignoresSafeArea())
            .navigationTitle("New Challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Brand.textSecondary)
                }
            }
            .alert("Free plan includes 1 active challenge",
                   isPresented: $showLimitAlert) {
                Button("Upgrade", role: .none) {
                    dismiss()
                    NotificationCenter.default.post(name: .togetherShowPaywall, object: nil)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Upgrade to Premium to run unlimited challenges together.")
            }
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
                    ForEach(ChallengeSuggestion.library) { suggestion in
                        Button(action: { applySuggestion(suggestion) }) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Text(suggestion.emoji)
                                    Text(suggestion.title)
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .foregroundStyle(Brand.textPrimary)
                                }
                                Text(suggestion.blurb)
                                    .font(.system(size: 11, design: .rounded))
                                    .foregroundStyle(Brand.textSecondary)
                                    .lineLimit(2)
                                    .frame(width: 220, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(14)
                            .frame(width: 240, alignment: .leading)
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

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Title")
            TextField("e.g. 14 Days of Gratitude", text: $title)
                .focused($titleFocused)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Brand.surfaceLight)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(titleFocused
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
                    ForEach(ChallengeCategory.allCases) { cat in
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

    private var cadencePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Cadence")
            HStack(spacing: 0) {
                ForEach(ChallengeCadence.allCases, id: \.self) { c in
                    Button(action: { cadence = c }) {
                        Text(c.label)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(cadence == c ? Brand.textPrimary : Brand.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(
                                Group {
                                    if cadence == c {
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

    private var targetField: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(cadence == .daily ? "Number of days" : "Number of weeks")
            HStack(spacing: 12) {
                ForEach(targetSuggestions, id: \.self) { value in
                    Button(action: {
                        targetCountText = "\(value)"
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }) {
                        Text("\(value)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(targetCountText == "\(value)" ? .white : Brand.textPrimary)
                            .frame(width: 50, height: 50)
                            .background(
                                Circle()
                                    .fill(targetCountText == "\(value)"
                                          ? AnyShapeStyle(Brand.accentGradient)
                                          : AnyShapeStyle(Brand.surfaceLight))
                                    .overlay(
                                        Circle()
                                            .strokeBorder(Brand.divider, lineWidth: 1)
                                    )
                            )
                    }
                    .buttonStyle(BouncyButtonStyle(scale: 0.95))
                }
                Spacer()
            }
        }
    }

    private var targetSuggestions: [Int] {
        cadence == .daily ? [7, 14, 21, 30] : [4, 6, 8, 12]
    }

    private var startDateField: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Start")
            VStack(spacing: 0) {
                Toggle(isOn: $startNow) {
                    Text("Start today")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                }
                .tint(Brand.accentStart)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                if !startNow {
                    Divider().opacity(0.4)
                    DatePicker(
                        "On",
                        selection: $startDate,
                        in: Date()...,
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

    // MARK: - Helpers

    private func applySuggestion(_ suggestion: ChallengeSuggestion) {
        title = suggestion.title
        category = suggestion.category
        colorway = TogetherColorway.suggested(for: suggestion.category)
        cadence = suggestion.cadence
        targetCountText = "\(suggestion.targetCount)"
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private var isFormValid: Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = Int(targetCountText) ?? 0
        return !trimmed.isEmpty && target > 0
    }

    private func handleSave() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let count = Int(targetCountText) ?? 0
        let start = startNow ? Date() : startDate
        let canExceed = premiumStore.hasAccess(to: .togetherChallengesUnlimited)

        Task {
            isSubmitting = true
            defer { isSubmitting = false }

            let success = await viewModel.createChallenge(
                title: trimmed,
                category: category,
                colorway: colorway,
                cadence: cadence,
                targetCount: count,
                startDate: start,
                canExceedFreeLimit: canExceed
            )

            if !success && !canExceed {
                showLimitAlert = true
            } else {
                dismiss()
            }
        }
    }
}
