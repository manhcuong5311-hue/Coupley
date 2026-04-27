//
//  PartnerProfileDetail.swift
//  Coupley
//
//  Data model for the "Partner & Me" profile feature — likes, dislikes,
//  communication style, free-form notes, and shared activities. Persists
//  on the user document and syncs between partners.
//

import Foundation
import FirebaseFirestore

// MARK: - Profile Detail Model

struct PartnerProfileDetail: Equatable {
    var userId: String
    var likes: [String]
    var dislikes: [String]
    var communicationStyle: String
    var notes: String
    var activities: [String]

    /// Per-entry attribution: maps each chip value → the userId that added it.
    /// Missing key means legacy entry — treated as added by the profile owner
    /// (`userId`) for display purposes. Allows the partner to contribute
    /// hints to the *other* user's profile and still attribute them correctly.
    var likesAddedBy: [String: String]
    var dislikesAddedBy: [String: String]
    var activitiesAddedBy: [String: String]

    var updatedAt: Date

    var isEmpty: Bool {
        likes.isEmpty
        && dislikes.isEmpty
        && communicationStyle.isEmpty
        && notes.isEmpty
        && activities.isEmpty
    }

    static func empty(userId: String) -> PartnerProfileDetail {
        PartnerProfileDetail(
            userId: userId,
            likes: [],
            dislikes: [],
            communicationStyle: "",
            notes: "",
            activities: [],
            likesAddedBy: [:],
            dislikesAddedBy: [:],
            activitiesAddedBy: [:],
            updatedAt: .distantPast
        )
    }

    // MARK: - Firestore Mapping

    init(userId: String, data: [String: Any]) {
        self.userId = userId
        self.likes              = (data["likes"] as? [String]) ?? []
        self.dislikes           = (data["dislikes"] as? [String]) ?? []
        self.communicationStyle = (data["communicationStyle"] as? String) ?? ""
        self.notes              = (data["notes"] as? String) ?? ""
        self.activities         = (data["activities"] as? [String]) ?? []
        self.likesAddedBy       = (data["likesAddedBy"]      as? [String: String]) ?? [:]
        self.dislikesAddedBy    = (data["dislikesAddedBy"]   as? [String: String]) ?? [:]
        self.activitiesAddedBy  = (data["activitiesAddedBy"] as? [String: String]) ?? [:]
        // The legacy `customAnswers` field on existing user docs is now
        // ignored. The new Custom Quiz lives in the chat thread under
        // /couples/{id}/quizzes (see ChatQuiz). No migration needed — old
        // entries simply stop rendering on the profile.
        if let ts = data["profileUpdatedAt"] as? Timestamp {
            self.updatedAt = ts.dateValue()
        } else {
            self.updatedAt = .distantPast
        }
    }

    init(
        userId: String,
        likes: [String],
        dislikes: [String],
        communicationStyle: String,
        notes: String,
        activities: [String],
        likesAddedBy: [String: String] = [:],
        dislikesAddedBy: [String: String] = [:],
        activitiesAddedBy: [String: String] = [:],
        updatedAt: Date
    ) {
        self.userId = userId
        self.likes = likes
        self.dislikes = dislikes
        self.communicationStyle = communicationStyle
        self.notes = notes
        self.activities = activities
        self.likesAddedBy = likesAddedBy
        self.dislikesAddedBy = dislikesAddedBy
        self.activitiesAddedBy = activitiesAddedBy
        self.updatedAt = updatedAt
    }

    func firestorePayload() -> [String: Any] {
        [
            "likes": likes,
            "dislikes": dislikes,
            "communicationStyle": communicationStyle,
            "notes": notes,
            "activities": activities,
            "likesAddedBy": likesAddedBy,
            "dislikesAddedBy": dislikesAddedBy,
            "activitiesAddedBy": activitiesAddedBy,
            "profileUpdatedAt": FieldValue.serverTimestamp()
        ]
    }
}
