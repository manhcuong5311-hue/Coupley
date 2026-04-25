//
//  CoupleyTimelineProvider.swift
//  CoupleyWidget
//
//  Timeline strategy:
//   - placeholder: rendered while the system is generating a real snapshot
//     (and in the gallery before any data exists). Shows tasteful sample
//     data so the gallery preview feels alive.
//   - getSnapshot: synchronous read from the App Group container — never
//     hits the network. Returns immediately so the gallery transition
//     doesn't stutter.
//   - getTimeline: builds entries spaced to honour the next-midnight
//     rollover so day counts animate themselves. Caps refresh at 6h to
//     pick up new mood/nudge writes from the main app even if the user
//     hasn't relaunched it.
//

import Foundation
import WidgetKit

struct CoupleyTimelineProvider: TimelineProvider {

    // MARK: - Placeholder

    func placeholder(in context: Context) -> CoupleyTimelineEntry {
        CoupleyTimelineEntry(date: Date(), snapshot: .samplePaired)
    }

    // MARK: - Snapshot

    func getSnapshot(
        in context: Context,
        completion: @escaping (CoupleyTimelineEntry) -> Void
    ) {
        let snapshot = WidgetSnapshotStore.read()
        let entry = CoupleyTimelineEntry(
            date: Date(),
            snapshot: context.isPreview ? .samplePaired : snapshot
        )
        completion(entry)
    }

    // MARK: - Timeline

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<CoupleyTimelineEntry>) -> Void
    ) {
        let snapshot = WidgetSnapshotStore.read()
        let now = Date()

        let entries = makeEntries(snapshot: snapshot, now: now)
        let nextRefresh = WidgetCountdownEngine.nextRefreshDate(after: now)

        completion(Timeline(entries: entries, policy: .after(nextRefresh)))
    }

    // MARK: - Entry Generation

    /// Produces one entry for "now" and one for the start of the next day
    /// so SwiftUI's text content transitions can roll the day count at
    /// midnight without us being woken up. The widget reload at midnight
    /// happens regardless via `nextRefreshDate`.
    private func makeEntries(
        snapshot: WidgetSnapshot,
        now: Date
    ) -> [CoupleyTimelineEntry] {
        var entries = [CoupleyTimelineEntry(date: now, snapshot: snapshot)]

        if let nextMidnight = Calendar.current.nextDate(
            after: now,
            matching: DateComponents(hour: 0, minute: 0, second: 1),
            matchingPolicy: .nextTime
        ), nextMidnight.timeIntervalSince(now) < 24 * 3600 {
            entries.append(CoupleyTimelineEntry(date: nextMidnight, snapshot: snapshot))
        }

        return entries
    }
}

// MARK: - Sample Data

extension WidgetSnapshot {

    /// Used in the widget gallery and SwiftUI previews. Crafted to look
    /// realistic — a partner with a recent loving mood, a sweet nudge,
    /// and a 7-day countdown to a 1 Year Anniversary milestone.
    static var samplePaired: WidgetSnapshot {
        let now = Date()
        let oneYearAgoMinusSevenDays = Calendar.current.date(
            byAdding: .day,
            value: -358,
            to: now
        ) ?? now

        return WidgetSnapshot(
            version: WidgetSnapshot.currentVersion,
            generatedAt: now,
            isPaired: true,
            partner: PartnerSnapshot(displayName: "Lena", avatarFilename: nil),
            mood: MoodSnapshot(
                kind: .missingYou,
                note: "thinking of you",
                updatedAt: now.addingTimeInterval(-2 * 3600),
                customLabel: nil
            ),
            nudge: NudgeSnapshot(
                emoji: "💌",
                message: "Don't forget to smile today",
                receivedAt: now.addingTimeInterval(-45 * 60)
            ),
            anniversary: AnniversarySnapshot(
                relationshipStart: oneYearAgoMinusSevenDays,
                upcoming: [
                    UpcomingAnniversary(
                        id: "first-trip",
                        title: "Our First Trip",
                        date: now.addingTimeInterval(28 * 24 * 3600)
                    )
                ]
            ),
            couplePhotoFilename: nil
        )
    }
}
