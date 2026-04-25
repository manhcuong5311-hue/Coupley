//
//  WidgetMoodCapsule.swift
//  CoupleyWidget
//
//  Pill that surfaces the partner's current mood. When mood data is
//  missing it renders a quiet empty-state pill ("No mood shared yet")
//  rather than disappearing — keeps the widget from feeling broken.
//

import SwiftUI

struct WidgetMoodCapsule: View {

    let mood: MoodSnapshot?
    let referenceDate: Date
    var compact: Bool = false

    var body: some View {
        if let mood {
            WidgetGlassCapsule(horizontalPadding: compact ? 10 : 12,
                               verticalPadding: compact ? 5 : 7) {
                HStack(spacing: 6) {
                    Text(mood.kind.emoji)
                        .font(.system(size: compact ? 13 : 15))

                    Text(label(for: mood))
                        .font(WidgetType.body(compact ? 11 : 12))
                        .foregroundStyle(WidgetPalette.textPrimary)
                        .lineLimit(1)

                    if !compact {
                        Text("·")
                            .font(WidgetType.caption(11))
                            .foregroundStyle(WidgetPalette.textTertiary)

                        Text(WidgetRelativeTime.string(for: mood.updatedAt, now: referenceDate))
                            .font(WidgetType.caption(11))
                            .foregroundStyle(WidgetPalette.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
        } else {
            WidgetGlassCapsule(horizontalPadding: compact ? 10 : 12,
                               verticalPadding: compact ? 5 : 7) {
                HStack(spacing: 6) {
                    Text("💭")
                        .font(.system(size: compact ? 13 : 15))
                    Text("No mood yet")
                        .font(WidgetType.body(compact ? 11 : 12))
                        .foregroundStyle(WidgetPalette.textSecondary)
                }
            }
        }
    }

    private func label(for mood: MoodSnapshot) -> String {
        if let custom = mood.customLabel, !custom.isEmpty {
            return custom
        }
        return mood.kind.label
    }
}
