//
//  TimeTreeStorageService.swift
//  Coupley
//
//  Uploads and deletes memory photos in Firebase Storage.
//
//  Every upload gets its own file, couples/{coupleId}/memories/{memoryId}/
//  photo-<UUID>.jpg, so a replaced photo has a new download URL: caches keyed
//  by URL can never keep showing the old picture, and the old file can be
//  removed only after the memory document points at the new one. Earlier
//  versions wrote every photo to .../photo.jpg (the "legacy" path), which is
//  still deleted alongside.
//

import Foundation
import FirebaseStorage
import UIKit

// MARK: - Uploaded photo

/// What an upload produced: the download URL to store on the memory, and the
/// exact JPEG bytes that were sent, so the image cache can keep them as-is
/// instead of re-encoding the original on the main thread.
struct UploadedMemoryPhoto {
    let url: String
    let jpegData: Data
}

// MARK: - Storage Service

final class TimeTreeStorageService {

    /// `Storage.storage()` with uploads that give up after 30 s instead of
    /// the SDK's 10 minutes, so an offline photo fails fast with a message
    /// rather than holding the Save button. Configured once per process (the
    /// instance is shared, so other uploaders get the same limit).
    private static let configuredStorage: Storage = {
        let storage = Storage.storage()
        storage.maxUploadRetryTime = 30
        return storage
    }()

    private let storage = TimeTreeStorageService.configuredStorage

    // MARK: - Upload

    func uploadPhoto(
        _ image: UIImage,
        coupleId: String,
        memoryId: String
    ) async throws -> UploadedMemoryPhoto {
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
        let ref = storage.reference()
            .child(Self.folder(coupleId: coupleId, memoryId: memoryId) + "photo-\(UUID().uuidString).jpg")
        let meta = StorageMetadata()
        meta.contentType = "image/jpeg"

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            ref.putData(data, metadata: meta) { _, error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume() }
            }
        }

        let url: URL
        do {
            url = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
                ref.downloadURL { url, error in
                    if let error { cont.resume(throwing: error) }
                    else if let url { cont.resume(returning: url) }
                    else { cont.resume(throwing: TimeTreeStorageError.noDownloadURL) }
                }
            }
        } catch {
            // Nothing will ever point at a file whose URL never came back,
            // and its name is random: remove it. Not awaited: offline the
            // delete retries for about two minutes, and the user shouldn't
            // wait for it. What it misses goes with the memory's folder
            // (onMemoryDeleted, and the purge on disconnect).
            ref.delete { _ in }
            throw error
        }
        return UploadedMemoryPhoto(url: url.absoluteString, jpegData: data)
    }

    // MARK: - Delete

    /// Deletes the photo file a memory's `photoURL` points at. The object
    /// path is read from the download URL itself and must lie inside this
    /// memory's own folder; anything else (a foreign or malformed URL) falls
    /// back to the legacy photo.jpg path. Failures are ignored: a missing
    /// file is already the goal, and a stray one only costs storage.
    func deletePhoto(url: String, coupleId: String, memoryId: String) async {
        guard !coupleId.isEmpty, !memoryId.isEmpty else { return }
        let path = Self.objectPath(fromDownloadURL: url, coupleId: coupleId, memoryId: memoryId)
            ?? Self.legacyPath(coupleId: coupleId, memoryId: memoryId)
        await deleteObject(at: path)
    }

    /// Deletes the legacy .../photo.jpg that earlier versions wrote.
    func deletePhoto(coupleId: String, memoryId: String) async {
        guard !coupleId.isEmpty, !memoryId.isEmpty else { return }
        await deleteObject(at: Self.legacyPath(coupleId: coupleId, memoryId: memoryId))
    }

    // MARK: - Paths

    /// The Storage object path inside a Firebase download URL
    /// (`…/v0/b/<bucket>/o/<percent-encoded path>?alt=media&token=…`), or nil
    /// unless it names a file directly inside
    /// couples/{coupleId}/memories/{memoryId}/.
    ///
    /// Parsed by hand on purpose: Storage's URL-based reference lookup traps
    /// on a URL from another bucket or a malformed one, and `photoURL` is data
    /// any couple member's client can write.
    nonisolated static func objectPath(fromDownloadURL url: String,
                                       coupleId: String,
                                       memoryId: String) -> String? {
        guard let components = URLComponents(string: url) else { return nil }
        // The path excludes the query, so this is "up to '?'".
        let encodedPath = components.percentEncodedPath
        guard let marker = encodedPath.range(of: "/o/") else { return nil }
        let encodedName = encodedPath[marker.upperBound...]
        // Firebase encodes the object's slashes as %2F; a raw "/" here means
        // this is not a download URL.
        guard !encodedName.isEmpty, !encodedName.contains("/"),
              let name = String(encodedName).removingPercentEncoding else { return nil }

        let prefix = folder(coupleId: coupleId, memoryId: memoryId)
        guard name.hasPrefix(prefix) else { return nil }
        let leaf = name.dropFirst(prefix.count)
        guard !leaf.isEmpty, !leaf.contains("/"), leaf != ".", leaf != ".." else { return nil }
        return name
    }

    nonisolated private static func folder(coupleId: String, memoryId: String) -> String {
        "couples/\(coupleId)/memories/\(memoryId)/"
    }

    nonisolated private static func legacyPath(coupleId: String, memoryId: String) -> String {
        folder(coupleId: coupleId, memoryId: memoryId) + "photo.jpg"
    }

    // MARK: - Private

    private func deleteObject(at path: String) async {
        let ref = storage.reference().child(path)
        try? await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            ref.delete { error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume() }
            }
        }
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
