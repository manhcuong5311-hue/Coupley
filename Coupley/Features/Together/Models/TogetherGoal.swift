//
//  TogetherGoal.swift
//  Coupley
//
//  A shared goal a couple is actively working toward. Goals are couple-scoped
//  (live under couples/{id}/togetherGoals) and shared by both partners. Two
//  flavors share the same shape because the UI for them is otherwise nearly
//  identical:
//    • progress goals (target = number of completed checkpoints)
//    • savings goals  (target = money amount, contributions = currency)
//
//  Free users get 2 active goals. Premium gets unlimited. The store enforces
//  this at write time; the UI renders the lock state from `PremiumStore.hasAccess`.
//

import Foundation
import FirebaseFirestore

// MARK: - Goal Category

enum GoalCategory: String, Codable, CaseIterable, Identifiable {
    case travel
    case savings
    case wedding
    case home
    case lifestyle
    case health
    case gratitude
    case learning
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .travel:    return "Travel"
        case .savings:   return "Savings"
        case .wedding:   return "Wedding"
        case .home:      return "Home"
        case .lifestyle: return "Lifestyle"
        case .health:    return "Health"
        case .gratitude: return "Gratitude"
        case .learning:  return "Learning"
        case .other:     return "Other"
        }
    }

    var icon: String {
        switch self {
        case .travel:    return "airplane"
        case .savings:   return "banknote"
        case .wedding:   return "heart.fill"
        case .home:      return "house.fill"
        case .lifestyle: return "sparkles"
        case .health:    return "figure.walk"
        case .gratitude: return "leaf.fill"
        case .learning:  return "book.fill"
        case .other:     return "star.fill"
        }
    }

    /// Emoji used inline in copy and notification bodies. Kept distinct from
    /// the SF Symbol icon so cards can render both elegantly.
    var emoji: String {
        switch self {
        case .travel:    return "✈️"
        case .savings:   return "💰"
        case .wedding:   return "💍"
        case .home:      return "🏠"
        case .lifestyle: return "✨"
        case .health:    return "💪"
        case .gratitude: return "🌿"
        case .learning:  return "📚"
        case .other:     return "🌟"
        }
    }

    /// Whether goals in this category default to currency tracking.
    /// (Drives the editor toggle and the units shown in progress UI.)
    var defaultIsFinancial: Bool {
        switch self {
        case .savings, .wedding, .travel, .home: return true
        default: return false
        }
    }
}

// MARK: - Goal Tracking Mode

/// `count` goals tally completed checkpoints (e.g. "14 / 20 days").
/// `currency` goals tally money toward a target. The exact symbol is driven by
/// the goal's stored `currencyCode` (USD → "$5,000", VND → "5.000 ₫").
/// We keep both code paths in one model because every other field is shared.
enum GoalTrackingMode: String, Codable, CaseIterable {
    case count
    case currency

    var unitsLabel: String {
        switch self {
        case .count:    return "steps"
        case .currency: return "saved"
        }
    }
}

// MARK: - Together Goal

struct TogetherGoal: Identifiable, Codable, Equatable {
    @DocumentID var firestoreId: String?

    let id: String
    var title: String
    var category: GoalCategory
    var colorway: TogetherColorway
    var trackingMode: GoalTrackingMode

    /// Target value in whatever the tracking mode dictates. Counts are integers
    /// stored as doubles so the same field works for both modes.
    var target: Double

    /// ISO 4217 code chosen at create time. Locked into the document so both
    /// partners always see the same currency for a shared goal — independent
    /// of either viewer's device locale. Editable from the goal editor.
    /// Ignored when `trackingMode == .count`.
    var currencyCode: String

    var contribution: TogetherContribution

    /// Optional milestone date — when set, the card renders an "estimated
    /// completion" line and the AI coach knows how to pace recommendations.
    var dueDate: Date?

    /// Free-form note shared by both partners. Used as the description on the
    /// detail sheet.
    var note: String?

    let createdBy: String
    let createdAt: Date
    var updatedAt: Date

    /// Set when the goal is fully reached or otherwise wrapped up. Archived
    /// goals stop appearing in the active section but live on for history.
    var completedAt: Date?

    var documentId: String { firestoreId ?? id }

    // MARK: - Derived

    /// 0...1 progress against the target. Caps at 1 so completed goals don't
    /// render bars that overflow.
    var progress: Double {
        guard target > 0 else { return 0 }
        return min(1.0, contribution.total / target)
    }

    var isComplete: Bool {
        completedAt != nil || progress >= 1.0
    }

    static let countFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    /// Resolved currency metadata for `.currency` goals. Falls back to USD if
    /// the stored code isn't in the catalog (legacy data, future codes, etc.).
    var currencyInfo: CurrencyInfo {
        CurrencyCatalog.info(for: currencyCode)
    }

    func formatAmount(_ value: Double) -> String {
        switch trackingMode {
        case .currency:
            return CurrencyFormatting.format(value, code: currencyCode)
        case .count:
            return Self.countFormatter.string(from: NSNumber(value: value)) ?? "0"
        }
    }

    var progressLabel: String {
        "\(formatAmount(contribution.total)) / \(formatAmount(target))"
    }

    /// Estimated completion based on contribution velocity. Returns `nil` when
    /// there's not enough history to project, which the UI hides gracefully.
    func estimatedCompletion(now: Date = Date()) -> Date? {
        guard !isComplete, target > 0, contribution.total > 0 else { return nil }
        let secondsSinceStart = now.timeIntervalSince(createdAt)
        guard secondsSinceStart > 60 * 60 * 24 else { return nil }
        let perSecond = contribution.total / secondsSinceStart
        guard perSecond > 0 else { return nil }
        let remaining = target - contribution.total
        let secondsLeft = remaining / perSecond
        guard secondsLeft.isFinite, secondsLeft > 0 else { return nil }
        return now.addingTimeInterval(secondsLeft)
    }
}

// MARK: - Sample Suggestions

/// Curated prompts shown in the editor's "Quick Start" tray. New users almost
/// never want to type a goal name from scratch — having one tap pre-fill the
/// editor with a known-good shape is the difference between empty-state and
/// engagement.
struct GoalSuggestion: Identifiable {
    let id = UUID()
    let title: String
    let category: GoalCategory
    let trackingMode: GoalTrackingMode
    let target: Double
    let emoji: String

    static let library: [GoalSuggestion] = [
        GoalSuggestion(title: "Japan Trip Fund",     category: .travel,    trackingMode: .currency, target: 5000, emoji: "✈️"),
        GoalSuggestion(title: "Wedding Savings",     category: .wedding,   trackingMode: .currency, target: 25000, emoji: "💍"),
        GoalSuggestion(title: "New Apartment Fund",  category: .home,      trackingMode: .currency, target: 8000,  emoji: "🏠"),
        GoalSuggestion(title: "Emergency Fund",      category: .savings,   trackingMode: .currency, target: 3000,  emoji: "🛟"),
        GoalSuggestion(title: "Anniversary Trip",    category: .travel,    trackingMode: .currency, target: 2000,  emoji: "🌅"),
        GoalSuggestion(title: "30 Days Gratitude",   category: .gratitude, trackingMode: .count,    target: 30,    emoji: "🌿"),
        GoalSuggestion(title: "Gym Together",        category: .health,    trackingMode: .count,    target: 20,    emoji: "💪"),
        GoalSuggestion(title: "Weekly Date Night",   category: .lifestyle, trackingMode: .count,    target: 12,    emoji: "🍷"),
        GoalSuggestion(title: "Reading Challenge",   category: .learning,  trackingMode: .count,    target: 6,     emoji: "📚")
    ]
}
