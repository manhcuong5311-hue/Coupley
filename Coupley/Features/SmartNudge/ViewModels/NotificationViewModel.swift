//
//  NotificationViewModel.swift
//  Coupley
//
//  Created by Sam Manh Cuong on 1/4/26.
//

import Foundation
import Combine
import UIKit

// MARK: - Notification ViewModel

@MainActor
final class NotificationViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var permissionState: NotificationPermissionState = .unknown
    @Published var recentNudges: [NudgeRecord] = []
    @Published var unreadCount: Int = 0
    @Published var showNudgeDetail: Bool = false
    @Published var selectedNudge: NudgeRecord?
    @Published var navigateToMood: Bool = false
    @Published var navigateToDashboard: Bool = false

    // MARK: - Dependencies

    private let notificationService: any NotificationServiceProtocol
    private var session: UserSession = UserSession(userId: "", coupleId: "", partnerId: "")
    private var cancellables = Set<AnyCancellable>()
    private var heartbeatTask: Task<Void, Never>?

    // MARK: - Init

    init(notificationService: (any NotificationServiceProtocol)? = nil) {
        self.notificationService = notificationService ?? NotificationService.shared
        observeNotifications()
    }

    // MARK: - Setup

    /// Call this once the real UserSession is available (after auth + pairing).
    func setup(session: UserSession) {
        guard !session.userId.isEmpty else { return }
        self.session = session

        Task {
            permissionState = await notificationService.checkCurrentPermission()

            if permissionState == .unknown {
                permissionState = await notificationService.requestPermission()
            }

            if permissionState == .authorized {
                notificationService.registerForRemoteNotifications()
            }

            try? await notificationService.updateLastActive(userId: session.userId)

            startHeartbeat()
        }
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        let userId = session.userId
        guard !userId.isEmpty else { return }

        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000) // 60s
                if Task.isCancelled { return }
                try? await self?.notificationService.updateLastActive(userId: userId)
            }
        }
    }

    func requestPermissionIfNeeded() {
        guard permissionState == .unknown || permissionState == .denied else { return }

        Task {
            permissionState = await notificationService.requestPermission()
        }
    }

    // MARK: - Token Handling

    func handleFCMToken(_ token: String) {
        guard !session.userId.isEmpty else { return }
        Task {
            try? await notificationService.saveFCMToken(token, userId: session.userId)
        }
    }

    // MARK: - Nudge Management

    func markAsRead(_ nudge: NudgeRecord) {
        guard let index = recentNudges.firstIndex(where: { $0.id == nudge.id }) else { return }
        recentNudges[index].isRead = true
        updateUnreadCount()
    }

    func markAllAsRead() {
        for index in recentNudges.indices {
            recentNudges[index].isRead = true
        }
        updateUnreadCount()
    }

    func clearAll() {
        recentNudges.removeAll()
        unreadCount = 0
    }

    // MARK: - Navigation

    func handleNudgeTap(_ nudge: NudgeRecord) {
        markAsRead(nudge)

        switch nudge.nudgeType {
        case .lowMood:
            navigateToDashboard = true
        case .dailySync:
            navigateToMood = true
        case .inactivity:
            navigateToMood = true
        case .none:
            break
        }
    }

    // MARK: - Activity Tracking

    func recordActivity() {
        guard !session.userId.isEmpty else { return }
        Task {
            try? await notificationService.updateLastActive(userId: session.userId)
        }
    }

    // MARK: - Private

    private func observeNotifications() {
        // Incoming nudge while app is open
        NotificationCenter.default.publisher(for: .didReceiveNudge)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleIncomingNudge(notification.userInfo)
            }
            .store(in: &cancellables)

        // Nudge tapped from notification center
        NotificationCenter.default.publisher(for: .didTapNudge)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleTappedNudge(notification.userInfo)
            }
            .store(in: &cancellables)

        // FCM token received
        NotificationCenter.default.publisher(for: .didReceiveFCMToken)
            .receive(on: DispatchQueue.main)
            .compactMap { $0.userInfo?["token"] as? String }
            .sink { [weak self] token in
                self?.handleFCMToken(token)
            }
            .store(in: &cancellables)

        // App became active — update last active
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.recordActivity()
            }
            .store(in: &cancellables)
    }

    private func handleIncomingNudge(_ userInfo: [AnyHashable: Any]?) {
        guard let info = userInfo else { return }

        let type = info["type"] as? String ?? "unknown"
        let title = (info["aps"] as? [String: Any])?["alert"] as? String
            ?? "Coupley"
        let body = info["body"] as? String ?? ""

        let nudge = NudgeRecord(
            type: type,
            title: title,
            body: body
        )

        recentNudges.insert(nudge, at: 0)

        // Keep only last 20
        if recentNudges.count > 20 {
            recentNudges = Array(recentNudges.prefix(20))
        }

        updateUnreadCount()
    }

    private func handleTappedNudge(_ userInfo: [AnyHashable: Any]?) {
        guard let info = userInfo,
              let typeString = info["type"] as? String else { return }

        let nudge = NudgeRecord(
            type: typeString,
            title: "",
            body: ""
        )

        handleNudgeTap(nudge)
    }

    private func updateUnreadCount() {
        unreadCount = recentNudges.filter { !$0.isRead }.count
    }
}
