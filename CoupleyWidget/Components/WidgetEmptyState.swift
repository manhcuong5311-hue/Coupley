//
//  WidgetEmptyState.swift
//  CoupleyWidget
//
//  "Connect with your partner" — shown when no partner is paired. Tapping
//  the widget opens the main app's pairing flow via the `partner` deeplink.
//

import SwiftUI

struct WidgetEmptyState: View {

    var compact: Bool = false

    var body: some View {
        VStack(spacing: compact ? 8 : 12) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: compact ? 44 : 56, height: compact ? 44 : 56)
                Circle()
                    .strokeBorder(Color.white.opacity(0.32), lineWidth: 1)
                    .frame(width: compact ? 44 : 56, height: compact ? 44 : 56)
                Text(verbatim: "💞")
                    .font(.system(size: compact ? 22 : 28))
            }

            VStack(spacing: 2) {
                Text("Connect with your partner",
                     comment: "Widget: shown until the user has paired with their partner in the app")
                    .font(WidgetType.title(compact ? 13 : 15))
                    .foregroundStyle(WidgetPalette.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                if !compact {
                    Text("Bring your relationship home",
                         comment: "Widget: subtitle under 'Connect with your partner' (home = the home screen)")
                        .font(WidgetType.caption(11))
                        .foregroundStyle(WidgetPalette.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
