//
//  DailyLimitAlert.swift
//  Coupley
//
//  Shown when a fair-use daily limit (AI suggestions, AI Coach, date ideas)
//  is used up. Replaces the old "upgrade to Premium" paywall.
//

import SwiftUI

extension PremiumFeature {
    /// The limit message, one whole sentence per feature so each language can
    /// word it its own way.
    var dailyLimitMessage: LocalizedStringResource {
        switch self {
        case .aiMoodSuggestions:
            return "You've used all of today's AI suggestions. They reset tomorrow."
        case .aiCoach:
            return "You've used all of today's AI Coach sessions. They reset tomorrow."
        case .dateIdeas:
            return "You've used all of today's date ideas. They reset tomorrow."
        default:
            return "You've used all of today's uses. They reset tomorrow."
        }
    }
}

extension View {
    /// Presents "Daily limit reached" while `feature` is non-nil.
    func dailyLimitAlert(_ feature: Binding<PremiumFeature?>) -> some View {
        alert(
            "Daily limit reached",
            isPresented: Binding(
                get: { feature.wrappedValue != nil },
                set: { if !$0 { feature.wrappedValue = nil } }
            ),
            presenting: feature.wrappedValue
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { feature in
            Text(feature.dailyLimitMessage)
        }
    }
}
