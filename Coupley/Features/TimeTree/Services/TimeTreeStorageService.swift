//
//  TimeTreeStorageService.swift
//  Coupley
//
//  Uploads and deletes memory photos in Firebase Storage. Storage path:
//  couples/{coupleId}/memories/{memoryId}/photo.jpg.
//

import Foundation
import FirebaseStorage
import UIKit

// MARK: - Storage Service

final class TimeTreeStorageService {

    private let storage = Storage.storage()

    // MARK: - Upload

    func uploadPhoto(
        _ image: UIImage,
        coupleId: String,
        memoryId: String
    ) async throws -> String {
        // Was `image.jpegData(compressionQuality: 0.80)` on the picker's
        // full-resolution image. A modern iPhone shot is ~4000px and lands
        // at several MB that way -- a large one can exceed the 10 MB ceiling
        // in storage.rules and be rejected outright. Nothing in this app
        // renders a memory photo larger than a phone screen, and the chat
        // uploader already solved this; its helper's own doc comment names
        // Time Tree as a caller.
        guard let data = ChatPhotoStorageService.downscaledJPEG(image) else {
            throw TimeTreeStorageError.encodingFailed
        }
        let ref = photoRef(coupleId: coupleId, memoryId: memoryId)
        let meta = StorageMetadata()
        meta.contentType = "image/jpeg"

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            ref.putData(data, metadata: meta) { _, error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume() }
            }
        }

        let url = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            ref.downloadURL { url, error in
                if let error { cont.resume(throwing: error) }
                else if let url { cont.resume(returning: url) }
                else { cont.resume(throwing: TimeTreeStorageError.noDownloadURL) }
            }
        }
        return url.absoluteString
    }

    // MARK: - Delete

    func deletePhoto(coupleId: String, memoryId: String) async {
        let ref = photoRef(coupleId: coupleId, memoryId: memoryId)
        try? await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            ref.delete { error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume() }
            }
        }
    }

    // MARK: - Private

    private func photoRef(coupleId: String, memoryId: String) -> StorageReference {
        storage.reference()
            .child("couples/\(coupleId)/memories/\(memoryId)/photo.jpg")
    }
}

// MARK: - Errors

enum TimeTreeStorageError: LocalizedError {
    case encodingFailed
    case noDownloadURL

    var errorDescription: String? {
        switch self {
        case .encodingFailed: return "Could not encode the image."
        case .noDownloadURL:  return "Upload succeeded but no download URL was returned."
        }
    }
}
