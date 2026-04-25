//
//  CoupleyWidgetEntryView.swift
//  CoupleyWidget
//
//  Top-level dispatcher — routes by widget family and by paired/unpaired
//  state. Owns the deeplink handling so size-specific views stay
//  presentational.
//

import SwiftUI
import WidgetKit

struct CoupleyWidgetEntryView: View {

    @Environment(\.widgetFamily) private var family

    let entry: CoupleyTimelineEntry

    var body: some View {
        Group {
            if !entry.snapshot.isPaired {
                WidgetEmptyState(compact: family == .systemSmall)
                    .widgetURL(WidgetDeepLink.partner.url)
            } else {
                switch family {
                case .systemSmall:
                    WidgetSmallView(entry: entry)
                        .widgetURL(WidgetDeepLink.anniversary.url)
                case .systemMedium:
                    WidgetMediumView(entry: entry)
                default:
                    WidgetSmallView(entry: entry)
                        .widgetURL(WidgetDeepLink.anniversary.url)
                }
            }
        }
        .foregroundStyle(WidgetPalette.textPrimary)
    }
}

// MARK: - Previews

#Preview("Small · paired", as: .systemSmall) {
    CoupleyHomeWidget()
} timeline: {
    CoupleyTimelineEntry(date: Date(), snapshot: .samplePaired)
}

#Preview("Medium · paired", as: .systemMedium) {
    CoupleyHomeWidget()
} timeline: {
    CoupleyTimelineEntry(date: Date(), snapshot: .samplePaired)
}

#Preview("Small · empty", as: .systemSmall) {
    CoupleyHomeWidget()
} timeline: {
    CoupleyTimelineEntry(date: Date(), snapshot: .placeholder)
}

#Preview("Medium · empty", as: .systemMedium) {
    CoupleyHomeWidget()
} timeline: {
    CoupleyTimelineEntry(date: Date(), snapshot: .placeholder)
}
