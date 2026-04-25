//
//  OnboardingService.swift
//  Coupley
//
//  Persists onboarding answers to `/users/{uid}`. Two write modes:
//
//    1. `savePartial(_:)` — incremental writes after each step. Survives
//       app kills and lets a returning user resume mid-flow without losing
//       what they typed.
//    2. `complete(_:)` — terminal write, also stamps
//       `onboardingCompletedAt = serverTimestamp()` so the gating logic in
//       RootView (and any cross-device sync down the line) has one
//       authoritative flag.
//
//  Uses `setData(merge:)` everywhere so we never clobber unrelated fields
//  written by other parts of the app (premium, coupleId, partnerId, etc.).
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

// MARK: - Protocol

protocol OnboardingServiceProtocol {
    /// Save a partial profile — called between steps. Soft-fails: errors
    /// are logged but never bubbled up, since onboarding flow shouldn't
    /// break on a transient network blip.
    func savePartial(_ profile: OnboardingProfile, userId: String) async

    /// Final commit. Throws so the caller can hold the user on the paywall
    /// step if the network is genuinely down.
    func complete(_ profile: OnboardingProfile, userId: String) async throws

    /// One-shot: write the user's chosen first name to both
    /// `Auth.currentUser.displayName` and `/users/{uid}.displayName`. Called
    /// from the name step so the rest of the app picks it up immediately.
    func updateDisplayName(_ name: String, userId: String) async throws
}

// MARK: - Firestore Implementation

final class FirestoreOnboardingService: OnboardingServiceProtocol {

    private let db = Firestore.firestore()

    func savePartial(_ profile: OnboardingProfile, userId: String) async {
        let payload = serialize(profile, terminal: false)
        guard !payload.isEmpty else { return }
        do {
            try await db.collection(FirestorePath.users).document(userId)
                .setData(payload, merge: true)
        } catch {
            // Soft-fail. The next step will retry the same merge.
            print("[OnboardingService] Partial save failed: \(error.localizedDescription)")
        }
    }

    func complete(_ profile: OnboardingProfile, userId: String) async throws {
        var payload = serialize(profile, terminal: true)
        payload[OnboardingField.onboardingCompletedAt] = FieldValue.serverTimestamp()
        try await db.collection(FirestorePath.users).document(userId)
            .setData(payload, merge: true)
    }

    func updateDisplayName(_ name: String, userId: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        // Firebase Auth profile (used by other clients & .displayName reads)
        if let user = Auth.auth().currentUser {
            let req = user.createProfileChangeRequest()
            req.displayName = trimmed
            try await req.commitChanges()
        }

        // Firestore mirror (used by paired-partner views)
        try await db.collection(FirestorePath.users).document(userId)
            .setData(["displayName": trimmed], merge: true)
    }

    // MARK: - Serialization

    /// Build a Firestore payload from the profile. `terminal=true` includes
    /// every field the user touched; `false` skips empty/default fields so
    /// partial saves don't write garbage.
    private func serialize(_ profile: OnboardingProfile, terminal: Bool) -> [String: Any] {
        var out: [String: Any] = [:]

        let trimmedName = profile.firstName.trimmingCharacters(in: .whitespaces)
        if !trimmedName.isEmpty {
            out[OnboardingField.firstName] = trimmedName
            // Mirror to displayName so the rest of the app sees the chosen
            // name even before the explicit Auth.profileChange call lands.
            out["displayName"] = trimmedName
        }

        let trimmedPartner = profile.partnerName.trimmingCharacters(in: .whitespaces)
        if !trimmedPartner.isEmpty {
            out[OnboardingField.partnerName] = trimmedPartner
        }

        if let anniversary = profile.anniversary {
            out[OnboardingField.anniversary] = Timestamp(date: anniversary)
        }

        if !profile.goals.isEmpty {
            out[OnboardingField.goals] = profile.goals.map { $0.rawValue }.sorted()
        }

        if let style = profile.communicationStyle {
            out[OnboardingField.communicationStyle] = style.rawValue
        }

        // Reminder cadence: write even when "off" on the terminal write so
        // we capture an explicit choice. On partial writes only persist
        // non-default values to keep the doc tidy.
        if terminal || profile.reminderCadence != .daily {
            out[OnboardingField.reminderCadence] = profile.reminderCadence.rawValue
        }
        if terminal || profile.reminderHour != 20 {
            out[OnboardingField.reminderHour] = profile.reminderHour
        }
        if terminal || profile.moodCheckCadence != .once {
            out[OnboardingField.moodCheckCadence] = profile.moodCheckCadence.rawValue
        }

        if profile.notificationsEnabled {
            out[OnboardingField.notificationsEnabled] = true
        }
        if profile.widgetSuggestionAcknowledged {
            out[OnboardingField.widgetAcknowledged] = true
        }

        return out
    }
}

// MARK: - Mock

final class MockOnboardingService: OnboardingServiceProtocol {
    func savePartial(_ profile: OnboardingProfile, userId: String) async {}
    func complete(_ profile: OnboardingProfile, userId: String) async throws {}
    func updateDisplayName(_ name: String, userId: String) async throws {}
}
