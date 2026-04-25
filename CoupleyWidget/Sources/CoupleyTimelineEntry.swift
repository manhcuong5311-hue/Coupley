//
//  CoupleyTimelineEntry.swift
//  CoupleyWidget
//
//  The TimelineEntry is intentionally thin — it just carries the snapshot
//  and the date. Every piece of derived state (countdown, milestone, etc.)
//  is computed inside the view using `entry.date`, so the same snapshot
//  can produce a sequence of timeline entries that animate the day count
//  rolling over at midnight.
//

import Foundation
import WidgetKit

struct CoupleyTimelineEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}
