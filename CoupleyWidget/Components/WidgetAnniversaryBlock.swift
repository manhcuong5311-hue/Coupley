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
        // `.textCase` rather than `.uppercased()`: it capitalises by the
        // reader's locale rules (Turkish dotted İ, German ß) at render time.
        Text(highlight.topline)
            .textCase(.uppercase)
            .font(WidgetType.micro(10))
            .scriptAwareTracking(0.8)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(highlight.isCelebratory
                             ? WidgetPalette.goldStart
                             : WidgetPalette.textSecondary)
    }

    /// One Text, so the number and its unit stay on one baseline in
    /// whichever order the language puts them.
    private var heroLine: some View {
        Text(styledHeroPhrase)
            .foregroundStyle(heroForeground)
            .contentTransition(.numericText(value: Double(highlight.heroNumber)))
            .minimumScaleFactor(0.6)
            .lineLimit(1)
    }

    /// The localized hero phrase with the number drawn as the hero and the
    /// rest (the unit, before or after it) drawn as the label. The unit's
    /// own colour overrides `heroForeground`, which only the number shows.
    private var styledHeroPhrase: AttributedString {
        let phrase = highlight.heroPhrase
        var styled = AttributedString()
        for run in phrase.runs {
            var part = AttributedString(phrase[run.range])
            if run.replacementIndex != nil {
                part.font = WidgetType.hero(heroSize)
            } else {
                part.font = WidgetType.title(heroSize * 0.34)
                part.foregroundColor = WidgetPalette.textPrimary.opacity(0.85)
            }
            styled += part
        }
        return styled
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
                    .minimumScaleFactor(0.8)
            }
        } else {
            Text(highlight.subline)
                .font(WidgetType.body(12))
                .foregroundStyle(WidgetPalette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(alignment: alignment, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(WidgetPalette.gradientTop)
                Text("Together", comment: "Widget: heading shown before the couple has set the date they got together")
                    .font(WidgetType.title(15))
                    .foregroundStyle(WidgetPalette.textPrimary)
            }
            Text("Start your love journey",
                 comment: "Widget: shown before the couple has set the date they got together")
                .font(WidgetType.body(11))
                .foregroundStyle(WidgetPalette.textSecondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
    }

    // MARK: - Foreground

    private var heroForeground: AnyShapeStyle {
        highlight.isCelebratory
            ? AnyShapeStyle(LinearGradient.widgetGold)
            : AnyShapeStyle(WidgetPalette.textPrimary)
    }
}
