//
//  AnchorSetupSheet.swift
//  Coupley
//
//  "When did it begin?": picks the day the couple's story started, which
//  every day count, anniversary and crown on Journey grows from. First run
//  plants the tree; later it edits the start date from the hero's
//  "Since … · Edit" line.
//
//  The day is a calendar day, not an instant: the picker starts from the day
//  the stored value names (JourneyCalendarDay.localDay(ofStored:)), and the
//  view model stores what is picked as that day for both partners, wherever
//  each of them is.
//

import Foundation
import SwiftUI
import UIKit

// MARK: - Start-date sheet

struct AnchorSetupSheet: View {

    @ObservedObject var viewModel: TimeTreeViewModel
    /// The current start date, if one is set. Non-nil makes this an edit.
    let existing: RelationshipAnchor?
    /// This user's name, stored with the date so the partner's phone can say
    /// who set it.
    let myName: String?
    let partnerName: String

    @Environment(\.dismiss) private var dismiss

    @State private var startDate: Date

    /// The leaf's well grows with the text.
    @ScaledMetric(relativeTo: .largeTitle) private var glyphSize: CGFloat = 84

    init(viewModel: TimeTreeViewModel,
         existing: RelationshipAnchor?,
         myName: String?,
         partnerName: String) {
        self.viewModel = viewModel
        self.existing = existing
        self.myName = myName
        self.partnerName = partnerName

        let calendar = Calendar.current
        let threeMonthsAgo = calendar.date(byAdding: .month, value: -3, to: Date()) ?? Date()
        _startDate = State(initialValue: existing.map { JourneyCalendarDay.localDay(ofStored: $0.startDate) }
                           ?? calendar.startOfDay(for: threeMonthsAgo))
    }

    private var isEditing: Bool { existing != nil }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    heroBlock

                    dateCard

                    if let existing {
                        attributionFootnote(existing)
                    }
                }
                .padding(.horizontal, Brand.Space.gutter)
                .padding(.top, 20)
                .padding(.bottom, 16)
            }
            // The sheet's one filled control, pinned under the content.
            .safeAreaInset(edge: .bottom) {
                BrandCTA(title: isEditing ? "Save start date" : "Plant tree",
                         tier: .hero,
                         isBusy: viewModel.isSavingAnchor) {
                    save()
                }
                .padding(.horizontal, Brand.Space.gutter)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            .background(Brand.bgGradient.ignoresSafeArea())
            .navigationTitle(isEditing ? "Start date" : "Plant your tree")
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
            Image(systemName: "leaf.fill")
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(Brand.accentStart)
                .frame(width: glyphSize, height: glyphSize)
                .background(
                    Circle().fill(
                        LinearGradient(
                            colors: [Brand.accentStart.opacity(0.30), Brand.accentEnd.opacity(0.18)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                )
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(isEditing ? "When did it begin?" : "Plant your tree")
                    .font(JourneyFont.display)
                    .foregroundStyle(Brand.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Text("Pick the day your story began. Your tree grows from it, and \(partnerName) sees it too.")
                    .font(JourneyFont.body)
                    .foregroundStyle(Brand.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    // MARK: - Date card

    private var dateCard: some View {
        BrandCard(tier: .card) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Start date", systemImage: "calendar")
                    .font(JourneyFont.label)
                    .foregroundStyle(Brand.textSecondary)
                    .accessibilityHidden(true)

                DatePicker(
                    "Start date",
                    selection: $startDate,
                    in: ...Date(),
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
                .tint(Brand.accentStart)
                .labelsHidden()
            }
        }
    }

    // MARK: - Attribution footnote

    private func attributionFootnote(_ anchor: RelationshipAnchor) -> some View {
        let who = anchor.setBy == viewModel.currentUserId ? "you" : partnerName
        return HStack(spacing: 8) {
            Image(systemName: "person.2.fill")
                .font(JourneyFont.meta)
                .foregroundStyle(Brand.textTertiary)
                .accessibilityHidden(true)
            Text("Set by \(who) on \(anchor.setAt.formatted(date: .abbreviated, time: .omitted))")
                .font(JourneyFont.meta)
                .foregroundStyle(Brand.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Save

    private func save() {
        Task {
            await viewModel.setAnchor(startDay: startDate, myName: myName)
            dismiss()
        }
    }
}
