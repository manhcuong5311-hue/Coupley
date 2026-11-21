//
//  CoupleyWidgetBundle.swift
//  CoupleyWidget
//
//  Widget extension entry point. Add additional widgets here as the app
//  grows (lock screen, StandBy, etc.) — each one is a separate
//  `WidgetConfiguration` value returned from `body`.
//

import SwiftUI
import WidgetKit

@main
struct CoupleyWidgetBundle: WidgetBundle {

    init() {
        // The widget is its own process with its own preferences: the same
        // override as the app, before anything formats a date or a number.
        FormattingLocale.applyOverride()
    }

    var body: some Widget {
        CoupleyHomeWidget()
    }
}
