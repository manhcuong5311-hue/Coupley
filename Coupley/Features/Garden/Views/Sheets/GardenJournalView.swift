//
//  GardenJournalView.swift
//  Coupley
//
//  The garden journal (spec B5.5, pushed from the Garden sheet): every
//  watering and its note, grouped by month, "Together" pairs, pages of 50.
//
//  The live last 60 come from GardenViewModel.journalEntries(); older pages
//  load through loadJournalPage(before:) as the list reaches its end, with
//  the oldest shown watering's server time (GardenJournalEntry.wateredAt) as
//  the cursor, and the same time titles the month headers. A pending
//  watering has no time yet: it shows under the month above it (or no
//  header at the top), and paging stops
//  if the oldest entry's time is unknown (never claiming "every watering").
//  Only a short page from the server ends the journal: a page that could
//  not load (offline, an error) offers "Try again" instead.
//

import Foundation
import SwiftUI

struct GardenJournalView: View {

    @ObservedObject var garden: GardenViewModel

    init(garden: GardenViewModel) {
        self.garden = garden
    }

    /// Pages older than the live listener's, oldest last.
    @State private var older: [GardenJournalEntry] = []
    @State private var isLoadingMore = false
    @State private var reachedEnd = false
    /// The last page asked for could not be loaded (offline, an error).
    @State private var loadFailed = false
    /// The oldest entry's time is unknown: no further page can be asked for.
    @State private var cursorUnknown = false

    var body: some View {
        let entries = allEntries
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Text("Every watering, and the notes you left.",
                     comment: "Garden journal: subtitle under the title")
                    .font(JourneyFont.body)
                    .foregroundStyle(Brand.textSecondary)
                    .padding(.bottom, 20)

                if entries.isEmpty {
                    Text("No waterings yet. The first drop starts the journal.",
                         comment: "Garden journal: no watering yet")
                        .font(JourneyFont.body)
                        .foregroundStyle(Brand.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(months(of: entries)) { month in
                        monthSection(month)
                    }
                    footer(lastId: entries.last?.id)
                }
            }
            .padding(.horizontal, Brand.Space.gutter)
            .padding(.vertical, 16)
        }
        .background(Brand.bgGradient.ignoresSafeArea())
        .navigationTitle(Text("Garden journal", comment: "Garden journal: navigation title"))
        .navigationBarTitleDisplayMode(.inline)
        // The journal shows the partner's latest note: it is read now.
        .onAppear { garden.markWateringSeen() }
    }

    // MARK: - Entries

    private var liveEntries: [GardenJournalEntry] { garden.journalEntries() }

    private var allEntries: [GardenJournalEntry] {
        let live = liveEntries
        let liveIds = Set(live.map(\.id))
        return live + older.filter { !liveIds.contains($0.id) }
    }

    /// The server time of an entry (nil while its watering is pending).
    private func date(of entry: GardenJournalEntry) -> Date? {
        entry.wateredAt
    }

    /// One month of entries; a "Together" pair stays one group.
    private struct Month: Identifiable {
        let id: String
        let title: String
        var groups: [[GardenJournalEntry]]
    }

    private func months(of entries: [GardenJournalEntry]) -> [Month] {
        var months: [Month] = []
        var index = 0
        while index < entries.count {
            let entry = entries[index]
            var group = [entry]
            if entry.pairsWithNext, entries.indices.contains(index + 1) {
                group.append(entries[index + 1])
            }
            index += group.count

            let title = date(of: entry).map { $0.formatted(.dateTime.month(.wide).year()) }
            if let title, months.last?.title != title {
                months.append(Month(id: title, title: title, groups: [group]))
            } else if months.isEmpty {
                // Undated (a pending watering at the top): no month header
                // until its server time arrives.
                months.append(Month(id: entry.id, title: "", groups: [group]))
            } else {
                months[months.count - 1].groups.append(group)
            }
        }
        return months
    }

    // MARK: - Layout

    private func monthSection(_ month: Month) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !month.title.isEmpty {
                Text(month.title)
                    .font(JourneyFont.title)
                    .foregroundStyle(Brand.textPrimary)
                    .accessibilityAddTraits(.isHeader)
            }
            ForEach(month.groups, id: \.first?.id) { group in
                if group.count > 1 {
                    togetherGroup(group)
                } else if let entry = group.first {
                    GardenJournalRow(entry: entry)
                        .onAppear { loadMoreIfLast(entry) }
                }
            }
        }
        .padding(.bottom, 24)
    }

    private func togetherGroup(_ group: [GardenJournalEntry]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                HStack(spacing: -3) {
                    Image(systemName: "drop.fill")
                    Image(systemName: "drop.fill")
                }
                .font(JourneyFont.meta)
                .foregroundStyle(GardenHero.water)
                .accessibilityHidden(true)
                Text("Together", comment: "Garden journal: two waterings by both partners within a day")
                    .font(JourneyFont.label)
                    .foregroundStyle(Brand.textPrimary)
            }
            ForEach(group) { entry in
                GardenJournalRow(entry: entry)
                    .onAppear { loadMoreIfLast(entry) }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wellBackground(in: .card)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func footer(lastId: String?) -> some View {
        if reachedEnd || isLiveComplete {
            Text("That's every watering since your first.",
                 comment: "Garden journal: footer after the oldest watering")
                .font(JourneyFont.meta)
                .foregroundStyle(Brand.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        } else if isLoadingMore {
            ProgressView()
                .tint(Brand.accentStart)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        } else if loadFailed {
            VStack(spacing: 2) {
                Text("Couldn't load older waterings.",
                     comment: "Garden journal: footer when the next page of older waterings could not load (offline or an error)")
                    .font(JourneyFont.meta)
                    .foregroundStyle(Brand.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    loadMore()
                } label: {
                    Text("Try again",
                         comment: "Garden journal: button under that footer; loads the older waterings again")
                        .font(JourneyFont.label)
                        .foregroundStyle(Brand.accentStart)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Paging

    /// The live listener holds every watering there is.
    private var isLiveComplete: Bool {
        older.isEmpty && garden.waterings.waterings.count < GardenLimits.wateringListen
            && !garden.waterings.isFromCache
    }

    private func loadMoreIfLast(_ entry: GardenJournalEntry) {
        guard entry.id == allEntries.last?.id else { return }
        loadMore()
    }

    /// The page before the oldest entry shown. Only a short page from the
    /// server is the end; one that could not load offers "Try again".
    private func loadMore() {
        guard let last = allEntries.last, !reachedEnd, !cursorUnknown, !isLiveComplete,
              !isLoadingMore else { return }
        guard let cursor = date(of: last) else {
            cursorUnknown = true
            return
        }
        isLoadingMore = true
        loadFailed = false
        Task {
            guard let page = await garden.loadJournalPage(before: cursor) else {
                isLoadingMore = false
                loadFailed = true
                return
            }
            let known = Set(allEntries.map(\.id))
            let fresh = page.filter { !known.contains($0.id) }
            older += fresh
            if fresh.isEmpty || page.count < GardenLimits.journalPage { reachedEnd = true }
            isLoadingMore = false
        }
    }
}

// MARK: - Row

/// "Sam · Thu, Nov 13 at 9:14 PM", the note (already in quotes), and the
/// partner's own time when their time zone differs.
struct GardenJournalRow: View {
    let entry: GardenJournalEntry

    var body: some View {
        let name = entry.name, when = entry.when
        VStack(alignment: .leading, spacing: 3) {
            Text("\(name) · \(when)",
                 comment: "Garden journal row: who watered, then when, as in 'Sam · Thu, Nov 13 at 9:14 PM'")
                .font(JourneyFont.label)
                .foregroundStyle(Brand.textPrimary)
            if let partnerTime = entry.partnerLocalTime {
                Text(partnerTime)
                    .font(JourneyFont.meta)
                    .foregroundStyle(Brand.textSecondary)
            }
            if let note = entry.note {
                Text(note)
                    .font(JourneyFont.body)
                    .foregroundStyle(Brand.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Preview

// Builds a GardenViewModel on the in-memory service, so DEBUG only (K7).
#if DEBUG
#Preview("Journal") {
    let service = InMemoryGardenService()
    let garden = GardenViewModel(session: GardenLab.session, service: service)
    NavigationStack {
        GardenJournalView(garden: garden)
    }
    .onAppear {
        garden.start()
        service.simulatePartner(.water(note: "Miss you"))
    }
}
#endif
