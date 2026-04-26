//
//  AnchorSetupSheet.swift
//  Coupley
//
//  First-run sheet that asks the couple "When did your story begin?"
//  Setting the anchor unlocks the tree, all milestones, days-together
//  counter, and yearly anniversary computation.
//
//  Surfaces an explainer paragraph at the top so users understand why
//  we're asking, plus reassurance that they can change it later.
//

import SwiftUI

// MARK: - Setup Sheet

struct AnchorSetupSheet: View {

    @ObservedObject var viewModel: TimeTreeViewModel
    /// Existing anchor (if any) — if non-nil, this sheet operates as an
    /// "edit" rather than an initial setup.
    let existing: RelationshipAnchor?
    /// User's display name, used to attribute the anchor on the partner
    /// device. Optional — falls back to "your partner."
    let displayName: String?

    @Environment(\.dismiss) private var dismiss

    @State private var startDate: Date

    init(viewModel: TimeTreeViewModel, existing: RelationshipAnchor? = nil, displayName: String? = nil) {
        self.viewModel = viewModel
        self.existing = existing
        self.displayName = displayName
        _startDate = State(initialValue: existing?.startDate ?? Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date())
    }

    private var isEditing: Bool { existing != nil }

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.bgGradient.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 22) {
                        Color.clear.frame(height: 8)

                        heroBlock

                        datePickerCard

                        if let existing {
                            attributionFootnote(existing)
                        }

                        Color.clear.frame(height: 80)
                    }
                    .padding(.horizontal, 20)
                }

                VStack {
                    Spacer()
                    PrimaryButton(
                        title: isEditing ? "Update Anchor" : "Plant Tree",
                        isLoading: viewModel.isSavingAnchor,
                        isEnabled: !viewModel.isSavingAnchor,
                        action: save
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
            }
            .navigationTitle(isEditing ? "Anchor Date" : "Begin Your Tree")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Brand.textSecondary)
                }
            }
        }
    }

    // MARK: - Hero block

    private var heroBlock: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Brand.accentStart.opacity(0.30), Brand.accentEnd.opacity(0.18)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 84, height: 84)
                    .shadow(color: Brand.accentStart.opacity(0.30), radius: 18, y: 8)

                Image(systemName: "leaf.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Brand.accentStart)
            }

            VStack(spacing: 8) {
                Text(isEditing ? "When did it really begin?" : "Plant your Time Tree")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Pick the day your story began.\nYour tree will grow from this date — \nshared with your partner instantly.")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    // MARK: - Date picker card

    private var datePickerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.system(size: 13, weight: .semibold))
                Text("Start Date")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(Brand.textSecondary)
            .padding(.horizontal, 4)

            DatePicker(
                "Start Date",
                selection: $startDate,
                in: ...Date(),
                displayedComponents: [.date]
            )
            .datePickerStyle(.graphical)
            .tint(Brand.accentStart)
            .labelsHidden()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Brand.surfaceLight)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Brand.divider, lineWidth: 1)
                )
        )
    }

    // MARK: - Attribution footnote

    private func attributionFootnote(_ anchor: RelationshipAnchor) -> some View {
        let setBy = anchor.setByName ?? "your partner"
        return HStack(spacing: 8) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Brand.textTertiary)
            Text("Originally set by \(setBy) on \(formatDate(anchor.setAt))")
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundStyle(Brand.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Save

    private func save() {
        Task {
            await viewModel.setAnchor(startDate: startDate, displayName: displayName)
            dismiss()
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }
}
