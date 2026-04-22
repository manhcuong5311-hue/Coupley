//
//  ChatPhotoStorageService.swift
//  Coupley
//
//  Uploads chat photos to Firebase Storage.
//  Path: couples/{coupleId}/chat-photos/{messageId}.jpg
//

import Foundation
import FirebaseStorage
import UIKit

final class ChatPhotoStorageService {

    private let storage = Storage.storage()

    func upload(_ image: UIImage, coupleId: String, messageId: String) async throws -> String {
        guard let data = image.jpegData(compressionQuality: 0.75) else {
            throw ChatPhotoError.encodingFailed
        }
        let ref = storage.reference()
            .child("couples/\(coupleId)/chat-photos/\(messageId).jpg")
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
                else { cont.resume(throwing: ChatPhotoError.noDownloadURL) }
            }
        }
        return url.absoluteString
    }
}

enum ChatPhotoError: LocalizedError {
    case encodingFailed
    case noDownloadURL

    var errorDescription: String? {
        switch self {
        case .encodingFailed:  return "Could not encode the image."
        case .noDownloadURL:   return "Upload succeeded but no download URL returned."
        }
    }
}
