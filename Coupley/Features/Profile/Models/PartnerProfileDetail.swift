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
        updatedAt: Date
    ) {
        self.userId = userId
        self.likes = likes
        self.dislikes = dislikes
        self.communicationStyle = communicationStyle
        self.notes = notes
        self.activities = activities
        self.updatedAt = updatedAt
    }

    func firestorePayload() -> [String: Any] {
        [
            "likes": likes,
            "dislikes": dislikes,
            "communicationStyle": communicationStyle,
            "notes": notes,
            "activities": activities,
            "profileUpdatedAt": FieldValue.serverTimestamp()
        ]
    }
}
