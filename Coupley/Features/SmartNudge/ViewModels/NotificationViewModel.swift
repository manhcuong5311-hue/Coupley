//
//  NotificationViewModel.swift
//  Coupley
//

import Foundation
import Combine
import UIKit

// MARK: - Notification ViewModel

@MainActor
final class NotificationViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var permissionState: NotificationPermissionState = .unknown
    @Published var preferences: NotificationPreferences = NotificationPreferences()
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

    // MARK: - Setup (called once UserSession is available)

    func setup(session: UserSession) {
        guard !session.userId.isEmpty else { return }
        self.session = session

        Task {
            permissionState = await notificationService.checkCurrentPermission()

            if permissionState == .unknown {
                permissionState = await notificationService.requestPermission()
            }

            if permissionState == .authorized || permissionState == .provisional {
                notificationService.registerForRemoteNotifications()
            }

            try? await notificationService.updateLastActive(userId: session.userId)
            await loadPreferencesFromFirestore()
            startHeartbeat()
        }
    }

    // MARK: - Permission

    func requestPermissionIfNeeded() {
        guard permissionState == .unknown else { return }
        Task {
            permissionState = await notificationService.requestPermission()
            if permissionState == .authorized || permissionState == .provisional {
                notificationService.registerForRemoteNotifications()
            }
        }
    }

    // MARK: - Preferences

    func savePreferences() {
        let userId = session.userId
        guard !userId.isEmpty else { return }
        let prefs = preferences
        Task {
            try? await notificationService.savePreferences(prefs, userId: userId)
        }
    }

    private func loadPreferencesFromFirestore() async {
        guard !session.userId.isEmpty else { return }
        preferences = (try? await notificationService.loadPreferences(userId: session.userId))
            ?? NotificationPreferences()
    }

    // MARK: - Heartbeat

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
        for index in recentNudges.indices { recentNudges[index].isRead = true }
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
        case .lowMood, .reaction, .ping:
            navigateToDashboard = true
        case .dailySync, .inactivity:
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

    // MARK: - Private Observers

    private func observeNotifications() {
        NotificationCenter.default.publisher(for: .didReceiveNudge)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] n in self?.handleIncomingNudge(n.userInfo) }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .didTapNudge)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] n in self?.handleTappedNudge(n.userInfo) }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .didReceiveFCMToken)
            .receive(on: DispatchQueue.main)
            .compactMap { $0.userInfo?["token"] as? String }
            .sink { [weak self] token in self?.handleFCMToken(token) }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.recordActivity() }
            .store(in: &cancellables)
    }

    private func handleIncomingNudge(_ userInfo: [AnyHashable: Any]?) {
        guard let info = userInfo else { return }

        let type = info["type"] as? String ?? "unknown"

        // APNs alert can be a String or a {title, body} dict depending on payload format
        let apsDict = info["aps"] as? [String: Any]
        let alertTitle: String
        let alertBody: String

        if let alertDict = apsDict?["alert"] as? [String: Any] {
            alertTitle = alertDict["title"] as? String ?? "Coupley"
            alertBody  = alertDict["body"]  as? String ?? ""
        } else if let alertString = apsDict?["alert"] as? String {
            alertTitle = alertString
            alertBody  = ""
        } else {
            alertTitle = "Coupley"
            alertBody  = info["body"] as? String ?? ""
        }

        let nudge = NudgeRecord(type: type, title: alertTitle, body: alertBody)
        recentNudges.insert(nudge, at: 0)
        if recentNudges.count > 20 { recentNudges = Array(recentNudges.prefix(20)) }
        updateUnreadCount()
    }

    private func handleTappedNudge(_ userInfo: [AnyHashable: Any]?) {
        guard let info = userInfo,
              let typeString = info["type"] as? String else { return }
        handleNudgeTap(NudgeRecord(type: typeString, title: "", body: ""))
    }

    private func updateUnreadCount() {
        unreadCount = recentNudges.filter { !$0.isRead }.count
    }
}
