//
//  GardenHomeRow.swift
//  Coupley
//
//  Home's one quiet garden row (spec B7): a request waiting for me, or the
//  partner's watering in the last 24 hours that this device has not seen on
//  Journey. Never thirst, never a badge. Tapping opens Journey at the
//  line's focus.
//
//  It sits in Home's ambient zone as a quiet block without its own rule
//  (the zone's first block carries it). The line's words come from
//  GardenViewModel.homeLine.
//

import Foundation
import SwiftUI
import UIKit

struct GardenHomeRow: View {

    let line: GardenHomeLine
    let onOpen: (GardenFocus) -> Void

    init(line: GardenHomeLine, onOpen: @escaping (GardenFocus) -> Void) {
        self.line = line
        self.onOpen = onOpen
    }

    var body: some View {
        BrandCard(tier: .quiet, showsRule: false) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onOpen(line.focus)
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.title)
                            .font(BrandType.label)
                            .foregroundStyle(Brand.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let subtitle = line.subtitle {
                            Text(subtitle)
                                .font(BrandType.meta)
                                .foregroundStyle(Brand.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Brand.textTertiary)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(line.spokenLabel)
            .accessibilityAddTraits(.isButton)
        }
    }
}

// MARK: - Previews

#Preview("Home row · watered") {
    GardenHomeRow(line: GardenHomeLine(kind: .watered,
                                       title: "💧 Sam watered your garden · today at 9:14 PM",
                                       subtitle: "“Thinking of our first coffee.”",
                                       focus: .watering(id: "preview"),
                                       spokenLabel: "Sam watered your garden today at 9:14 PM. Opens Journey."),
                  onOpen: { _ in })
        .padding(.horizontal, Brand.Space.gutter)
        .background(Brand.bgGradient)
}

#Preview("Home row · a seed") {
    GardenHomeRow(line: GardenHomeLine(kind: .request,
                                       title: "🌱 Sam sent you a seed · See it on Journey",
                                       subtitle: nil,
                                       focus: .proposal(id: "preview"),
                                       spokenLabel: "Sam sent you a seed. Opens Journey."),
                  onOpen: { _ in })
        .padding(.horizontal, Brand.Space.gutter)
        .background(Brand.bgGradient)
}
