//
//  Anniversary.swift
//  Coupley
//

import Foundation
import FirebaseFirestore

// MARK: - Anniversary

/// A shared countdown event for a couple. Stored in Firestore under
/// `couples/{coupleId}/anniversaries/{id}`. The countdown value itself is
/// never persisted — it's derived on-device from `date` and `Date()`.
struct Anniversary: Identifiable, Codable, Equatable {
    @DocumentID var firestoreId: String?
    var id: String
    var title: String
    var date: Date
    var note: String?
    /// Timezone identifier of the creator. Not used for display —
    /// each device renders the countdown in its *own* timezone so the
    /// label matches the user's local wall-clock day.
    var creatorTimezone: String
    var createdBy: String
    var createdAt: Date
    var updatedAt: Date

    var documentId: String { firestoreId ?? id }

    init(
        id: String = UUID().uuidString,
        title: String,
        date: Date,
        note: String? = nil,
        creatorTimezone: String = TimeZone.current.identifier,
        createdBy: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.note = note
        self.creatorTimezone = creatorTimezone
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Countdown State

enum CountdownState: Equatable {
    case future(days: Int)
    case today
    case past(days: Int)

    /// "D-30" / "D-DAY" / "D+5" style marker.
    var marker: String {
        switch self {
        case .future(let d): return "D-\(d)"
        case .today:         return "D-DAY"
        case .past(let d):   return "D+\(d)"
        }
    }

    /// Human-facing sentence.
    var caption: String {
        switch self {
        case .future(let d):
            if d == 1 { return "1 day to go" }
            return "\(d) days to go"
        case .today:
            return "It's today"
        case .past(let d):
            if d == 1 { return "1 day ago" }
            return "\(d) days ago"
        }
    }

    var isFuture: Bool {
        if case .future = self { return true }
        return false
    }
}

// MARK: - Countdown Engine

/// Pure function: computes day-level countdown between today and a target date,
/// using a single calendar/timezone for both sides so the result is correct
/// across DST transitions and timezone changes. Both dates are normalized to
/// their start-of-day first.
enum CountdownEngine {

    static func state(
        for target: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> CountdownState {
        let startOfTarget = calendar.startOfDay(for: target)
        let startOfNow    = calendar.startOfDay(for: now)
        let components    = calendar.dateComponents([.day], from: startOfNow, to: startOfTarget)
        let days          = components.day ?? 0

        if days > 0   { return .future(days: days) }
        if days == 0  { return .today }
        return .past(days: -days)
    }

    /// Progress from `createdAt` to `date`, clamped [0, 1]. Useful for the
    /// progress-bar decoration. Returns nil for past events (no meaningful bar).
    static func progress(
        anniversary: Anniversary,
        now: Date = Date()
    ) -> Double? {
        let total = anniversary.date.timeIntervalSince(anniversary.createdAt)
        guard total > 0 else { return nil }
        let elapsed = now.timeIntervalSince(anniversary.createdAt)
        return max(0, min(1, elapsed / total))
    }
}

// MARK: - Formatting helpers

extension Anniversary {
    func formattedDate(style: DateFormatter.Style = .long) -> String {
        let f = DateFormatter()
        f.dateStyle = style
        f.timeStyle = .none
        return f.string(from: date)
    }
}
