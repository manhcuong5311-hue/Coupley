//
//  MicroAction.swift
//  Coupley
//

import Foundation

// MARK: - Tone

enum MicroActionTone: String, Codable, Equatable {
    case support   // partner needs gentle care
    case bonding   // partner is up / connected mood
    case light     // neutral or unknown state
}

// MARK: - Status

enum MicroActionStatus: String, Codable, Equatable {
    case pending
    case done
    case skipped
    case snoozed
}

// MARK: - Micro Action

/// A single private suggestion shown to the current user. Never synced to the
/// partner. Stored locally only.
struct MicroAction: Identifiable, Codable, Equatable {
    let id: String
    let text: String
    let tone: MicroActionTone
    /// "Why this, now" — a short rationale shown in the detail row.
    let rationale: String
    let createdAt: Date
    var status: MicroActionStatus
    var doneAt: Date?
    var snoozedUntil: Date?

    /// Hash of the context that produced it. Used so we don't regenerate the
    /// same suggestion again when the mood input hasn't actually moved.
    let contextKey: String

    init(
        id: String = UUID().uuidString,
        text: String,
        tone: MicroActionTone,
        rationale: String,
        contextKey: String,
        createdAt: Date = Date(),
        status: MicroActionStatus = .pending
    ) {
        self.id = id
        self.text = text
        self.tone = tone
        self.rationale = rationale
        self.contextKey = contextKey
        self.createdAt = createdAt
        self.status = status
    }

    // MARK: - Derived

    var isActionable: Bool {
        switch status {
        case .pending:  return true
        case .snoozed:  return (snoozedUntil ?? .distantFuture) <= Date()
        case .done, .skipped: return false
        }
    }

    var isToday: Bool {
        Calendar.current.isDateInToday(createdAt)
    }
}

// MARK: - Generation Context

/// All inputs the generator needs. The view model assembles this from the
/// existing CoupleViewModel + ProfileService.
struct MicroActionContext: Equatable {

    /// Summary of the partner's latest mood log. `nil` when we've never seen one.
    struct PartnerMood: Equatable {
        let mood: Mood
        let energy: EnergyLevel
        let loggedAt: Date
        let note: String?
    }

    let partnerMood: PartnerMood?
    /// Partner's mood strings for the last ~7 days — we use this to avoid
    /// suggesting the same kind of action several days in a row.
    let recentMoods: [Mood]
    /// Last seen within ~2 hours = active.
    let partnerIsActive: Bool
    let profile: PartnerProfile?

    /// Texts of the actions we've already generated recently — used for dedup.
    var recentActionTexts: [String] = []

    /// Stable key that summarizes the *meaningful* part of the context. When
    /// this changes we know it's time to regenerate.
    var key: String {
        let m = partnerMood.map { "\($0.mood.rawValue)-\($0.energy.rawValue)" } ?? "none"
        let day = ISO8601DateFormatter().string(from: Calendar.current.startOfDay(for: Date()))
        return "\(day)|\(m)|\(partnerIsActive ? "a" : "i")"
    }
}
