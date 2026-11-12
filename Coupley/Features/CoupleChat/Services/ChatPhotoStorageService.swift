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

    /// Resizes to fit `maxDimension` (never upscales) and encodes as JPEG.
    static func downscaledJPEG(_ image: UIImage, quality: CGFloat = 0.72) -> Data? {
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }

        let scale = min(1, maxDimension / longest)
        guard scale < 1 else { return image.jpegData(compressionQuality: quality) }

        let target = CGSize(width: (image.size.width * scale).rounded(),
                            height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1          // target is already in pixels
        format.opaque = true      // JPEG has no alpha; opaque avoids a blend pass
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }

    /// Longest edge an uploaded photo is allowed to keep.
    ///
    /// A modern iPhone shot is ~4000px and lands around 3–5 MB even at 0.75
    /// quality, and it was being uploaded at full size. Nothing in this app
    /// displays a photo larger than a phone screen: chat bubbles, Time Tree
    /// thumbnails and the daily-photo card are all a few hundred points wide.
    /// 1600px covers a full-screen view on the largest device with room to
    /// spare, and cuts a typical upload to roughly a tenth of the bytes —
    /// which is a tenth of the storage bill, the partner's download, and the
    /// time they wait looking at a spinner.
    static let maxDimension: CGFloat = 1600

    func upload(_ image: UIImage, coupleId: String, messageId: String) async throws -> String {
        guard let data = Self.downscaledJPEG(image) else {
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
