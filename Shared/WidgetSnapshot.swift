//
//  WidgetSnapshot.swift
//  Coupley
//
//  The single Codable contract that flows between the main app (writer) and
//  the widget extension (reader). Versioned so we can evolve the schema
//  without crashing older widgets that haven't been re-signed yet.
//

import Foundation

// MARK: - Snapshot

struct WidgetSnapshot: Codable, Equatable {

    /// Bumped whenever the on-disk schema changes in a non-backward-compatible
    /// way. The reader returns `.placeholder` when it sees a higher version
    /// than it knows how to decode.
    static let currentVersion = 1

    var version: Int = WidgetSnapshot.currentVersion
    var generatedAt: Date

    /// True only when the user has an active partner connection. When false
    /// the widget renders the "Connect with your partner" empty state and
    /// every other field is ignored.
    var isPaired: Bool

    var partner: PartnerSnapshot?
    var mood: MoodSnapshot?
    var nudge: NudgeSnapshot?
    var anniversary: AnniversarySnapshot?

    /// Filename inside the App Group container, *not* an absolute URL — the
    /// path of the container can change between launches. Read it via
    /// `WidgetShared.containerURL?.appendingPathComponent(...)`.
    var couplePhotoFilename: String?

    static let placeholder = WidgetSnapshot(
        version: WidgetSnapshot.currentVersion,
        generatedAt: Date(),
        isPaired: false,
        partner: nil,
        mood: nil,
        nudge: nil,
        anniversary: nil,
        couplePhotoFilename: nil
    )
}

// MARK: - Partner

struct PartnerSnapshot: Codable, Equatable {
    var displayName: String
    var avatarFilename: String?
}

// MARK: - Mood

/// The widget keeps mood as a self-contained value — the source `Mood` enum
/// lives in the main-app domain and the widget process must not import it.
struct MoodSnapshot: Codable, Equatable {
    var kind: WidgetMoodKind
    var note: String?
    var updatedAt: Date

    /// Optional override label (e.g. "Missing You") set by the partner when
    /// the basic mood enum can't capture the feeling. Falls back to
    /// `kind.label` when nil or empty.
    var customLabel: String?
}

/// Mirror of the app's `Mood` enum, plus richer expressive variants. The
/// widget only ever decodes values it knows about — anything unknown
/// decodes to `.unspecified` so future writers can extend the schema
/// without breaking older readers.
enum WidgetMoodKind: String, Codable, CaseIterable {
    case happy
    case neutral
    case sad
    case stressed

    // Extended palette — written by future mood-picker UI
    case loved
    case missingYou
    case excited
    case tired
    case calm
    case unspecified

    var emoji: String {
        switch self {
        case .happy:      return "😊"
        case .neutral:    return "😐"
        case .sad:        return "😢"
        case .stressed:   return "😤"
        case .loved:      return "❤️"
        case .missingYou: return "💌"
        case .excited:    return "✨"
        case .tired:      return "😴"
        case .calm:       return "🌿"
        case .unspecified: return "💭"
        }
    }

    var label: String {
        switch self {
        case .happy:      return "Happy"
        case .neutral:    return "Okay"
        case .sad:        return "Down"
        case .stressed:   return "Stressed"
        case .loved:      return "In Love"
        case .missingYou: return "Missing You"
        case .excited:    return "Excited"
        case .tired:      return "Tired"
        case .calm:       return "Calm"
        case .unspecified: return "Thinking"
        }
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = WidgetMoodKind(rawValue: raw) ?? .unspecified
    }
}

// MARK: - Nudge

struct NudgeSnapshot: Codable, Equatable {
    var emoji: String
    var message: String
    var receivedAt: Date
}

// MARK: - Anniversary

/// Carries every anniversary the couple has set so the widget can decide
/// locally which one to surface (next-up vs. milestone). The "days
/// together" value comes from `relationshipStart`, which is always the
/// earliest anniversary date.
struct AnniversarySnapshot: Codable, Equatable {

    /// Earliest anniversary date — drives the "Together for X days" line
    /// and milestone detection. Nil when the user hasn't set any
    /// anniversaries yet.
    var relationshipStart: Date?

    /// All future-or-recent anniversaries the couple cares about. Sorted
    /// ascending by date. The widget walks this list to find the next
    /// one to display.
    var upcoming: [UpcomingAnniversary]
}

struct UpcomingAnniversary: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var date: Date
}
