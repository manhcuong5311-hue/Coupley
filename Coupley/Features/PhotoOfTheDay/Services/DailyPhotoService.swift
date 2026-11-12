//
//  DailyPhotoService.swift
//  Coupley
//
//  Creates the day's photo prompt and collects both submissions.
//
//  Images reuse the existing `couples/{id}/chat-photos/` bucket path rather
//  than getting their own: the storage rules already cover it for couple
//  members, and a daily photo is the same kind of object with the same
//  audience. The filename is prefixed so the two are still tellable apart.
//

import Foundation
import UIKit
import FirebaseFirestore

protocol DailyPhotoServicing {
    func observeCurrent(
        coupleId: String,
        onUpdate: @escaping (DailyPhoto?) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration

    @discardableResult
    func ensureCurrentPrompt(coupleId: String) async throws -> Bool

    func submit(_ image: UIImage, coupleId: String, photoId: String, userId: String) async throws
}

final class FirestoreDailyPhotoService: DailyPhotoServicing {

    /// Mirrors the question of the day: a new prompt is due 20h after the
    /// last, and an untouched one is held longer rather than replaced daily.
    static let refreshInterval: TimeInterval = 20 * 3600
    static let staleUnusedInterval: TimeInterval = 72 * 3600

    private let db = Firestore.firestore()
    private let photoStorage = ChatPhotoStorageService()

    private func collection(_ coupleId: String) -> CollectionReference {
        db.collection(FirestorePath.couples).document(coupleId).collection("photoOfDay")
    }

    // MARK: - Observe

    func observeCurrent(
        coupleId: String,
        onUpdate: @escaping (DailyPhoto?) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        collection(coupleId)
            .order(by: "createdAt", descending: true)
            .limit(to: 1)
            .addSnapshotListener { snapshot, error in
                if let error { onError(error); return }
                onUpdate(snapshot?.documents.compactMap { try? $0.data(as: DailyPhoto.self) }.first)
            }
    }

    // MARK: - Create

    @discardableResult
    func ensureCurrentPrompt(coupleId: String) async throws -> Bool {
        guard !coupleId.isEmpty else { return false }
        let coupleRef = db.collection(FirestorePath.couples).document(coupleId)

        let created = try await db.runTransaction { transaction, errorPointer -> Any? in
            do {
                let snap = try transaction.getDocument(coupleRef)
                let data = snap.data() ?? [:]

                let lastAt    = (data["potdLastCreatedAt"] as? Timestamp)?.dateValue()
                let lastId    = data["potdCurrentId"] as? String
                let sequence  = (data["potdSequence"] as? Int ?? 0) + 1

                var previous: DailyPhoto?
                if let lastId {
                    let ref = self.collection(coupleId).document(lastId)
                    previous = try? transaction.getDocument(ref).data(as: DailyPhoto.self)
                }

                guard Self.isPromptDue(lastCreatedAt: lastAt, previous: previous) else {
                    return false
                }
                guard let prompt = DailyPhotoPrompts.prompt(coupleId: coupleId, sequence: sequence) else {
                    return false
                }

                let photoId = "potd-\(sequence)"
                let photo = DailyPhoto(
                    id: photoId,
                    prompt: prompt,
                    createdAt: Date(),
                    photos: [:]
                )
                try transaction.setData(from: photo,
                                        forDocument: self.collection(coupleId).document(photoId))
                transaction.setData([
                    "potdSequence":      sequence,
                    "potdCurrentId":     photoId,
                    "potdLastCreatedAt": FieldValue.serverTimestamp()
                ], forDocument: coupleRef, merge: true)
                return true
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }
        }
        return (created as? Bool) ?? false
    }

    static func isPromptDue(lastCreatedAt: Date?, previous: DailyPhoto?) -> Bool {
        guard let lastCreatedAt else { return true }
        let age = Date().timeIntervalSince(lastCreatedAt)
        guard age >= refreshInterval else { return false }
        if let previous, !previous.photos.isEmpty { return true }
        return age >= staleUnusedInterval
    }

    // MARK: - Submit

    func submit(_ image: UIImage, coupleId: String, photoId: String, userId: String) async throws {
        // Read before spending an upload: if this user already answered this
        // prompt there is nothing to do, and the expensive part (the Storage
        // write) must not happen at all.
        let existing = try? await collection(coupleId).document(photoId).getDocument()
        if let photos = existing?.data()?["photos"] as? [String: String],
           photos[userId] != nil {
            return
        }

        let url = try await photoStorage.upload(
            image,
            coupleId: coupleId,
            messageId: "potd-\(photoId)-\(userId)"
        )
        try await collection(coupleId).document(photoId).setData(
            ["photos": [userId: url]], merge: true
        )
    }
}
