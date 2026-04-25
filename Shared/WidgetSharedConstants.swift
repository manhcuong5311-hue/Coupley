//
//  WidgetSharedConstants.swift
//  Coupley
//
//  Compile target: shared between main app and widget extension.
//  Must NOT import Firebase or any framework that the widget process can't load.
//

import Foundation

// MARK: - App Group + URL Scheme

enum WidgetShared {

    /// App Group identifier. Must be configured in entitlements for both
    /// the main app target and the widget extension target.
    static let appGroupID = "group.com.SamCorp.Coupley"

    /// Custom URL scheme used by widget deeplinks. Must be declared under
    /// `CFBundleURLTypes` in the main app's Info.plist.
    static let urlScheme = "coupley"

    /// Widget kind identifier — must match the value passed to
    /// `WidgetConfiguration(kind:)` and to `WidgetCenter.reloadTimelines(ofKind:)`.
    static let widgetKind = "CoupleyHomeWidget"

    // MARK: - Container

    /// Shared App Group container URL. Returns nil only when the App Group
    /// entitlement is misconfigured — callers should treat that as a developer
    /// error and fall back to in-memory state.
    static var containerURL: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        )
    }

    /// Path inside the App Group container where the snapshot JSON lives.
    static var snapshotURL: URL? {
        containerURL?.appendingPathComponent("widget_snapshot.json", isDirectory: false)
    }

    /// Path where the cached couple photo lives (JPEG).
    static var couplePhotoURL: URL? {
        containerURL?.appendingPathComponent("couple_photo.jpg", isDirectory: false)
    }
}
