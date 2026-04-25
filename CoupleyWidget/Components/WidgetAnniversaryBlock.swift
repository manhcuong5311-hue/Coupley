//
//  WidgetAnniversaryBlock.swift
//  CoupleyWidget
//
//  Hero block. Three visual modes driven by `WidgetAnniversaryHighlight`:
//   - milestone (celebratory): gold gradient ring around the number
//   - upcomingAnniversary (calm): white number, soft pink topline
//   - daysTogether (running total): same as calm but with "of love" subline
//   - empty: invitation to set the date
//

import SwiftUI

struct WidgetAnniversaryBlock: View {

    let highlight: WidgetAnniversaryHighlight
    var heroSize: CGFloat = 44
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 4) {

            if case .empty = highlight {
                emptyState
            } else {
                topline

                heroLine

                subline
            }
        }
    }

    // MARK: - Pieces

    private var topline: some View {
        Text(highlight.topline.uppercased())
            .font(WidgetType.micro(10))
            .tracking(0.8)
            .foregroundStyle(highlight.isCelebratory
                             ? WidgetPalette.goldStart
                             : WidgetPalette.textSecondary)
    }

    private var heroLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("\(highlight.heroNumber)")
                .font(WidgetType.hero(heroSize))
                .foregroundStyle(heroForeground)
                .contentTransition(.numericText(value: Double(highlight.heroNumber)))
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Text(highlight.heroUnit)
                .font(WidgetType.title(heroSize * 0.34))
                .foregroundStyle(WidgetPalette.textPrimary.opacity(0.85))
                .padding(.bottom, heroSize * 0.10)
        }
    }

    @ViewBuilder
    private var subline: some View {
        if highlight.isCelebratory {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(WidgetPalette.goldStart)
                Text(highlight.subline)
                    .font(WidgetType.body(12))
                    .foregroundStyle(WidgetPalette.textPrimary)
                    .lineLimit(1)
            }
        } else {
            Text(highlight.subline)
                .font(WidgetType.body(12))
                .foregroundStyle(WidgetPalette.textSecondary)
                .lineLimit(1)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(alignment: alignment, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(WidgetPalette.gradientTop)
                Text("Together")
                    .font(WidgetType.title(15))
                    .foregroundStyle(WidgetPalette.textPrimary)
            }
            Text("Start your love journey")
                .font(WidgetType.body(11))
                .foregroundStyle(WidgetPalette.textSecondary)
        }
    }

    // MARK: - Foreground

    private var heroForeground: AnyShapeStyle {
        highlight.isCelebratory
            ? AnyShapeStyle(LinearGradient.widgetGold)
            : AnyShapeStyle(WidgetPalette.textPrimary)
    }
}
