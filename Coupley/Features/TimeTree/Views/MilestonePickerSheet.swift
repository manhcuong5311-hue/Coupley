//
//  MilestonePickerSheet.swift
//  Coupley
//
//  The grid of preset milestone types shown when adding a new memory.
//  Tapping a preset opens the MemoryEditorSheet with the kind, suggested
//  emotions, and a hint already filled in. Tapping "Custom Moment"
//  opens the editor blank.
//
//  This sheet is small (presentationDetent .medium) — the editor itself
//  is the workspace, this is just the chooser.
//

import SwiftUI

// MARK: - Picker Sheet

struct MilestonePickerSheet: View {

    let onPick: (MemoryKind) -> Void
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.bgGradient.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("What kind of moment?")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(Brand.textPrimary)
                            Text("Pick one of these milestones, or capture something only you two would understand.")
                                .font(.system(size: 13, weight: .regular, design: .rounded))
                                .foregroundStyle(Brand.textSecondary)
                                .lineSpacing(2)
                        }
                        .padding(.horizontal, 4)

                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(MemoryKind.allCases.sorted { $0.pickerOrder < $1.pickerOrder }) { kind in
                                tile(for: kind)
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("New Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Brand.textSecondary)
                }
            }
        }
    }

    // MARK: - Tile

    private func tile(for kind: MemoryKind) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onPick(kind)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                Text(kind.emoji)
                    .font(.system(size: 32))

                VStack(alignment: .leading, spacing: 3) {
                    Text(kind.displayName)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(kind == .custom ? "Anything you'd remember" : "Tap to add")
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(Brand.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Brand.surfaceLight)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(
                                kind == .custom
                                ? AnyShapeStyle(
                                    LinearGradient(
                                        colors: [
                                            Brand.accentStart.opacity(0.55),
                                            Brand.accentEnd.opacity(0.30)
                                        ],
                                        startPoint: .leading, endPoint: .trailing
                                    )
                                  )
                                : AnyShapeStyle(Brand.divider),
                                lineWidth: kind == .custom ? 1.5 : 1
                            )
                    )
            )
        }
        .buttonStyle(BouncyButtonStyle(scale: 0.96))
    }
}
