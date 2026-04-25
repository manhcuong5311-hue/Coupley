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

// MARK: - Custom Quiz Answer

/// A user-authored quiz captured on the profile: a custom question, the options
/// the user defined, and the subset they chose as their own answer. Shown as a
/// Q&A card on the profile. Created behind the `customQuizzes` premium gate.
struct CustomQuizAnswer: Equatable, Identifiable {
    let id: String
    var question: String
    var options: [String]
    var selectedOptions: [String]
    var createdBy: String
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        question: String,
        options: [String],
        selectedOptions: [String],
        createdBy: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.question = question
        self.options = options
        self.selectedOptions = selectedOptions
        self.createdBy = createdBy
        self.createdAt = createdAt
    }

    init?(dict: [String: Any]) {
        guard let id = dict["id"] as? String,
              let question = dict["question"] as? String,
              let options = dict["options"] as? [String] else { return nil }
        self.id = id
        self.question = question
        self.options = options
        self.selectedOptions = (dict["selectedOptions"] as? [String]) ?? []
        self.createdBy = (dict["createdBy"] as? String) ?? ""
        if let ts = dict["createdAt"] as? Timestamp {
            self.createdAt = ts.dateValue()
        } else if let date = dict["createdAt"] as? Date {
            self.createdAt = date
        } else {
            self.createdAt = Date()
        }
    }

    func dictionary() -> [String: Any] {
        [
            "id": id,
            "question": question,
            "options": options,
            "selectedOptions": selectedOptions,
            "createdBy": createdBy,
            "createdAt": Timestamp(date: createdAt)
        ]
    }
}

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

    /// User-authored Q&A entries (premium). Owner-only — partner can't add or
    /// remove these because they're personal reflections rather than hints.
    var customAnswers: [CustomQuizAnswer]

    var updatedAt: Date

    var isEmpty: Bool {
        likes.isEmpty
        && dislikes.isEmpty
        && communicationStyle.isEmpty
        && notes.isEmpty
        && activities.isEmpty
        && customAnswers.isEmpty
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
            customAnswers: [],
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
        let rawCustom = (data["customAnswers"] as? [[String: Any]]) ?? []
        self.customAnswers      = rawCustom.compactMap { CustomQuizAnswer(dict: $0) }
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
        customAnswers: [CustomQuizAnswer] = [],
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
        self.customAnswers = customAnswers
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
            "customAnswers": customAnswers.map { $0.dictionary() },
            "profileUpdatedAt": FieldValue.serverTimestamp()
        ]
    }
}
