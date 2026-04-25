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
        UNUserNotificationCenter.current().delegate = NotificationService.shared
        Messaging.messaging().delegate = NotificationService.shared
        AppTheming.configureTabBar()
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("APNs registration failed: \(error)")
    }

}

// MARK: - App Entry Point

@main
struct CoupleyApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var sessionStore = SessionStore()
    @StateObject private var notificationViewModel = NotificationViewModel()
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var premiumStore = PremiumStore()

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
    /// the onboarding flow. The 5-tap reset gesture in Settings flips this
    /// without touching premium, pairing, or any Firestore data.
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
                        .task { notificationViewModel.requestPermissionIfNeeded() }
                } else {
                    OnboardingFlowView(userId: userId, initialName: displayName) {
                        // Closure runs on the main actor after `complete()`
                        // lands — flips the local flag, which RootView
                        // re-renders against.
                        hasCompletedOnboarding = true
                    }
                }

            case .ready(let session):
                ContentView(session: session, displayName: nil)
                    .environmentObject(notificationViewModel)
            }
        }
        .animation(.easeInOut(duration: 0.38), value: stateID)
        .brandBackground()        // fills the full screen, no black bars
        .attachWidgetSync()       // bind WidgetSyncService to session changes
        .handleWidgetDeepLinks()  // route coupley:// URLs from the widget
        .onChange(of: stateID) { _, _ in syncPremiumBinding() }
        .onAppear { syncPremiumBinding() }
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
