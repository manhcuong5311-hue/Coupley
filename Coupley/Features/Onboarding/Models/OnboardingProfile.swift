//
//  OnboardingProfile.swift
//  Coupley
//
//  All data the user supplies during the post-login onboarding flow.
//  Persists to:
//    • In-memory `OnboardingViewModel.profile` while flowing through the steps
//    • `/users/{uid}` on partial save (after each step) and a final commit
//      with `onboardingCompletedAt` once the paywall is dismissed.
//
//  Designed so each field is optional — users can skip Partner, Anniversary,
//  or any preference, and we just don't write that field. This keeps the
//  Firestore document clean for users who only filled in the bare minimum.
//

import Foundation

// MARK: - Onboarding Communication Style
//
// Distinct from the AI-Suggestion `CommunicationStyle` (introvert / expressive
// / avoidant), which describes how a partner *behaves*. This one is the tone
// the user wants Coupley to use when nudging them.

enum OnboardingCommunicationStyle: String, CaseIterable, Identifiable, Codable {
    case affectionate
    case playful
    case direct
    case thoughtful

    var id: String { rawValue }

    var label: String {
        switch self {
        case .affectionate: return "Warm & affectionate"
        case .playful:      return "Playful & teasing"
        case .direct:       return "Honest & direct"
        case .thoughtful:   return "Thoughtful & deep"
        }
    }

    var blurb: String {
        switch self {
        case .affectionate: return "Lots of \"I love you\" — sweet check-ins."
        case .playful:      return "Inside jokes and silly nudges."
        case .direct:       return "Clear, honest, no-fuss."
        case .thoughtful:   return "Slow, deeper conversations."
        }
    }

    var icon: String {
        switch self {
        case .affectionate: return "heart.fill"
        case .playful:      return "face.smiling.fill"
        case .direct:       return "bubble.left.and.bubble.right.fill"
        case .thoughtful:   return "moon.stars.fill"
        }
    }
}

// MARK: - Relationship Goal

enum RelationshipGoal: String, CaseIterable, Identifiable, Codable {
    case feelCloser
    case communicateBetter
    case rememberDates
    case haveMoreFun
    case understandEmotions
    case buildHabits

    var id: String { rawValue }

    var label: String {
        switch self {
        case .feelCloser:        return "Feel closer every day"
        case .communicateBetter: return "Communicate better"
        case .rememberDates:     return "Never forget the moments"
        case .haveMoreFun:       return "Have more fun together"
        case .understandEmotions:return "Understand each other emotionally"
        case .buildHabits:       return "Build healthy daily habits"
        }
    }

    var icon: String {
        switch self {
        case .feelCloser:         return "heart.circle.fill"
        case .communicateBetter:  return "bubble.left.and.bubble.right.fill"
        case .rememberDates:      return "calendar.badge.clock"
        case .haveMoreFun:        return "sparkles"
        case .understandEmotions: return "face.smiling.inverse"
        case .buildHabits:        return "chart.line.uptrend.xyaxis"
        }
    }
}

// MARK: - Reminder Cadence

enum ReminderCadence: String, CaseIterable, Identifiable, Codable {
    case off
    case daily
    case weekdays
    case weekly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off:      return "Off"
        case .daily:    return "Every day"
        case .weekdays: return "Weekdays"
        case .weekly:   return "Weekly"
        }
    }
}

// MARK: - Mood Check Cadence

enum MoodCheckCadence: String, CaseIterable, Identifiable, Codable {
    case off
    case once
    case twice

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off:   return "I'll log when I want to"
        case .once:  return "Once a day"
        case .twice: return "Twice a day"
        }
    }

    var blurb: String {
        switch self {
        case .off:   return "No nudges. You're in control."
        case .once:  return "A gentle ping each evening."
        case .twice: return "Morning + evening check-ins."
        }
    }
}

// MARK: - Profile

/// Every onboarding-collected field. All optional so partial onboarding is
/// supported (e.g. user skips partner name) and the doc never carries blank
/// strings.
struct OnboardingProfile: Equatable {

    var firstName: String = ""
    var partnerName: String = ""
    var anniversary: Date? = nil

    var goals: Set<RelationshipGoal> = []
    var communicationStyle: OnboardingCommunicationStyle? = nil

    var reminderCadence: ReminderCadence = .daily
    var reminderHour: Int = 20            // 8pm default
    var moodCheckCadence: MoodCheckCadence = .once

    var notificationsEnabled: Bool = false  // toggled true after system prompt
    var widgetSuggestionAcknowledged: Bool = false

    /// True if the firstName field has at least one non-whitespace char.
    var hasName: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

// MARK: - Firestore Field Constants

/// Single source of truth for onboarding-related Firestore field names.
/// Keep in sync with the cloud function and Firestore rules. Lower-camel-
/// case to match the rest of the user-doc schema.
enum OnboardingField {
    static let firstName              = "firstName"
    static let partnerName            = "partnerName"
    static let anniversary            = "anniversary"
    static let goals                  = "relationshipGoals"
    static let communicationStyle     = "communicationStyle"
    static let reminderCadence        = "reminderCadence"
    static let reminderHour           = "reminderHour"
    static let moodCheckCadence       = "moodCheckCadence"
    static let notificationsEnabled   = "notificationsEnabled"
    static let widgetAcknowledged     = "widgetSuggestionAcknowledged"
    static let onboardingCompletedAt  = "onboardingCompletedAt"
}
