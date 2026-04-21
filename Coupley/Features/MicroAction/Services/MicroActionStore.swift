//
//  MicroActionStore.swift
//  Coupley
//

import Foundation

// MARK: - Protocol

protocol MicroActionStore {
    func load(userId: String) -> [MicroAction]
    func save(_ actions: [MicroAction], userId: String)
}

// MARK: - UserDefaults Implementation

/// Local-only persistence. Private to this device — never uploaded. Keyed by
/// userId so two accounts on the same device don't cross-contaminate.
final class UserDefaultsMicroActionStore: MicroActionStore {

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(userId: String) -> [MicroAction] {
        guard
            let data = defaults.data(forKey: key(for: userId)),
            let items = try? JSONDecoder().decode([MicroAction].self, from: data)
        else { return [] }
        return items
    }

    func save(_ actions: [MicroAction], userId: String) {
        // Keep history bounded — anything older than 30 days is dropped so
        // the file doesn't grow forever.
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
        let trimmed = actions.filter { $0.createdAt >= cutoff }

        if let data = try? JSONEncoder().encode(trimmed) {
            defaults.set(data, forKey: key(for: userId))
        }
    }

    private func key(for userId: String) -> String {
        "microActions.v1.\(userId)"
    }
}
