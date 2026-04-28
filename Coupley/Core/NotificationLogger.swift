//
//  NotificationLogger.swift
//  Coupley
//
//  Centralised, ring-buffered log of every notification-system event
//  (permission, APNs/FCM tokens, pushes received, taps). Used by:
//    – `os_log` for Console.app on real devices
//    – the in-app DebugMenu's "Logs" panel
//
//  The buffer is persisted to UserDefaults so it survives backgrounding
//  and cold launch — important when QA wants to inspect what happened
//  *before* they opened the debug sheet.
//

import Foundation
import os.log
import Combine

@MainActor
final class NotificationLogger: ObservableObject {

    static let shared = NotificationLogger()

    // MARK: - Types

    enum Level: String, Codable {
        case info, warn, error, success

        var glyph: String {
            switch self {
            case .info:    return "•"
            case .warn:    return "!"
            case .error:   return "x"
            case .success: return "✓"
            }
        }
    }

    struct Entry: Codable, Identifiable, Equatable {
        let id: UUID
        let timestamp: Date
        let level: Level
        let category: String
        let message: String
    }

    // MARK: - State

    @Published private(set) var entries: [Entry] = []
    @Published var lastReceivedAt: Date?

    private let osLog = Logger(subsystem: "com.SamCorp.Coupley", category: "Notifications")
    private let bufferLimit = 200
    private let storeKey = "coupley.notif.logs.v1"
    private let lastReceivedKey = "coupley.notif.lastReceivedAt.v1"

    // MARK: - Init

    private init() {
        entries = loadEntries()
        if let stored = UserDefaults.standard.object(forKey: lastReceivedKey) as? Date {
            lastReceivedAt = stored
        }
    }

    // MARK: - Logging

    func log(_ level: Level, category: String, _ message: String) {
        let entry = Entry(id: UUID(), timestamp: Date(),
                          level: level, category: category, message: message)
        entries.insert(entry, at: 0)
        if entries.count > bufferLimit {
            entries = Array(entries.prefix(bufferLimit))
        }
        osLog.log(level: level.osLogLevel,
                  "\(level.glyph, privacy: .public) [\(category, privacy: .public)] \(message, privacy: .public)")
        persist()
    }

    func info(_ category: String, _ message: String)    { log(.info,    category: category, message) }
    func warn(_ category: String, _ message: String)    { log(.warn,    category: category, message) }
    func error(_ category: String, _ message: String)   { log(.error,   category: category, message) }
    func success(_ category: String, _ message: String) { log(.success, category: category, message) }

    func recordReceived(at date: Date = Date()) {
        lastReceivedAt = date
        UserDefaults.standard.set(date, forKey: lastReceivedKey)
    }

    func clear() {
        entries.removeAll()
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: storeKey)
    }

    private func loadEntries() -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: storeKey),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return decoded
    }
}

private extension NotificationLogger.Level {
    var osLogLevel: OSLogType {
        switch self {
        case .info, .success: return .info
        case .warn:           return .default
        case .error:          return .error
        }
    }
}
