//
//  NotificationService.swift
//  Coupley
//
//  Production-grade orchestrator for every layer of the notification stack:
//    – Permission request + status
//    – APNs registration + correctly-typed APNs token forwarding to Firebase
//    – FCM token reception, persistence, and binding to the current user
//    – Push payload reception (foreground + background) with proper
//      foreground presentation
//    – Debug surface: tokens, last-received timestamp, manual refresh,
//      local test notification — consumed by DebugMenuView
//
//  Edge cases this service is designed to survive:
//    – FCM token arrives BEFORE the user signs in (held in cache, flushed
//      to Firestore the moment a user binds)
//    – User signs out (binding cleared; the previous user's Firestore row
//      remains and gets pruned by the server on the next failed push)
//    – User signs in as a different account (token re-bound; the old user's
//      row is overwritten only when *that* user logs back in)
//    – Token rotation by APNs / FCM (re-fired through `messaging:didReceive`
//      and re-saved automatically against the currently bound user)
//    – Re-install (FCM emits a fresh token; flow is identical to first run)
//

import Foundation
import UserNotifications
import UIKit
import FirebaseFirestore
import FirebaseMessaging

// MARK: - Protocol

protocol NotificationServiceProtocol: AnyObject {
    func requestPermission() async -> NotificationPermissionState
    func checkCurrentPermission() async -> NotificationPermissionState
    func registerForRemoteNotifications()
    func saveFCMToken(_ token: String, userId: String) async throws
    func updateLastActive(userId: String) async throws
    func savePreferences(_ preferences: NotificationPreferences, userId: String) async throws
    func loadPreferences(userId: String) async throws -> NotificationPreferences
}

// MARK: - Service

final class NotificationService: NSObject, NotificationServiceProtocol {

    static let shared = NotificationService()

    // MARK: - Dependencies

    private let db = Firestore.firestore()
    private let center = UNUserNotificationCenter.current()
    private let messaging = Messaging.messaging()

    // MARK: - State (debug-readable, single-writer = this service)

    private(set) var currentlyBoundUserId: String?
    private(set) var latestFCMToken: String?
    private(set) var latestAPNsToken: String?

    // MARK: - Init

    private override init() { super.init() }

    // MARK: - Permission

    func requestPermission() async -> NotificationPermissionState {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            log(granted ? .success : .info,
                category: "Permission",
                granted ? "Granted" : "Denied")
            if granted {
                await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
                return .authorized
            } else {
                return .denied
            }
        } catch {
            log(.error, category: "Permission",
                "Request failed: \(error.localizedDescription)")
            return .denied
        }
    }

    func checkCurrentPermission() async -> NotificationPermissionState {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized:    return .authorized
        case .denied:        return .denied
        case .provisional:   return .provisional
        case .notDetermined: return .unknown
        case .ephemeral:     return .provisional
        @unknown default:    return .unknown
        }
    }

    func registerForRemoteNotifications() {
        Task { @MainActor in
            UIApplication.shared.registerForRemoteNotifications()
            NotificationLogger.shared.info("APNs", "Registration requested")
        }
    }

    // MARK: - APNs Token (called from AppDelegate)

    /// Fed the raw `Data` from `didRegisterForRemoteNotificationsWithDeviceToken`.
    /// Forwards it to Firebase Messaging with the **explicit** environment
    /// type — leaving this on `.unknown` is the single most common reason
    /// FCM silently drops messages on TestFlight/App Store builds.
    func handleAPNsToken(_ deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        latestAPNsToken = hex

        #if DEBUG
        let tokenType: MessagingAPNSTokenType = .sandbox
        let typeLabel = "sandbox"
        #else
        let tokenType: MessagingAPNSTokenType = .prod
        let typeLabel = "prod"
        #endif

        messaging.setAPNSToken(deviceToken, type: tokenType)
        Task { @MainActor in
            NotificationLogger.shared.success(
                "APNs",
                "Token received (\(typeLabel)): \(hex.prefix(16))…"
            )
        }
    }

    func handleAPNsRegistrationFailure(_ error: Error) {
        Task { @MainActor in
            NotificationLogger.shared.error(
                "APNs",
                "Registration failed: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - User Binding

    /// Called by NotificationViewModel as soon as a real session resolves.
    /// Idempotent — calling with the same userId twice is a no-op.
    func bind(userId: String) {
        guard !userId.isEmpty else { return }
        guard currentlyBoundUserId != userId else { return }
        currentlyBoundUserId = userId

        // Flush whatever FCM token we already hold (covers the case where
        // FCM emitted before the user signed in, which is the norm).
        if let token = latestFCMToken {
            Task {
                try? await saveFCMToken(token, userId: userId)
            }
        } else {
            // No token yet — request one now so we're not waiting on the
            // delegate firing. This is also what unblocks first-launch
            // pushes for users who didn't authorise during onboarding.
            Task {
                _ = await refreshFCMToken()
            }
        }

        Task { @MainActor in
            NotificationLogger.shared.info("Binding", "Bound to user \(userId.prefix(8))…")
        }
    }

    func unbind() {
        currentlyBoundUserId = nil
        Task { @MainActor in
            NotificationLogger.shared.info("Binding", "Unbound")
        }
    }

    // MARK: - FCM Token

    @discardableResult
    func refreshFCMToken() async -> String? {
        do {
            let token = try await messaging.token()
            latestFCMToken = token
            log(.success, category: "FCM",
                "Token refresh OK: \(token.prefix(16))…")
            if let uid = currentlyBoundUserId, !uid.isEmpty {
                try await saveFCMToken(token, userId: uid)
            }
            return token
        } catch {
            log(.error, category: "FCM",
                "Token refresh failed: \(error.localizedDescription)")
            return nil
        }
    }

    func saveFCMToken(_ token: String, userId: String) async throws {
        guard !userId.isEmpty else { return }
        try await db.collection(FirestorePath.users).document(userId).setData([
            "fcmToken":       token,
            "tokenUpdatedAt": FieldValue.serverTimestamp(),
            "platform":       "ios",
            "appVersion":     Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        ], merge: true)
        log(.success, category: "FCM",
            "Saved token for \(userId.prefix(8))…")
    }

    /// Wipes the FCM token field on a user doc — used during sign-out so
    /// pushes don't trail to a device that no longer holds the account.
    func clearFCMToken(for userId: String) async {
        guard !userId.isEmpty else { return }
        do {
            try await db.collection(FirestorePath.users).document(userId).updateData([
                "fcmToken":       FieldValue.delete(),
                "tokenUpdatedAt": FieldValue.serverTimestamp()
            ])
            log(.info, category: "FCM",
                "Cleared token for \(userId.prefix(8))…")
        } catch {
            log(.warn, category: "FCM",
                "Clear failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Last Active / Preferences

    func updateLastActive(userId: String) async throws {
        guard !userId.isEmpty else { return }
        try await db.collection(FirestorePath.users).document(userId).setData([
            "lastActive": FieldValue.serverTimestamp(),
            "lastSeen":   FieldValue.serverTimestamp(),
            "timezone":   TimeZone.current.identifier
        ], merge: true)
    }

    func savePreferences(_ preferences: NotificationPreferences, userId: String) async throws {
        guard !userId.isEmpty else { return }
        try await db.collection(FirestorePath.users).document(userId).setData([
            "notificationPreferences": preferences.firestorePrefsDict,
            "reminderHour":            preferences.reminderHour
        ], merge: true)
    }

    func loadPreferences(userId: String) async throws -> NotificationPreferences {
        let snap = try await db.collection(FirestorePath.users).document(userId).getDocument()
        guard let data = snap.data() else { return NotificationPreferences() }
        let prefsDict = data["notificationPreferences"] as? [String: Any] ?? [:]
        let reminderHour = data["reminderHour"] as? Int ?? 20
        return NotificationPreferences(from: prefsDict, reminderHour: reminderHour)
    }

    // MARK: - Local Test Notification (DebugMenu)

    /// Schedules a local notification a few seconds in the future. Works in
    /// any build configuration and any auth state — useful for QA proving
    /// that *display* works even if remote delivery is broken.
    func scheduleLocalTest(after seconds: TimeInterval = 5) async {
        let content = UNMutableNotificationContent()
        content.title = "Test notification"
        content.body  = "If you see this, local notifications work ✓"
        content.sound = .default
        content.userInfo = ["type": "debug_test"]

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, seconds),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: "coupley.debug.test.\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        do {
            try await center.add(request)
            log(.success, category: "Local",
                "Test scheduled in \(Int(seconds))s")
        } catch {
            log(.error, category: "Local",
                "Schedule failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private func log(_ level: NotificationLogger.Level,
                     category: String,
                     _ message: String) {
        Task { @MainActor in
            NotificationLogger.shared.log(level, category: category, message)
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationService: UNUserNotificationCenterDelegate {

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        Task { @MainActor in
            NotificationLogger.shared.recordReceived()
            NotificationLogger.shared.info(
                "Foreground",
                "Received: \(notification.request.content.title)"
            )
        }
        NotificationCenter.default.post(name: .didReceiveNudge, object: nil, userInfo: userInfo)
        completionHandler([.banner, .badge, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo   = response.notification.request.content.userInfo
        let typeString = userInfo["type"] as? String ?? ""

        Task { @MainActor in
            NotificationLogger.shared.info("Tap", "type=\(typeString)")
        }

        NotificationCenter.default.post(
            name: .didTapNudge,
            object: nil,
            userInfo: ["type": typeString, "userInfo": userInfo]
        )

        Task { try? await UNUserNotificationCenter.current().setBadgeCount(0) }
        completionHandler()
    }
}

// MARK: - MessagingDelegate

extension NotificationService: MessagingDelegate {

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken, !token.isEmpty else {
            Task { @MainActor in
                NotificationLogger.shared.warn("FCM", "Empty token received")
            }
            return
        }
        latestFCMToken = token

        // If a user is already bound, save immediately. Otherwise the token
        // sits in `latestFCMToken` and will be flushed by `bind(userId:)`.
        if let uid = currentlyBoundUserId, !uid.isEmpty {
            Task {
                try? await saveFCMToken(token, userId: uid)
            }
        }

        Task { @MainActor in
            NotificationLogger.shared.success("FCM", "Token: \(token.prefix(16))…")
        }
        NotificationCenter.default.post(
            name: .didReceiveFCMToken,
            object: nil,
            userInfo: ["token": token]
        )
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let didReceiveNudge    = Notification.Name("didReceiveNudge")
    static let didTapNudge        = Notification.Name("didTapNudge")
    static let didReceiveFCMToken = Notification.Name("didReceiveFCMToken")
}
