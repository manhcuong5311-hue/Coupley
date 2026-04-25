//
//  ContentView.swift
//  Coupley
//

import SwiftUI

// MARK: - Tab Selection

enum AppTab: Hashable {
    case home, mood, anniversary, chat
}

// MARK: - Content View

struct ContentView: View {

    let session: UserSession
    var displayName: String?

    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var notificationViewModel: NotificationViewModel
    @ObservedObject private var deepLinkRouter = WidgetDeepLinkRouter.shared
    @State private var selectedTab: AppTab = .home
    @State private var showPairingSheet = false
    @State private var showStatsSheet = false

    @StateObject private var coupleViewModel: CoupleViewModel
    @StateObject private var statsViewModel: CoupleStatsViewModel
    @StateObject private var moodViewModel: MoodViewModel
    @StateObject private var profileViewModel: CouplePersonProfileViewModel
    @StateObject private var microActionViewModel: MicroActionViewModel
    @StateObject private var nudgeViewModel: NudgeViewModel

    init(session: UserSession, displayName: String?) {
        self.session = session
        self.displayName = displayName

        let safeSession = session.isPaired ? session : UserSession.demo
        _nudgeViewModel = StateObject(wrappedValue: NudgeViewModel(session: session))
        _coupleViewModel = StateObject(wrappedValue: CoupleViewModel(
            session: safeSession,
            listenerService: FirestoreMoodListenerService(),
            coupleService: FirestoreCoupleService(),
            suggestionService: HybridAISuggestionService(),
            profileService: LocalProfileService(),
            presenceService: FirestorePresenceService()
        ))
        _statsViewModel = StateObject(wrappedValue: CoupleStatsViewModel(
            session: safeSession,
            syncService: FirestoreSyncService(),
            streakService: FirestoreStreakService()
        ))
        _moodViewModel = StateObject(wrappedValue: MoodViewModel(
            moodService: FirestoreMoodService(session: session),
            notificationService: NotificationService.shared,
            session: session
        ))
        _profileViewModel = StateObject(wrappedValue: CouplePersonProfileViewModel(session: session))
        _microActionViewModel = StateObject(wrappedValue: MicroActionViewModel(session: session))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                CoupleDashboardView(
                    viewModel: coupleViewModel,
                    statsViewModel: statsViewModel,
                    profileViewModel: profileViewModel,
                    microActionViewModel: microActionViewModel,
                    showPairingSheet: $showPairingSheet,
                    showStatsSheet: $showStatsSheet,
                    selectedTab: $selectedTab
                )
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(AppTab.home)

                MoodCheckinView(viewModel: moodViewModel)
                    .tabItem { Label("Mood", systemImage: "heart.fill") }
                    .tag(AppTab.mood)

                AnniversaryListView(session: session)
                    .tabItem { Label("Anniversary", systemImage: "calendar.badge.clock") }
                    .tag(AppTab.anniversary)

                ChatView(session: session, profileViewModel: profileViewModel)
                    .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right.fill") }
                    .tag(AppTab.chat)
            }
            .toolbarBackground(Brand.backgroundTop.opacity(0.96), for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)

            if !session.isPaired {
                connectPartnerBanner
                    .padding(.bottom, 58)
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            VStack {
                DisconnectNoticeBanner()
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                Spacer()
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.9),
                       value: sessionStore.pendingDisconnectNotice)
        }
        .brandBackground()
        .overlay {
            if let nudge = nudgeViewModel.incomingNudge {
                NudgePopupView(
                    nudge: nudge,
                    partnerName: profileViewModel.partnerProfile.displayName,
                    partnerAvatar: profileViewModel.partnerProfile.avatar,
                    onDismiss: { nudgeViewModel.dismiss() }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                .zIndex(999)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.78), value: nudgeViewModel.incomingNudge?.id)
            .sheet(isPresented: $showPairingSheet) {
                PairingSheetView(
                    userId: session.userId,
                    displayName: displayName ?? "You"
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Brand.backgroundTop)
            }
            .sheet(isPresented: $showStatsSheet) {
                NavigationStack {
                    CoupleStatsView(viewModel: statsViewModel)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { showStatsSheet = false }
                                    .foregroundStyle(Brand.accentStart)
                            }
                        }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Brand.backgroundTop)
            }
            .onAppear {
                profileViewModel.startListening()
                microActionViewModel.bind(to: coupleViewModel)
                microActionViewModel.refresh(from: coupleViewModel, reason: .appOpen)
                if session.isPaired {
                    coupleViewModel.startListening()
                    statsViewModel.loadStats()
                    nudgeViewModel.startListening()
                }
                notificationViewModel.setup(session: session)
            }
            .onChange(of: notificationViewModel.navigateToMood) { _, navigate in
                if navigate { selectedTab = .mood; notificationViewModel.navigateToMood = false }
            }
            .onChange(of: notificationViewModel.navigateToDashboard) { _, navigate in
                if navigate { selectedTab = .home; notificationViewModel.navigateToDashboard = false }
            }
            .onChange(of: deepLinkRouter.pendingDestination) { _, destination in
                handleWidgetDestination(destination)
            }
            .onAppear { handleWidgetDestination(deepLinkRouter.pendingDestination) }
            .onChange(of: sessionStore.isPaired) { _, paired in
                if paired {
                    coupleViewModel.startListening()
                    statsViewModel.loadStats()
                    profileViewModel.startListening()
                    nudgeViewModel.startListening()
                }
            }
    }

    // MARK: - Widget Deep Link Routing

    /// Translates an incoming widget destination into tab + sheet state.
    /// Calling with `nil` is a no-op so this is safe to invoke on appear.
    private func handleWidgetDestination(_ destination: WidgetDeepLink?) {
        guard let destination else { return }
        switch destination {
        case .home:
            selectedTab = .home
        case .anniversary:
            selectedTab = .anniversary
        case .mood:
            selectedTab = .mood
        case .partner:
            // Surface the pairing sheet only when the user can act on it.
            if !session.isPaired {
                showPairingSheet = true
            } else {
                selectedTab = .home
            }
        }
        deepLinkRouter.consume()
    }

    // MARK: - Connect Partner Banner

    private var connectPartnerBanner: some View {
        Button {
            showPairingSheet = true
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Brand.accentStart.opacity(0.18))
                        .frame(width: 40, height: 40)
                    Image(systemName: "link.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Brand.accentStart)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect your partner")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                    Text("Tap to share or enter an invite code")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Brand.textTertiary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Brand.backgroundTop)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Brand.accentStart.opacity(0.55), Brand.accentEnd.opacity(0.30)],
                                    startPoint: .leading, endPoint: .trailing
                                ),
                                lineWidth: 1.5
                            )
                    )
                    .shadow(color: Brand.accentStart.opacity(0.25), radius: 20, y: 4)
            )
        }
        .buttonStyle(BouncyButtonStyle(scale: 0.97))
    }
}

// MARK: - Pairing Sheet View

struct PairingSheetView: View {

    let userId: String
    let displayName: String

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: PairingViewModel
    @EnvironmentObject private var sessionStore: SessionStore

    init(userId: String, displayName: String) {
        self.userId = userId
        self.displayName = displayName
        _viewModel = StateObject(wrappedValue: PairingViewModel(userId: userId, displayName: displayName))
    }

    var body: some View {
        Brand.bgGradient
            .ignoresSafeArea(.all)
            .overlay {
                VStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Brand.divider)
                        .frame(width: 40, height: 5)
                        .padding(.top, 12)
                        .padding(.bottom, 8)

                    HStack {
                        Button("Close") { dismiss() }
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(Brand.textSecondary)

                        Spacer()

                        Button("Sign Out") {
                            sessionStore.signOut()
                            dismiss()
                        }
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(red: 1.0, green: 0.40, blue: 0.40))
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)

                    PairingView(viewModel: viewModel)
                }
            }
            .onChange(of: sessionStore.isPaired) { _, paired in
                if paired { dismiss() }
            }
    }
}

#Preview {
    ContentView(session: .demo, displayName: nil)
        .environmentObject(SessionStore())
        .environmentObject(NotificationViewModel())
}
