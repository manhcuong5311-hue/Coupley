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
        configureTabBar()
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

    private func configureTabBar() {
        let brandBg = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.07, green: 0.04, blue: 0.15, alpha: 0.97)
                : UIColor(red: 1.00, green: 0.98, blue: 0.99, alpha: 0.97)
        }
        let accent = UIColor(red: 1.0, green: 0.38, blue: 0.60, alpha: 1.0)
        let inactive = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.38)
                : UIColor.black.withAlphaComponent(0.42)
        }

        let a = UITabBarAppearance()
        a.configureWithOpaqueBackground()
        a.backgroundColor = brandBg
        a.stackedLayoutAppearance.normal.iconColor    = inactive
        a.stackedLayoutAppearance.selected.iconColor  = accent
        a.stackedLayoutAppearance.normal.titleTextAttributes  = [.foregroundColor: inactive]
        a.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: accent]

        UITabBar.appearance().standardAppearance   = a
        UITabBar.appearance().scrollEdgeAppearance = a
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
                .fixWindowBackground()        // ← UIKit-level fix
                .onAppear { sessionStore.start() }
        }
    }
}

// MARK: - Root View

struct RootView: View {

    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var notificationViewModel: NotificationViewModel
    @EnvironmentObject var premiumStore: PremiumStore
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    var body: some View {
        Group {
            switch sessionStore.appState {
            case .loading:
                SplashView()

            case .unauthenticated:
                if hasSeenOnboarding {
                    AuthView()
                } else {
                    OnboardingView()
                }

            case .needsPairing(let userId, let displayName):
                ContentView(session: UserSession.solo(userId: userId), displayName: displayName)
                    .environmentObject(notificationViewModel)

            case .ready(let session):
                ContentView(session: session, displayName: nil)
                    .environmentObject(notificationViewModel)
            }
        }
        .animation(.easeInOut(duration: 0.38), value: stateID)
        .brandBackground()        // fills the full screen, no black bars
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
