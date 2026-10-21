//
//  DailyLimitAlert.swift
//  Coupley
//
//  Shown when a fair-use daily limit (AI suggestions, AI Coach, date ideas)
//  is used up. Replaces the old "upgrade to Premium" paywall.
//

import SwiftUI

extension PremiumFeature {
    /// Plural noun used in the limit message.
    var dailyLimitName: String {
        switch self {
        case .aiMoodSuggestions: return "AI suggestions"
        case .aiCoach:           return "AI Coach sessions"
        case .dateIdeas:         return "date ideas"
        default:                 return "uses"
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
            Text("You've used all of today's \(feature.dailyLimitName). They reset tomorrow.")
        }
    }
}
