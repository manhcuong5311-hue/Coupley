//
//  ProfileService.swift
//  Coupley
//
//  Created by Sam Manh Cuong on 1/4/26.
//

import Foundation

// MARK: - Profile Service Protocol

protocol ProfileService {
    func saveProfile(_ profile: PartnerProfile) async throws
    func loadProfile() async throws -> PartnerProfile?
    func updatePreference(
        category: QuestionCategory,
        values: [String],
        in profile: inout PartnerProfile
    )
}

// MARK: - Local Profile Service

final class LocalProfileService: ProfileService {

    private var storedProfile: PartnerProfile?

    func saveProfile(_ profile: PartnerProfile) async throws {
        try await Task.sleep(nanoseconds: 300_000_000)
        storedProfile = profile
    }

    func loadProfile() async throws -> PartnerProfile? {
        try await Task.sleep(nanoseconds: 200_000_000)
        return storedProfile
    }

    func updatePreference(
        category: QuestionCategory,
        values: [String],
        in profile: inout PartnerProfile
    ) {
        switch category {
        case .food:
            profile.preferences.favoriteFood = values

        case .drink:
            profile.preferences.favoriteDrink = values

        case .music:
            profile.preferences.favoriteMusic = values

        case .activities:
            profile.preferences.favoriteActivities = values

        case .color:
            profile.preferences.favoriteColor = values.first ?? ""

        case .loveLanguage:
            if let raw = values.first,
               let language = LoveLanguage.allCases.first(where: { raw.contains($0.label) }) {
                profile.personality.loveLanguage = language
            }

        case .stressBehavior:
            if let raw = values.first,
               let response = StressResponse.allCases.first(where: { raw.contains($0.label) }) {
                profile.personality.stressResponse = response
            }

        case .communicationStyle:
            if let raw = values.first,
               let style = CommunicationStyle.allCases.first(where: { raw.contains($0.label) }) {
                profile.personality.communicationStyle = style
            }
        }
    }
}

// MARK: - Future: Firebase Profile Service
//
// final class FirebaseProfileService: ProfileService {
//     func saveProfile(_ profile: PartnerProfile) async throws {
//         // Firestore: users/{uid}/partnerProfile
//     }
//     func loadProfile() async throws -> PartnerProfile? {
//         // Firestore read
//     }
//     func updatePreference(category:values:in:) { ... }
// }
