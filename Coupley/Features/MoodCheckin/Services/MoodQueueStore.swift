//
//  MoodQueueStore.swift
//  Coupley
//
//  Persists MoodEntry writes that failed (offline / transient error) so they can
//  be retried later. Firestore has its own offline cache, but this queue also
//  survives app relaunch and surfaces a "pending sync" state in the UI.
//

import Foundation

// MARK: - Queue Store Protocol

protocol MoodQueueStore {
    func enqueue(_ entry: MoodEntry)
    func dequeue(id: UUID)
    func all() -> [MoodEntry]
    var pendingCount: Int { get }
}

// MARK: - UserDefaults-backed Store

final class UserDefaultsMoodQueueStore: MoodQueueStore {

    private let key = "Coupley.pendingMoodEntries"
    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var pendingCount: Int {
        all().count
    }

    func enqueue(_ entry: MoodEntry) {
        lock.lock(); defer { lock.unlock() }
        var items = load()
        // Dedupe by id
        items.removeAll { $0.id == entry.id }
        items.append(entry)
        save(items)
    }

    func dequeue(id: UUID) {
        lock.lock(); defer { lock.unlock() }
        var items = load()
        items.removeAll { $0.id == id }
        save(items)
    }

    func all() -> [MoodEntry] {
        lock.lock(); defer { lock.unlock() }
        return load()
    }

    // MARK: - Private

    private func load() -> [MoodEntry] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder.iso8601.decode([MoodEntry].self, from: data)) ?? []
    }

    private func save(_ entries: [MoodEntry]) {
        if entries.isEmpty {
            defaults.removeObject(forKey: key)
            return
        }
        if let data = try? JSONEncoder.iso8601.encode(entries) {
            defaults.set(data, forKey: key)
        }
    }
}

// MARK: - Coders

private extension JSONDecoder {
    static let iso8601: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

private extension JSONEncoder {
    static let iso8601: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}
