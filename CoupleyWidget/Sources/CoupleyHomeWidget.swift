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
        // The brand name is never translated, so it stays out of the catalog.
        .configurationDisplayName(Text(verbatim: "Coupley"))
        .description(Text("Your relationship, alive on your home screen.",
                          comment: "Widget gallery: description of the Coupley home screen widget"))
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}
