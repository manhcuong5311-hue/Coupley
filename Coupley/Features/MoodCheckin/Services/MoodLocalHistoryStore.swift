//
//  MoodLocalHistoryStore.swift
//  Coupley
//
//  UserDefaults-backed local mood journal. Captures every mood check-in the
//  user makes on this device so the monthly insight view has data even when
//  offline / unpaired / pre-Firestore-sync. Independent from the Firestore
//  mood pipeline — this is a read-only-from-the-VM journal that the
//  MoodCheckinView calls into after a successful submit.
//
//  Storage shape: a single JSON-encoded `[LocalMoodEntry]` value under
//  `coupley.mood.localHistory`. Up to ~365 entries lives well inside
//  UserDefaults' soft limit; we cap at 24 months to keep it bounded.
//

import Foundation
import Combine

// MARK: - Local Mood Entry

/// Compact local-only record of one mood check-in. Distinct from
/// `MoodEntry` because we never need to round-trip this back to Firestore —
/// it's purely for the local insight view.
struct LocalMoodEntry: Codable, Identifiable, Hashable {
    let id: String          // mirrors the source MoodEntry.id when known
    let mood: Mood
    let energy: EnergyLevel
    let note: String?
    let timestamp: Date

    init(
        id: String = UUID().uuidString,
        mood: Mood,
        energy: EnergyLevel,
        note: String?,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.mood = mood
        self.energy = energy
        self.note = note?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.timestamp = timestamp
    }

    /// Convenience init from the existing MoodEntry shape so the view model
    /// can persist with one line: `store.append(.init(from: entry))`.
    init(from entry: MoodEntry) {
        self.id = entry.id.uuidString
        self.mood = entry.mood
        self.energy = entry.energy
        self.note = entry.note
        self.timestamp = entry.timestamp
    }
}

// MARK: - Store

@MainActor
final class MoodLocalHistoryStore: ObservableObject {

    static let shared = MoodLocalHistoryStore()

    private let storageKey = "coupley.mood.localHistory"
    private let defaults: UserDefaults
    private let retentionMonths: Int = 24

    /// Published so SwiftUI views can re-render on change without us having
    /// to re-read UserDefaults each tick.
    @Published private(set) var entries: [LocalMoodEntry] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: - Read

    /// Entries that fall within the calendar month containing `referenceDate`.
    /// Sorted newest-first.
    func entries(in referenceDate: Date) -> [LocalMoodEntry] {
        let calendar = Calendar.current
        guard
            let interval = calendar.dateInterval(of: .month, for: referenceDate)
        else { return [] }
        return entries
            .filter { interval.contains($0.timestamp) }
            .sorted { $0.timestamp > $1.timestamp }
    }

    /// Returns at most one entry per day in the given month — the latest
    /// check-in for that day. Used to power the calendar dot grid.
    func latestPerDay(in referenceDate: Date) -> [Date: LocalMoodEntry] {
        let calendar = Calendar.current
        var byDay: [Date: LocalMoodEntry] = [:]
        for entry in entries(in: referenceDate) {
            let day = calendar.startOfDay(for: entry.timestamp)
            // entries() returns newest-first, so the first time we see a day
            // is the latest entry for it.
            if byDay[day] == nil {
                byDay[day] = entry
            }
        }
        return byDay
    }

    /// All entries with a non-empty note, sorted newest-first.
    func notedEntries(in referenceDate: Date) -> [LocalMoodEntry] {
        entries(in: referenceDate).filter { ($0.note?.isEmpty == false) }
    }

    // MARK: - Write

    /// Append a new entry. Same-id duplicates are ignored — the Firestore
    /// listener can echo-back without us double-recording.
    func append(_ entry: LocalMoodEntry) {
        guard !entries.contains(where: { $0.id == entry.id }) else { return }
        var next = entries
        next.append(entry)
        next.sort { $0.timestamp > $1.timestamp }
        next = pruneOldEntries(next)
        entries = next
        persist()
    }

    /// Wipe everything. Settings can call this if the user wants a fresh
    /// journal — we don't expose a UI for it yet, but it's here.
    func clearAll() {
        entries = []
        persist()
    }

    // MARK: - Derived Stats

    /// Distribution as `(mood, count)` ordered by `Mood.allCases` so charts
    /// render in a stable order.
    func distribution(in referenceDate: Date) -> [(mood: Mood, count: Int)] {
        let monthEntries = entries(in: referenceDate)
        return Mood.allCases.map { mood in
            (mood: mood, count: monthEntries.filter { $0.mood == mood }.count)
        }
    }

    /// The mood with the most check-ins in the given month. Returns nil
    /// when the month is empty.
    func dominantMood(in referenceDate: Date) -> Mood? {
        let dist = distribution(in: referenceDate)
        guard let top = dist.max(by: { $0.count < $1.count }), top.count > 0 else {
            return nil
        }
        return top.mood
    }

    /// Number of distinct days with a check-in this month.
    func daysWithCheckin(in referenceDate: Date) -> Int {
        latestPerDay(in: referenceDate).count
    }

    /// Current consecutive-day streak ending today (or yesterday if today
    /// hasn't been logged yet — same grace window as the Together streak
    /// model so the two surfaces agree).
    func currentStreak(now: Date = Date()) -> Int {
        let calendar = Calendar.current
        let logDays: Set<Date> = Set(entries.map { calendar.startOfDay(for: $0.timestamp) })

        var anchor = calendar.startOfDay(for: now)
        if !logDays.contains(anchor) {
            anchor = calendar.date(byAdding: .day, value: -1, to: anchor) ?? anchor
        }

        var streak = 0
        var cursor = anchor
        while logDays.contains(cursor) {
            streak += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        return streak
    }

    /// Average energy expressed on a 1-3 scale (low=1, medium=2, high=3).
    /// Returns nil for empty months. Used to render the energy gauge.
    func averageEnergyValue(in referenceDate: Date) -> Double? {
        let monthEntries = entries(in: referenceDate)
        guard !monthEntries.isEmpty else { return nil }
        let sum = monthEntries.reduce(0.0) { acc, entry in
            acc + Double(energyValue(entry.energy))
        }
        return sum / Double(monthEntries.count)
    }

    /// Months that contain at least one entry. Sorted oldest→newest. Used
    /// by the month picker so the user can scroll through history.
    func availableMonths() -> [Date] {
        let calendar = Calendar.current
        var seen: Set<Date> = []
        for entry in entries {
            if let interval = calendar.dateInterval(of: .month, for: entry.timestamp) {
                seen.insert(interval.start)
            }
        }
        // Always include the current month so an empty journal still shows
        // somewhere meaningful.
        if let nowMonth = calendar.dateInterval(of: .month, for: Date())?.start {
            seen.insert(nowMonth)
        }
        return Array(seen).sorted()
    }

    // MARK: - Internal

    private func energyValue(_ level: EnergyLevel) -> Int {
        switch level {
        case .low:    return 1
        case .medium: return 2
        case .high:   return 3
        }
    }

    private func pruneOldEntries(_ items: [LocalMoodEntry]) -> [LocalMoodEntry] {
        let calendar = Calendar.current
        guard
            let cutoff = calendar.date(byAdding: .month, value: -retentionMonths, to: Date())
        else { return items }
        return items.filter { $0.timestamp >= cutoff }
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([LocalMoodEntry].self, from: data) else {
            entries = []
            return
        }
        entries = decoded.sorted { $0.timestamp > $1.timestamp }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

// MARK: - String helper

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
