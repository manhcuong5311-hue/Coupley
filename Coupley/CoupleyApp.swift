//
//  CoupleyApp.swift
//  Coupley
//

import SwiftUI
import FirebaseCore
import FirebaseMessaging
import UserNotifications

// MARK: - App Delegate

class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()

        // The two delegate hooks the rest of the notification stack relies
        // on. Wired here (rather than later) so the very first FCM token
        // that fires post-Firebase-init is captured even if no UI exists yet.
        UNUserNotificationCenter.current().delegate = NotificationService.shared
        Messaging.messaging().delegate              = NotificationService.shared

        AppTheming.configureTabBar()

        Task { @MainActor in
            NotificationLogger.shared.info("Launch", "App did finish launching")
        }
        return true
    }

    // APNs registration succeeded — forward the device token (with the
    // correct sandbox/prod type) to Firebase Messaging.
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        NotificationService.shared.handleAPNsToken(deviceToken)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NotificationService.shared.handleAPNsRegistrationFailure(error)
    }

    // Silent / `content-available` push handler. iOS calls this for any
    // remote payload that delivers in the background; UNUserNotificationCenter
    // covers visible foreground delivery separately.
    //
    // `nonisolated` matches the protocol requirement (which is not main-actor
    // isolated) so the non-Sendable `userInfo` dictionary doesn't have to
    // cross an actor boundary on entry. We extract the only field we need
    // (a Sendable String) before hopping to the main actor for logging.
    nonisolated func application(_ application: UIApplication,
                                 didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        let type = (userInfo["type"] as? String) ?? "unknown"
        Task { @MainActor in
            NotificationLogger.shared.recordReceived()
            NotificationLogger.shared.info("Background", "Silent push received (type=\(type))")
        }
        return .newData
    }
}

// MARK: - App Entry Point

@main
struct CoupleyApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var sessionStore         = SessionStore()
    @StateObject private var notificationViewModel = NotificationViewModel()
    @StateObject private var themeManager         = ThemeManager()
    @StateObject private var premiumStore         = PremiumStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(sessionStore)
                .environmentObject(notificationViewModel)
                .environmentObject(themeManager)
                .environmentObject(premiumStore)
                .preferredColorScheme(themeManager.colorScheme)
                .id(themeManager.variant)      // rebuild tree when variant changes
                .fixWindowBackground()          // ← UIKit-level fix
                .onAppear { sessionStore.start() }
        }
    }
}

// MARK: - Root View

struct RootView: View {

    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var notificationViewModel: NotificationViewModel
    @EnvironmentObject var premiumStore: PremiumStore

    /// Per-user gate. Survives sign-out (deliberate — no need to re-onboard
    /// the same human between sessions) and is the *only* flag that gates
    /// the onboarding flow. The DebugMenu's "Replay Onboarding" action flips
    /// this without touching premium, pairing, or any Firestore data.
    ///
    /// The gate now applies to **both** `.needsPairing` and `.ready` — so a
    /// paired user replaying onboarding from the debug menu sees the full
    /// flow again instead of being silently routed back to the dashboard.
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        Group {
            switch sessionStore.appState {
            case .loading:
                SplashView()

            case .unauthenticated:
                WelcomeView()

            case .needsPairing(let userId, let displayName):
                if hasCompletedOnboarding {
                    ContentView(session: UserSession.solo(userId: userId), displayName: displayName)
                        .environmentObject(notificationViewModel)
                } else {
                    OnboardingFlowView(userId: userId, initialName: displayName) {
                        hasCompletedOnboarding = true
                    }
                }

            case .ready(let session):
                if hasCompletedOnboarding {
                    ContentView(session: session, displayName: nil)
                        .environmentObject(notificationViewModel)
                } else {
                    // Replay path: a paired user with the onboarding flag
                    // reset hits this branch. Completion flips the flag and
                    // routes them right back to ContentView.
                    OnboardingFlowView(userId: session.userId, initialName: "") {
                        hasCompletedOnboarding = true
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.38), value: stateID)
        .brandBackground()        // fills the full screen, no black bars
        .attachWidgetSync()       // bind WidgetSyncService to session changes
        .handleWidgetDeepLinks()  // route coupley:// URLs from the widget
        .onChange(of: stateID) { _, _ in
            syncPremiumBinding()
            syncNotificationBinding()
        }
        .onAppear {
            syncPremiumBinding()
            syncNotificationBinding()
        }
    }

    private func syncPremiumBinding() {
        switch sessionStore.appState {
        case .ready(let s):
            premiumStore.bind(userId: s.userId, coupleId: s.coupleId)
        case .needsPairing(let userId, _):
            premiumStore.bind(userId: userId, coupleId: nil)
        case .loading, .unauthenticated:
            premiumStore.unbind()
        }
    }

    /// Mirrors the auth state into the notification stack. We only need to
    /// react on sign-out — `setup(session:)` is called on every new session
    /// from ContentView's onAppear, so the bound path is covered there.
    private func syncNotificationBinding() {
        if case .unauthenticated = sessionStore.appState {
            notificationViewModel.tearDownForSignOut()
        }
    }

    private var stateID: Int {
        switch sessionStore.appState {
        case .loading: return 0; case .unauthenticated: return 1
        case .needsPairing: return 2; case .ready: return 3
        }
    }
}

// MARK: - Splash View

struct SplashView: View {

    @State private var scale: CGFloat = 0.72
    @State private var opacity: Double = 0

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Brand.accentStart.opacity(0.30))
                    .frame(width: 150, height: 150)
                    .blur(radius: 45)

                Circle()
                    .fill(Brand.surfaceLight)
                    .frame(width: 96, height: 96)
                    .overlay(Circle().strokeBorder(Brand.divider, lineWidth: 1))
                    .overlay { Text("💑").font(.system(size: 40)) }
            }
            .scaleEffect(scale)

            Text("Coupley")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(Brand.textPrimary)
        }
        .opacity(opacity)
        .onAppear {
            withAnimation(.spring(response: 0.65, dampingFraction: 0.72).delay(0.1)) {
                scale = 1.0; opacity = 1.0
            }
        }
    }
}
