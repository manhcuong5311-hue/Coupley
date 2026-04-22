//
//  AnniversaryStorageService.swift
//  Coupley
//

import Foundation
import FirebaseStorage
import UIKit

// MARK: - Anniversary Storage Service

/// Handles uploading and deleting anniversary cover images in Firebase Storage.
/// Storage path: couples/{coupleId}/anniversaries/{anniversaryId}/cover.jpg
final class AnniversaryStorageService {

    private let storage = Storage.storage()

    // MARK: - Upload

    func uploadCover(
        _ image: UIImage,
        coupleId: String,
        anniversaryId: String
    ) async throws -> String {
        guard let data = image.jpegData(compressionQuality: 0.80) else {
            throw AnniversaryStorageError.encodingFailed
        }
        let ref = coverRef(coupleId: coupleId, anniversaryId: anniversaryId)
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
                else { cont.resume(throwing: AnniversaryStorageError.noDownloadURL) }
            }
        }
        return url.absoluteString
    }

    // MARK: - Delete

    func deleteCover(coupleId: String, anniversaryId: String) async {
        let ref = coverRef(coupleId: coupleId, anniversaryId: anniversaryId)
        try? await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            ref.delete { error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume() }
            }
        }
    }

    // MARK: - Private

    private func coverRef(coupleId: String, anniversaryId: String) -> StorageReference {
        storage.reference()
            .child("couples/\(coupleId)/anniversaries/\(anniversaryId)/cover.jpg")
    }
}

// MARK: - Errors

enum AnniversaryStorageError: LocalizedError {
    case encodingFailed
    case noDownloadURL

    var errorDescription: String? {
        switch self {
        case .encodingFailed:  return "Could not encode the image."
        case .noDownloadURL:   return "Upload succeeded but no download URL was returned."
        }
    }
}
