//
//  WidgetMediumView.swift
//  CoupleyWidget
//
//  Medium family layout. Two columns:
//   - Left: anniversary hero (big number, topline, subline)
//   - Right: mood capsule + nudge bubble
//   The two columns each carry their own deeplink so the user lands on
//   the most contextual screen. Requires iOS 17+ (`Link` containers
//   inside widgets).
//

import SwiftUI
import WidgetKit

struct WidgetMediumView: View {

    let entry: CoupleyTimelineEntry

    private var highlight: WidgetAnniversaryHighlight {
        WidgetCountdownEngine.highlight(
            from: entry.snapshot.anniversary,
            now: entry.date
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            anniversaryColumn
            partnerColumn
        }
        .padding(16)
    }

    // MARK: - Anniversary column

    private var anniversaryColumn: some View {
        Link(destination: WidgetDeepLink.anniversary.url) {
            VStack(alignment: .leading, spacing: 0) {

                if highlight.isCelebratory {
                    milestoneBadge
                        .padding(.bottom, 8)
                }

                Spacer(minLength: 0)

                WidgetAnniversaryBlock(
                    highlight: highlight,
                    heroSize: 46,
                    alignment: .leading
                )

                Spacer(minLength: 0)

                signatureLine
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var milestoneBadge: some View {
        WidgetGlassCapsule(
            horizontalPadding: 9,
            verticalPadding: 4,
            cornerRadius: 10,
            tint: WidgetPalette.goldStart.opacity(0.22),
            border: WidgetPalette.goldStart.opacity(0.55)
        ) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(WidgetPalette.goldStart)
                Text("Milestone")
                    .font(WidgetType.micro(10))
                    .tracking(0.6)
                    .foregroundStyle(WidgetPalette.textPrimary)
            }
        }
    }

    private var signatureLine: some View {
        HStack(spacing: 5) {
            Image(systemName: "heart.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(WidgetPalette.gradientTop)
            Text(signature)
                .font(WidgetType.caption(11))
                .foregroundStyle(WidgetPalette.textTertiary)
                .lineLimit(1)
        }
    }

    // MARK: - Partner column

    private var partnerColumn: some View {
        VStack(alignment: .leading, spacing: 8) {

            // Partner header — tappable to open mood detail.
            Link(destination: WidgetDeepLink.mood.url) {
                VStack(alignment: .leading, spacing: 8) {
                    headerRow

                    WidgetMoodCapsule(
                        mood: entry.snapshot.mood,
                        referenceDate: entry.date
                    )
                }
            }

            Spacer(minLength: 0)

            // Nudge — opens the home screen (chat / nudge surface).
            Link(destination: WidgetDeepLink.home.url) {
                WidgetNudgeBubble(nudge: entry.snapshot.nudge)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var headerRow: some View {
        HStack(spacing: 6) {
            Text(partnerName)
                .font(WidgetType.title(13))
                .foregroundStyle(WidgetPalette.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 4)

            if let mood = entry.snapshot.mood {
                Text(WidgetRelativeTime.string(for: mood.updatedAt, now: entry.date))
                    .font(WidgetType.micro(10))
                    .foregroundStyle(WidgetPalette.textTertiary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Helpers

    private var partnerName: String {
        if let name = entry.snapshot.partner?.displayName, !name.isEmpty {
            return name
        }
        return "Partner"
    }

    private var signature: String {
        "you & " + (entry.snapshot.partner?.displayName ?? "partner")
    }
}
