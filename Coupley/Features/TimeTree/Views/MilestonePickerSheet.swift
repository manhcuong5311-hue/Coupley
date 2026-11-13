//
//  MilestonePickerSheet.swift
//  Coupley
//
//  The chooser behind Journey's + button: the preset milestone kinds, a
//  custom moment and, when the presenter can write letters, a future letter
//  for the partner. Picking a kind hands it back and closes; the presenter
//  opens MemoryEditorSheet once this sheet is gone.
//
//  Kinds already in the timeline say when they were added, but stay
//  tappable: a couple can have more than one first trip.
//

import Foundation
import SwiftUI
import UIKit

// MARK: - Picker Sheet

struct MilestonePickerSheet: View {

    /// When each kind already in the timeline was added, keyed by kind.
    let loggedDates: [MemoryKind: Date]
    let partnerName: String
    let onPick: (MemoryKind) -> Void
    /// Offered as the first row when non-nil.
    let onWriteLetter: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(loggedDates: [MemoryKind: Date],
         partnerName: String,
         onPick: @escaping (MemoryKind) -> Void,
         onWriteLetter: (() -> Void)? = nil) {
        self.loggedDates = loggedDates
        self.partnerName = partnerName
        self.onPick = onPick
        self.onWriteLetter = onWriteLetter
    }

    /// Two columns, or one once the text is too large to share a row.
    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: 12), GridItem(.flexible())]
    }

    private var kinds: [MemoryKind] {
        MemoryKind.allCases.sorted { $0.pickerOrder < $1.pickerOrder }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("What kind of moment?")
                            .font(JourneyFont.title)
                            .foregroundStyle(Brand.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        Text("Pick one of these milestones, or capture something only you two would understand.")
                            .font(JourneyFont.body)
                            .foregroundStyle(Brand.textSecondary)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 4)

                    if let onWriteLetter {
                        letterRow(onWriteLetter)
                    }

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(kinds) { kind in
                            tile(for: kind)
                        }
                    }
                }
                .padding(Brand.Space.gutter)
            }
            .background(Brand.bgGradient.ignoresSafeArea())
            .navigationTitle("New Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Close", comment: "Toolbar button: close this sheet")
                    }
                    .foregroundStyle(Brand.textSecondary)
                }
            }
        }
    }

    // MARK: - Letter row

    private func letterRow(_ onWriteLetter: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onWriteLetter()
            dismiss()
        } label: {
            BrandCard(tier: .chip) {
                HStack(spacing: 12) {
                    Image(systemName: "envelope.fill")
                        .font(JourneyFont.title)
                        .foregroundStyle(FutureLetterStyle.accent)
                        .frame(width: 28)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("A future letter")
                            .font(JourneyFont.label)
                            .foregroundStyle(Brand.textPrimary)
                        Text("Sealed for \(partnerName) until a moment you pick")
                            .font(JourneyFont.meta)
                            .foregroundStyle(Brand.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .multilineTextAlignment(.leading)

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(JourneyFont.meta)
                        .foregroundStyle(Brand.textTertiary)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(BouncyButtonStyle(scale: 0.98))
    }

    // MARK: - Tile

    private func tile(for kind: MemoryKind) -> some View {
        let added = kind == .custom ? nil : loggedDates[kind]
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onPick(kind)
            dismiss()
        } label: {
            BrandCard(tier: .card) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(kind.emoji)
                        .font(.largeTitle)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(kind.displayName)
                            .font(JourneyFont.label)
                            .foregroundStyle(Brand.textPrimary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                        if kind == .custom {
                            Text("Anything you'd remember")
                                .font(JourneyFont.meta)
                                .foregroundStyle(Brand.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else if let added {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark")
                                    .font(JourneyFont.meta)
                                    .foregroundStyle(FutureLetterStyle.opened)
                                Text("Added \(added.formatted(.dateTime.day().month(.abbreviated)))",
                                     comment: "Memory kind tile: this kind is already on the timeline. %@ is a day such as 'May 1'.")
                                    .font(JourneyFont.meta)
                                    .foregroundStyle(Brand.textSecondary)
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
            }
        }
        .buttonStyle(BouncyButtonStyle(scale: 0.96))
        // Overrides the label only, so the button keeps its trait and action.
        .accessibilityLabel(spokenLabel(for: kind, added: added))
    }

    /// "First Kiss, added May 1", "Custom Moment, anything you'd remember",
    /// or just the kind. Never the emoji.
    private func spokenLabel(for kind: MemoryKind, added: Date?) -> String {
        if kind == .custom {
            return String(localized: "\(kind.displayName), anything you'd remember",
                          comment: "VoiceOver: the custom memory kind in the picker. %@ is its name, such as 'Custom Moment'.")
        }
        if let added {
            return String(localized: "\(kind.displayName), added \(added.formatted(.dateTime.day().month(.wide)))",
                          comment: "VoiceOver: a memory kind already on the timeline. First %@ is the kind such as 'First Kiss', second a day such as 'May 1'.")
        }
        return kind.displayName
    }
}
