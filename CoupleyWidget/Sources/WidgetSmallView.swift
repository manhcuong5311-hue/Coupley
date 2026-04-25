//
//  WidgetSmallView.swift
//  CoupleyWidget
//
//  Small family layout — anniversary hero is the only persistent content
//  because the canvas is too cramped for both. The mood capsule rides on
//  top as a compact pill so users still get a glance at how their partner
//  is doing.
//

import SwiftUI
import WidgetKit

struct WidgetSmallView: View {

    let entry: CoupleyTimelineEntry

    private var highlight: WidgetAnniversaryHighlight {
        WidgetCountdownEngine.highlight(
            from: entry.snapshot.anniversary,
            now: entry.date
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Top: mood pill (truncates gracefully when partner has none)
            WidgetMoodCapsule(
                mood: entry.snapshot.mood,
                referenceDate: entry.date,
                compact: true
            )

            Spacer(minLength: 6)

            // Center: anniversary hero
            WidgetAnniversaryBlock(
                highlight: highlight,
                heroSize: 36,
                alignment: .leading
            )

            Spacer(minLength: 4)

            // Bottom: signature heart line — small enough to feel like a
            // sign-off rather than UI chrome.
            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(WidgetPalette.gradientTop)
                Text(signature)
                    .font(WidgetType.caption(10))
                    .foregroundStyle(WidgetPalette.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(14)
    }

    private var signature: String {
        if let name = entry.snapshot.partner?.displayName, !name.isEmpty {
            return "you & \(name)"
        }
        return "you & partner"
    }
}
