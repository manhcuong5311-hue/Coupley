//
//  JourneyTreeGuideSheet.swift
//  Coupley
//
//  "How your tree grows": the growth stages with where the couple is now,
//  and what the tree carries (memories as stars, sealed letters as
//  envelopes, opened letters as blossoms, crowns, the season's colours).
//  Opened from the stage name in Journey's hero.
//

import Foundation
import SwiftUI
import UIKit

// MARK: - Tree guide

struct JourneyTreeGuideSheet: View {

    let stage: TreeGrowthStage
    let daysTogether: Int
    let partnerName: String

    @Environment(\.dismiss) private var dismiss

    init(stage: TreeGrowthStage, daysTogether: Int, partnerName: String) {
        self.stage = stage
        self.daysTogether = daysTogether
        self.partnerName = partnerName
    }

    /// The first stage still ahead, if any.
    private var nextStage: TreeGrowthStage? {
        TreeGrowthStage.allCases.first { $0 > stage }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Brand.Space.zone) {
                    stagesSection
                    growsSection
                }
                .padding(.horizontal, Brand.Space.gutter)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(Brand.bgGradient.ignoresSafeArea())
            .navigationTitle("How your tree grows")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Brand.accentStart)
                }
            }
        }
    }

    // MARK: - Stages

    private var stagesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Stages")

            Text(daysTogether > 0
                 ? "It grows from the day your story began. Today is day \(daysTogether)."
                 : "It grows from the day your story began, starting today.")
                .font(JourneyFont.body)
                .foregroundStyle(Brand.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)

            BrandCard(tier: .card) {
                VStack(spacing: 0) {
                    ForEach(TreeGrowthStage.allCases, id: \.self) { item in
                        if item != TreeGrowthStage.allCases.first {
                            rule
                        }
                        stageRow(item)
                    }
                }
            }
        }
    }

    private func stageRow(_ item: TreeGrowthStage) -> some View {
        let isCurrent = item == stage
        let isEarlier = item < stage
        let marker = isCurrent ? "circle.inset.filled" : (isEarlier ? "checkmark.circle.fill" : "circle")
        let spokenLabel = "\(item.displayName), \(detail(for: item))"
        let spokenValue: String = isCurrent ? "You're here" : (isEarlier ? "Reached" : "")

        return HStack(spacing: 12) {
            Image(systemName: marker)
                .font(JourneyFont.title)
                .foregroundStyle(isCurrent ? Brand.accentStart : (isEarlier ? Brand.textSecondary : Brand.textTertiary))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(JourneyFont.label)
                    .foregroundStyle(isEarlier ? Brand.textSecondary : Brand.textPrimary)
                Text(detail(for: item))
                    .font(JourneyFont.meta)
                    .foregroundStyle(Brand.textSecondary)
            }

            Spacer(minLength: 8)

            if isCurrent {
                Text("You're here")
                    .font(JourneyFont.caption)
                    .foregroundStyle(Brand.textPrimary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .wellBackground(in: .card, radius: 10)
                    .fixedSize()
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityValue(spokenValue)
    }

    /// "from the start", "from day 180", and for the next stage
    /// "from day 365 · in 74 days".
    private func detail(for item: TreeGrowthStage) -> String {
        let from = item.startDay == 0 ? "from the start" : "from day \(item.startDay)"
        guard item == nextStage else { return from }
        let left = max(1, item.startDay - daysTogether)
        return "\(from) · in \(left) \(left == 1 ? "day" : "days")"
    }

    // MARK: - What grows on it

    private var growsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("What grows on it")

            BrandCard(tier: .card) {
                VStack(alignment: .leading, spacing: 0) {
                    growsRow(symbol: "sparkles",
                             tint: FutureLetterStyle.gold,
                             text: "Your memories shine as stars around it.")
                    rule
                    growsRow(symbol: "envelope.fill",
                             tint: FutureLetterStyle.accent,
                             text: "Sealed letters hang from the branches: \(partnerName)'s on the left, yours on the right. Tap one to open it.")
                    rule
                    growsRow(symbol: "camera.macro",
                             tint: FutureLetterStyle.gold,
                             text: "Once a letter is opened, it blooms.")
                    rule
                    growsRow(symbol: "crown.fill",
                             tint: FutureLetterStyle.gold,
                             text: "Crowns mark 100 days, 1 year, 500 days, 2 years, 1000 days and beyond.")
                    rule
                    growsRow(symbol: "leaf.fill",
                             tint: FutureLetterStyle.opened,
                             text: "Its colours change through the year.")
                }
            }
        }
    }

    private func growsRow(symbol: String, tint: Color, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .font(JourneyFont.label)
                .foregroundStyle(tint)
                .frame(minWidth: 22)
                .accessibilityHidden(true)
            Text(text)
                .font(JourneyFont.body)
                .foregroundStyle(Brand.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
    }

    // MARK: - Pieces

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(JourneyFont.title)
            .foregroundStyle(Brand.textPrimary)
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, 4)
    }

    private var rule: some View {
        Rectangle()
            .fill(Brand.divider)
            .frame(height: 1)
    }
}
