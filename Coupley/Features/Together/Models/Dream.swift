//
//  Dream.swift
//  Coupley
//
//  A future thing the couple wants — a place to go, a home to build, a pet,
//  a wedding, a baby. Distinct from goals because it's emotional rather than
//  measurable: there's no progress bar, just an inspiring card with a photo,
//  a timeframe, and a shared note.
//
//  The Dream Board is the "vision board" surface of Together. It is the most
//  premium-coded section by design — free users see *one* dream and a locked
//  shimmer overlay on the rest, which is the conversion lever.
//

import Foundation
import FirebaseFirestore

// MARK: - Dream Category

enum DreamCategory: String, Codable, CaseIterable, Identifiable {
    case travel
    case home
    case family
    case career
    case lifestyle
    case pet
    case other

    var id: String { rawValue }

    /// Display name only. Storage and comparisons use `rawValue`.
    var label: LocalizedStringResource {
        switch self {
        case .travel:    return LocalizedStringResource("Travel", comment: "Together tab: category of a shared goal, challenge or dream")
        case .home:
            // Own key: a plain "Home" key is the Home tab.
            return LocalizedStringResource(
                "together.category.home",
                defaultValue: "Home",
                comment: "Together tab: category of a shared goal or dream about a home or house (not the Home tab)"
            )
        case .family:    return LocalizedStringResource("Family", comment: "Together tab: category of a shared goal, challenge or dream")
        case .career:    return LocalizedStringResource("Career", comment: "Together tab: category of a shared goal, challenge or dream")
        case .lifestyle: return LocalizedStringResource("Lifestyle", comment: "Together tab: category of a shared goal, challenge or dream")
        case .pet:       return LocalizedStringResource("Pet", comment: "Together tab: category of a shared goal, challenge or dream")
        case .other:     return LocalizedStringResource("Other", comment: "Together tab: category of a shared goal, challenge or dream")
        }
    }

    var icon: String {
        switch self {
        case .travel:    return "airplane"
        case .home:      return "house.fill"
        case .family:    return "figure.2.and.child.holdinghands"
        case .career:    return "briefcase.fill"
        case .lifestyle: return "sparkles"
        case .pet:       return "pawprint.fill"
        case .other:     return "star.fill"
        }
    }

    var emoji: String {
        switch self {
        case .travel:    return "🌍"
        case .home:      return "🏡"
        case .family:    return "👶"
        case .career:    return "💼"
        case .lifestyle: return "✨"
        case .pet:       return "🐾"
        case .other:     return "💫"
        }
    }
}

// MARK: - Dream Horizon

/// Soft framing for when a dream is supposed to happen. Used for grouping and
/// for the "in 2 years" type chips on cards.
enum DreamHorizon: String, Codable, CaseIterable, Identifiable {
    case thisYear
    case nextYear
    case fiveYears
    case someday

    var id: String { rawValue }

    var label: LocalizedStringResource {
        switch self {
        case .thisYear:   return LocalizedStringResource("This Year", comment: "Dream timeframe option")
        case .nextYear:   return LocalizedStringResource("Next Year", comment: "Dream timeframe option")
        case .fiveYears:  return LocalizedStringResource("Within 5 Years", comment: "Dream timeframe option")
        case .someday:    return LocalizedStringResource("Someday", comment: "Dream timeframe: some day, no fixed date")
        }
    }

    /// Compact form for the chip on dream cards.
    var shortLabel: LocalizedStringResource {
        switch self {
        case .thisYear:   return LocalizedStringResource("This year", comment: "Dream timeframe chip on a dream card")
        case .nextYear:   return LocalizedStringResource("Next year", comment: "Dream timeframe chip on a dream card")
        case .fiveYears:  return LocalizedStringResource("5y", comment: "Dream timeframe chip: short for 'within 5 years'")
        case .someday:    return LocalizedStringResource("Someday", comment: "Dream timeframe: some day, no fixed date")
        }
    }
}

// MARK: - Dream

struct Dream: Identifiable, Codable, Equatable {
    @DocumentID var firestoreId: String?

    let id: String
    var title: String
    var category: DreamCategory
    var colorway: TogetherColorway
    var horizon: DreamHorizon

    /// Optional photo URL. The Firebase Storage upload happens through the
    /// existing TimeTreeStorageService (renamed paths) so we don't fork the
    /// upload pipeline. Premium-only.
    var photoURL: String?

    /// Free-form description — "the why" behind the dream.
    var note: String?

    /// Optional poetic line. Surfaced as the hero quote on the detail sheet.
    /// Helps cards read like a vision board rather than a task list.
    var inspiration: String?

    /// Optional "first step" the couple can take now. Bridges the gap from
    /// emotional dream to actionable goal. The detail sheet has a "Turn into a
    /// Goal" CTA that pre-fills a goal editor with this string.
    var firstStep: String?

    let createdBy: String
    let createdAt: Date
    var updatedAt: Date

    var documentId: String { firestoreId ?? id }
}

// MARK: - Dream Suggestions

/// Content bank. `title` and `inspiration` are base (English) text: the UI
/// shows them through `ContentL10n.text`, and picked text is saved in the
/// user's language as their own content.
struct DreamSuggestion: Identifiable {
    let id = UUID()
    let title: String
    let category: DreamCategory
    let horizon: DreamHorizon
    let inspiration: String
    let emoji: String

    static let library: [DreamSuggestion] = [
        DreamSuggestion(
            title: "Japan Together",
            category: .travel, horizon: .nextYear,
            inspiration: "Tokyo lights. Kyoto mornings. Cherry blossoms with you.",
            emoji: "🗾"
        ),
        DreamSuggestion(
            title: "Our First Home",
            category: .home, horizon: .fiveYears,
            inspiration: "A door with both our names. A kitchen we picked together.",
            emoji: "🏡"
        ),
        DreamSuggestion(
            title: "A Wedding",
            category: .family, horizon: .nextYear,
            inspiration: "The day we choose each other in front of everyone we love.",
            emoji: "💒"
        ),
        DreamSuggestion(
            title: "A Dog",
            category: .pet, horizon: .thisYear,
            inspiration: "Slow mornings, warm fur, three sets of footprints.",
            emoji: "🐕"
        ),
        DreamSuggestion(
            title: "A Cat",
            category: .pet, horizon: .thisYear,
            inspiration: "A small, furry tyrant we'd happily serve.",
            emoji: "🐈"
        ),
        DreamSuggestion(
            title: "Couple Business",
            category: .career, horizon: .fiveYears,
            inspiration: "The thing we make together that's bigger than either of us.",
            emoji: "💼"
        ),
        DreamSuggestion(
            title: "Italy Roadtrip",
            category: .travel, horizon: .fiveYears,
            inspiration: "Coastline. Pasta. Two weeks of sunset light.",
            emoji: "🇮🇹"
        ),
        DreamSuggestion(
            title: "Baby Future",
            category: .family, horizon: .someday,
            inspiration: "When we're ready. Whatever shape that takes.",
            emoji: "👶"
        ),
        DreamSuggestion(
            title: "Move to the Coast",
            category: .lifestyle, horizon: .fiveYears,
            inspiration: "Salt air. Slower mornings. The sound of waves at night.",
            emoji: "🌊"
        )
    ]
}

#if DEBUG
extension DreamSuggestion {
    /// Every base string the UI shows through ContentL10n (to build the Content catalog).
    static var l10nContentStrings: [String] {
        library.flatMap { [$0.title, $0.inspiration] }
    }
}
#endif
