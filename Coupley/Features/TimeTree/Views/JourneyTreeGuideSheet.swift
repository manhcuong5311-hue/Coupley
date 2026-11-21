//
//  JourneyTreeGuideSheet.swift
//  Coupley
//
//  "How your tree grows": the growth stages with where the couple is now,
//  and what the tree carries (memories as stars, sealed letters as
//  envelopes, opened letters as blossoms, crowns, the season's colours).
//  In the garden it also explains watering and places (B6), and a place
//  tree's guide counts from its planting day and shows only what a place
//  tree carries (B3 row 1).
//  Opened from the stage name in Journey's hero.
//

import Foundation
import SwiftUI
import UIKit

// MARK: - Tree guide

struct JourneyTreeGuideSheet: View {

    let stage: TreeGrowthStage
    /// Days since the tree's growth start: the start date for Our tree, the
    /// planting day for a place tree (`growsFromPlanting`).
    let daysTogether: Int
    let partnerName: String
    /// Garden mode: adds the Watering and Your places sections.
    let showsGarden: Bool
    /// A place tree's guide: it grows from the day it was planted (owner
    /// decision 3), and it never carries memory stars, letters, blossoms or
    /// crowns (spec C5), so only the colours row stays.
    let growsFromPlanting: Bool

    @Environment(\.dismiss) private var dismiss

    init(stage: TreeGrowthStage, daysTogether: Int, partnerName: String,
         showsGarden: Bool = GardenFeature.isEnabled, growsFromPlanting: Bool = false) {
        self.stage = stage
        self.daysTogether = daysTogether
        self.partnerName = partnerName
        self.showsGarden = showsGarden
        self.growsFromPlanting = growsFromPlanting
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
                    if showsGarden {
                        wateringSection
                        placesSection
                    }
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
                    Button {
                        dismiss()
                    } label: {
                        Text("Done", comment: "Toolbar button: close the tree guide")
                    }
                    .foregroundStyle(Brand.accentStart)
                }
            }
        }
    }

    // MARK: - Stages

    private var stagesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(LocalizedStringResource("Stages", comment: "Tree guide section title: the tree's growth stages"))

            Group {
                if growsFromPlanting {
                    if daysTogether > 0 {
                        Text("This tree grows from the day you planted it. Today is day \(daysTogether).",
                             comment: "Tree guide for a place tree (a tree the couple planted together for a place or a moment). The number is how many days ago they planted it; the planting day is day 0.")
                    } else {
                        Text("This tree grows from the day you planted it, starting today.",
                             comment: "Tree guide for a place tree (a tree the couple planted together for a place or a moment), on the day they planted it")
                    }
                } else if daysTogether > 0 {
                    Text("It grows from the day your story began. Today is day \(daysTogether).",
                         comment: "Tree guide. The number is how many days the couple has been together.")
                } else {
                    Text("It grows from the day your story began, starting today.",
                         comment: "Tree guide, on the day the relationship started")
                }
            }
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
        let spokenLabel = String(localized: "\(item.displayName), \(detail(for: item))",
                                 comment: "VoiceOver: a tree growth stage. First %@ is its name such as 'Blooming', second when it starts such as 'from day 180'.")
        let spokenValue: String = isCurrent
            ? String(localized: "You're here", comment: "Tree guide: the couple's current growth stage")
            : (isEarlier ? String(localized: "Reached", comment: "VoiceOver value: a growth stage the tree has already passed") : "")

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
                Text("You're here", comment: "Tree guide: the couple's current growth stage")
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
    /// "from day 365 · in 74 days". Each is one whole phrase: the next stage
    /// is never the first, so it always starts on a day number.
    private func detail(for item: TreeGrowthStage) -> String {
        guard item.startDay > 0 else {
            return String(localized: "from the start", comment: "Tree guide: the first growth stage starts on day 0")
        }
        guard item == nextStage else {
            return String(localized: "from day \(item.startDay)",
                          comment: "Tree guide: the day number a growth stage starts on")
        }
        let left = max(1, item.startDay - daysTogether)
        return left == 1
            ? String(localized: "from day \(item.startDay) · in 1 day",
                     comment: "Tree guide, the next growth stage: the day number it starts on; it is tomorrow")
            : String(localized: "from day \(item.startDay) · in \(left) days",
                     comment: "Tree guide, the next growth stage: the day number it starts on, then the days left until then")
    }

    // MARK: - Garden

    private var wateringSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(LocalizedStringResource("Watering", comment: "Tree guide section title: watering the garden"))
            BrandCard(tier: .card) {
                growsRow(symbol: "drop.fill",
                         tint: FutureLetterStyle.accent,
                         text: wateringText)
            }
        }
    }

    /// Matches the tree's look (`GardenTreeLook`) and the FAQ's answer.
    private var wateringText: LocalizedStringResource {
        GardenTreeLook.withersWhenThirsty
            ? LocalizedStringResource("Water your garden every couple of days. One tap waters every tree, and a note can go with it. A tree never dies and never loses its growth: when it's thirsty it droops a little, and after a week it rests until the next drop.",
                                      comment: "Tree guide: how watering works, for the look where an unwatered tree droops and then rests. Not shown while unwatered trees keep their plain look.")
            : LocalizedStringResource("Water your garden every couple of days. One tap waters every tree, and a note can go with it. A tree never dies, never wilts and never loses its growth: water makes it greener and fuller for a day or two.",
                                      comment: "Tree guide: how watering works. Watering is only a reward: a watered tree looks greener and fuller for a day or two, and an unwatered tree never wilts.")
    }

    private var placesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(LocalizedStringResource("Your places", comment: "Tree guide section title: trees for places and moments"))
            BrandCard(tier: .card) {
                growsRow(symbol: "mappin.and.ellipse",
                         tint: FutureLetterStyle.opened,
                         text: LocalizedStringResource("Each tree can stand for a place and a moment. You plant it together: one of you sends a seed, the other plants it.",
                                                       comment: "Tree guide: what place trees are"))
            }
        }
    }

    // MARK: - What grows on it

    private var growsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(LocalizedStringResource("What grows on it", comment: "Tree guide section title: what the tree shows"))

            BrandCard(tier: .card) {
                VStack(alignment: .leading, spacing: 0) {
                    // Stars, letters, blossoms and crowns are Our tree's (C5).
                    if !growsFromPlanting {
                        growsRow(symbol: "sparkles",
                                 tint: FutureLetterStyle.gold,
                                 text: "Your memories shine as stars around it.")
                        rule
                        growsRow(symbol: "envelope.fill",
                                 tint: FutureLetterStyle.accent,
                                 text: LocalizedStringResource("Sealed letters hang from the branches: \(partnerName)'s on the left, yours on the right. Tap one to open it.",
                                                               comment: "Tree guide. %@ is the partner's name; their letters hang on the left of the tree, the user's on the right."))
                        rule
                        growsRow(symbol: "camera.macro",
                                 tint: FutureLetterStyle.gold,
                                 text: "Once a letter is opened, it blooms.")
                        rule
                        growsRow(symbol: "crown.fill",
                                 tint: FutureLetterStyle.gold,
                                 text: "Crowns mark 100 days, 1 year, 500 days, 2 years, 1000 days and beyond.")
                        rule
                    }
                    growsRow(symbol: "leaf.fill",
                             tint: FutureLetterStyle.opened,
                             text: "Its colours change through the year.")
                }
            }
        }
    }

    private func growsRow(symbol: String, tint: Color, text: LocalizedStringResource) -> some View {
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

    private func sectionTitle(_ text: LocalizedStringResource) -> some View {
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
