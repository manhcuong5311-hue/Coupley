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
    var body: some Widget {
        CoupleyHomeWidget()
    }
}
