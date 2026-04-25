//
//  WidgetSnapshotStore.swift
//  Coupley
//
//  Atomic read/write of the widget snapshot JSON in the App Group container.
//  Writes are atomic (write-temp + rename) so the widget never reads a
//  half-flushed file.
//

import Foundation

// MARK: - Store

enum WidgetSnapshotStore {

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Read

    /// Reads the latest snapshot from the App Group container. Returns
    /// `.placeholder` when the file does not exist, the App Group is
    /// misconfigured, or the file is from a newer schema version.
    static func read() -> WidgetSnapshot {
        guard let url = WidgetShared.snapshotURL,
              let data = try? Data(contentsOf: url),
              let snapshot = try? decoder.decode(WidgetSnapshot.self, from: data),
              snapshot.version <= WidgetSnapshot.currentVersion
        else {
            return .placeholder
        }
        return snapshot
    }

    // MARK: - Write

    /// Atomically persists the snapshot. Returns `true` on success — callers
    /// in the main app should reload widget timelines only after a successful
    /// write so the widget never re-renders against stale data.
    @discardableResult
    static func write(_ snapshot: WidgetSnapshot) -> Bool {
        guard let url = WidgetShared.snapshotURL else { return false }
        do {
            let data = try encoder.encode(snapshot)
            try data.write(to: url, options: [.atomic])
            return true
        } catch {
            return false
        }
    }

    // MARK: - Photo

    /// Writes raw image bytes (already JPEG-encoded by caller) to the
    /// shared container. Returns the filename to store in the snapshot
    /// or nil on failure.
    @discardableResult
    static func writeCouplePhoto(jpegData: Data) -> String? {
        guard let url = WidgetShared.couplePhotoURL else { return nil }
        do {
            try jpegData.write(to: url, options: [.atomic])
            return url.lastPathComponent
        } catch {
            return nil
        }
    }

    /// Resolves the absolute file URL for a previously stored photo
    /// filename. Returns nil when the file is missing — e.g. the user
    /// reinstalled the app, or the photo was cleared on disconnect.
    static func resolvePhotoURL(filename: String?) -> URL? {
        guard let filename, !filename.isEmpty,
              let container = WidgetShared.containerURL
        else { return nil }
        let url = container.appendingPathComponent(filename, isDirectory: false)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Removes the cached photo file. Called from the main app when the
    /// user disconnects from a partner.
    static func clearCouplePhoto() {
        guard let url = WidgetShared.couplePhotoURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Wipes the entire snapshot — called on sign-out / disconnect so the
    /// widget can't keep rendering stale relationship data.
    static func clearAll() {
        if let url = WidgetShared.snapshotURL {
            try? FileManager.default.removeItem(at: url)
        }
        clearCouplePhoto()
    }
}
