//
//  WidgetNudgeBubble.swift
//  CoupleyWidget
//
//  Compact card that surfaces the latest nudge. Gracefully handles the
//  empty case so the layout never reflows when nudges arrive/expire.
//

import SwiftUI

struct WidgetNudgeBubble: View {

    let nudge: NudgeSnapshot?

    var body: some View {
        WidgetGlassCard(
            padding: EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10),
            cornerRadius: 14
        ) {
            HStack(alignment: .center, spacing: 8) {
                Text(nudge?.emoji ?? "💌")
                    .font(.system(size: 16))

                Text(nudge?.message ?? "No new nudge today")
                    .font(WidgetType.body(12))
                    .foregroundStyle(
                        nudge == nil ? WidgetPalette.textSecondary : WidgetPalette.textPrimary
                    )
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
