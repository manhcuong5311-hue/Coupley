//
//  NotificationService.swift
//  Coupley
//

import Foundation
import UserNotifications
import UIKit
import FirebaseFirestore
import FirebaseMessaging

// MARK: - Notification Service Protocol

protocol NotificationServiceProtocol {
    func requestPermission() async -> NotificationPermissionState
    func checkCurrentPermission() async -> NotificationPermissionState
    func registerForRemoteNotifications()
    func saveFCMToken(_ token: String, userId: String) async throws
    func updateLastActive(userId: String) async throws
    func savePreferences(_ preferences: NotificationPreferences, userId: String) async throws
    func loadPreferences(userId: String) async throws -> NotificationPreferences
}

// MARK: - Notification Service

final class NotificationService: NSObject, NotificationServiceProtocol {

    static let shared = NotificationService()

    private let db = Firestore.firestore()

    private override init() {
        super.init()
    }

    // MARK: - Permission

    func requestPermission() async -> NotificationPermissionState {
        do {
            let options: UNAuthorizationOptions = [.alert, .badge, .sound]
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: options)

            if granted {
                registerForRemoteNotificationsOnMain()
                return .authorized
            } else {
                return .denied
            }
        } catch {
            return .denied
        }
    }

    func checkCurrentPermission() async -> NotificationPermissionState {
        let settings = await UNUserNotificationCenter.current().notificationSettings()

        switch settings.authorizationStatus {
        case .authorized:    return .authorized
        case .denied:        return .denied
        case .provisional:   return .provisional
        case .notDetermined: return .unknown
        case .ephemeral:     return .provisional
        @unknown default:    return .unknown
        }
    }

    @MainActor
    private func registerForRemoteNotificationsOnMain() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    func registerForRemoteNotifications() {
        Task { @MainActor in
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    // MARK: - FCM Token

    func saveFCMToken(_ token: String, userId: String) async throws {
        try await db.collection(FirestorePath.users).document(userId).setData([
            "fcmToken": token,
            "tokenUpdatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }

    // MARK: - Last Active

    func updateLastActive(userId: String) async throws {
        guard !userId.isEmpty else { return }
        try await db.collection(FirestorePath.users).document(userId).setData([
            "lastActive": FieldValue.serverTimestamp(),
            "lastSeen": FieldValue.serverTimestamp(),
            "timezone": TimeZone.current.identifier
        ], merge: true)
    }

    // MARK: - Notification Preferences

    func savePreferences(_ preferences: NotificationPreferences, userId: String) async throws {
        guard !userId.isEmpty else { return }
        try await db.collection(FirestorePath.users).document(userId).setData([
            "notificationPreferences": preferences.firestorePrefsDict,
            "reminderHour": preferences.reminderHour
        ], merge: true)
    }

    func loadPreferences(userId: String) async throws -> NotificationPreferences {
        let snap = try await db.collection(FirestorePath.users).document(userId).getDocument()
        guard let data = snap.data() else { return NotificationPreferences() }
        let prefsDict = data["notificationPreferences"] as? [String: Any] ?? [:]
        let reminderHour = data["reminderHour"] as? Int ?? 20
        return NotificationPreferences(from: prefsDict, reminderHour: reminderHour)
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
        NotificationCenter.default.post(name: .didReceiveNudge, object: nil, userInfo: userInfo)
        completionHandler([.banner, .badge, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let typeString = userInfo["type"] as? String ?? ""

        NotificationCenter.default.post(
            name: .didTapNudge,
            object: nil,
            userInfo: ["type": typeString, "userInfo": userInfo]
        )

        Task {
            try? await UNUserNotificationCenter.current().setBadgeCount(0)
        }

        completionHandler()
    }
}

// MARK: - MessagingDelegate

extension NotificationService: MessagingDelegate {

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
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
