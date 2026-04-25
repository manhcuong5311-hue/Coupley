//
//  CoupleyHomeWidget.swift
//  CoupleyWidget
//
//  WidgetConfiguration — declares the supported sizes and ties the timeline
//  provider to the entry view. Uses the iOS 17+ container background API so
//  the widget integrates with the user's wallpaper tint and the gallery
//  preview.
//

import SwiftUI
import WidgetKit

struct CoupleyHomeWidget: Widget {

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: WidgetShared.widgetKind,
            provider: CoupleyTimelineProvider()
        ) { entry in
            CoupleyWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetBackground(snapshot: entry.snapshot)
                }
        }
        .configurationDisplayName("Coupley")
        .description("Your relationship, alive on your home screen.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}
