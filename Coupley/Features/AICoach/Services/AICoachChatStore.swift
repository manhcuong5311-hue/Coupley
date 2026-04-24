//
//  AICoachChatStore.swift
//  Coupley
//
//  UserDefaults-backed persistence for the AI Coach chat transcript. The
//  transcript is intentionally *not* erased when the sheet is dismissed —
//  opening the coach again restores the previous conversation so people can
//  pick up where they left off.
//

import Foundation

protocol AICoachChatStoring {
    func load(for userId: String) -> CoachChatSession
    func save(_ session: CoachChatSession, for userId: String)
    func clear(for userId: String)
}

final class AICoachChatStore: AICoachChatStoring {

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(for userId: String) -> CoachChatSession {
        guard let data = defaults.data(forKey: key(for: userId)),
              let session = try? decoder.decode(CoachChatSession.self, from: data) else {
            return .empty
        }
        return session
    }

    func save(_ session: CoachChatSession, for userId: String) {
        guard let data = try? encoder.encode(session) else { return }
        defaults.set(data, forKey: key(for: userId))
    }

    func clear(for userId: String) {
        defaults.removeObject(forKey: key(for: userId))
    }

    private func key(for userId: String) -> String {
        "coupley.aicoach.session.\(userId)"
    }
}
