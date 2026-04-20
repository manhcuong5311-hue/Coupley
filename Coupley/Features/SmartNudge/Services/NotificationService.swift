//
//  NotificationService.swift
//  Coupley
//
//  Created by Sam Manh Cuong on 1/4/26.
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
        case .authorized: return .authorized
        case .denied: return .denied
        case .provisional: return .provisional
        case .notDetermined: return .unknown
        case .ephemeral: return .provisional
        @unknown default: return .unknown
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
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationService: UNUserNotificationCenterDelegate {

    /// Handle foreground notifications — show them as banners
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo

        // Post notification for in-app handling
        NotificationCenter.default.post(
            name: .didReceiveNudge,
            object: nil,
            userInfo: userInfo
        )

        // Show banner + badge + sound even when app is in foreground
        completionHandler([.banner, .badge, .sound])
    }

    /// Handle notification tap — navigate to relevant screen
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let typeString = userInfo["type"] as? String ?? ""

        // Post navigation event
        NotificationCenter.default.post(
            name: .didTapNudge,
            object: nil,
            userInfo: [
                "type": typeString,
                "userInfo": userInfo
            ]
        )

        // Clear badge
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

        // Post token for ViewModel to pick up
        NotificationCenter.default.post(
            name: .didReceiveFCMToken,
            object: nil,
            userInfo: ["token": token]
        )
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let didReceiveNudge = Notification.Name("didReceiveNudge")
    static let didTapNudge = Notification.Name("didTapNudge")
    static let didReceiveFCMToken = Notification.Name("didReceiveFCMToken")
}
