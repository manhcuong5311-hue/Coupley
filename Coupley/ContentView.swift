//
//  ContentView.swift
//  Coupley
//

import SwiftUI

// MARK: - Tab Selection

enum AppTab: Hashable {
    case home, mood, together, anniversary, chat
}

// MARK: - Content View

struct ContentView: View {

    let session: UserSession
    var displayName: String?

    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var notificationViewModel: NotificationViewModel
    @ObservedObject private var deepLinkRouter = WidgetDeepLinkRouter.shared
    @ObservedObject private var ads = AdsManager.shared
    @State private var selectedTab: AppTab = .home
    @State private var showPairingSheet = false
    @State private var showStatsSheet = false
    /// What a tapped capsule or crown reminder asks Journey to open. Journey
    /// handles it and sets it back to nil.
    @State private var journeyFocus: JourneyFocus?
    /// A reminder's focus held back while one of this view's sheets slides
    /// away: Journey may answer it with a sheet of its own (a capsule's
    /// detail), which can't go up while ours is still on screen.
    @State private var pendingJourneyFocus: JourneyFocus?

    @StateObject private var coupleViewModel: CoupleViewModel
    @StateObject private var statsViewModel: CoupleStatsViewModel
    @StateObject private var moodViewModel: MoodViewModel
    @StateObject private var profileViewModel: CouplePersonProfileViewModel
    @StateObject private var microActionViewModel: MicroActionViewModel
    @StateObject private var nudgeViewModel: NudgeViewModel
    @StateObject private var chatUnreadCounter = ChatUnreadCounter()
    /// Owned here rather than by the dashboard: the Home tab badge counts the
    /// letters that are ready to open.
    @StateObject private var lettersViewModel: FutureLetterViewModel

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
        _lettersViewModel = StateObject(wrappedValue: FutureLetterViewModel(session: session))

        #if DEBUG
        // Only the first value is used: @State keeps its storage for the
        // life of this view, so later inits don't move the user's tab.
        if let tab = Self.launchArgumentTab {
            _selectedTab = State(initialValue: tab)
        }
        #endif
    }

    #if DEBUG
    /// DEBUG only, for automated screenshots: the tab named by the
    /// `-coupleyStartTab home|mood|together|journey|chat` launch argument.
    /// Read once per process.
    private static let launchArgumentTab: AppTab? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-coupleyStartTab"),
              arguments.indices.contains(flag + 1) else { return nil }
        switch arguments[flag + 1] {
        case "home":     return .home
        case "mood":     return .mood
        case "together": return .together
        case "journey":  return .anniversary
        case "chat":     return .chat
        default:         return nil
        }
    }()
    #endif

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                CoupleDashboardView(
                    viewModel: coupleViewModel,
                    statsViewModel: statsViewModel,
                    profileViewModel: profileViewModel,
                    microActionViewModel: microActionViewModel,
                    lettersViewModel: lettersViewModel,
                    showPairingSheet: $showPairingSheet,
                    showStatsSheet: $showStatsSheet,
                    selectedTab: $selectedTab
                )
                .adBannerInset()
                .tabItem {
                    Label {
                        Text("Home", comment: "Tab bar title: the main dashboard. Keep it short.")
                    } icon: {
                        Image(systemName: "house.fill")
                    }
                }
                .tag(AppTab.home)
                .badge(lettersViewModel.readyForMeCount)

                MoodCheckinView(viewModel: moodViewModel)
                    .adBannerInset()
                    .tabItem {
                        Label {
                            Text("Mood", comment: "Tab bar title: daily mood check-in. Keep it short.")
                        } icon: {
                            Image(systemName: "heart.fill")
                        }
                    }
                    .tag(AppTab.mood)

                TogetherView(session: session)
                    .adBannerInset()
                    .tabItem {
                        Label {
                            Text("Together", comment: "Tab bar title: shared goals, dreams and challenges. Keep it short.")
                        } icon: {
                            Image(systemName: "infinity")
                        }
                    }
                    .tag(AppTab.together)

                // Journey never observes the letters view model: it gets this
                // render's envelopes as one value, and opens or writes a
                // letter through the sheet presented below.
                TimeTreeView(
                    session: session,
                    letters: lettersViewModel.journeyFeed(partnerName: profileViewModel.partnerProfile.displayName),
                    myName: profileViewModel.myProfile == .placeholderSelf ? nil : profileViewModel.myProfile.displayName,
                    focus: $journeyFocus,
                    onOpenLetter: { lettersViewModel.show($0) },
                    onOpenAllLetters: { lettersViewModel.openHub() },
                    onWriteLetter: { writeLetter(seed: $0, opensAt: $1) }
                )
                    .adBannerInset()
                    .tabItem {
                        Label {
                            Text("Journey", comment: "Tab bar title: the couple's timeline of memories. Keep it short.")
                        } icon: {
                            Image(systemName: "leaf.fill")
                        }
                    }
                    .tag(AppTab.anniversary)

                // Chat used to be excluded because the banner would sit
                // between the message field and the keyboard. AdsManager now
                // tears the banner down on `keyboardWillShow` and restores it
                // on hide, so that case no longer happens: while typing there
                // is no ad on screen at all.
                // Its banner inset lives inside ChatView, below the composer:
                // applied out here it sits outside the NavigationStack and
                // overlays the conversation instead of shortening it.
                ChatView(session: session,
                         profileViewModel: profileViewModel,
                         onWriteLetter: { writeLetter(seed: $0) })
                    .tabItem {
                        Label {
                            Text("Chat", comment: "Tab bar title: messages with the partner. Keep it short.")
                        } icon: {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                        }
                    }
                    .tag(AppTab.chat)
                    .badge(chatUnreadCounter.unreadCount)
            }
            .toolbarBackground(Brand.backgroundTop.opacity(0.96), for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)

            if !session.isPaired {
                connectPartnerBanner
                    .padding(.bottom, 58 + ads.bannerInset)
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
                // "You" stays English: PairingViewModel writes this name to
                // the invite document as `creatorName`, which is data. (Only
                // reached when paired: an unpaired session passes "" here.)
                PairingSheetView(
                    userId: session.userId,
                    displayName: displayName ?? "You"
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Brand.backgroundTop)
            }
            .sheet(isPresented: $showStatsSheet, onDismiss: { releasePendingJourneyFocus() }) {
                NavigationStack {
                    CoupleStatsView(viewModel: statsViewModel)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button {
                                    showStatsSheet = false
                                } label: {
                                    Text("Done", comment: "Button: close the stats sheet")
                                }
                                .foregroundStyle(Brand.accentStart)
                            }
                        }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Brand.backgroundTop)
            }
            // The one presenter of the letters sheet, so Home, Chat and
            // Journey can all open it. Never also attach it inside a tab: two
            // `.sheet(item:)` bound to one route would both try to present.
            .sheet(item: $lettersViewModel.route, onDismiss: { releasePendingJourneyFocus() }) { route in
                FutureLetterSheet(
                    route: route,
                    viewModel: lettersViewModel,
                    partnerName: profileViewModel.partnerProfile.displayName,
                    onReplyInChat: {
                        lettersViewModel.route = nil
                        selectedTab = .chat
                    }
                )
                .environmentObject(notificationViewModel)   // the reader reads permissionState
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
                    chatUnreadCounter.start(session: session)
                }
                notificationViewModel.setup(session: session)
                // Consent / ATT / ads start only once the main UI is up —
                // never during onboarding.
                AdsManager.shared.activate()
                if let live = sessionStore.session { lettersViewModel.rebind(session: live) }
                lettersViewModel.start()
            }
            .onChange(of: notificationViewModel.navigateToMood, initial: true) { _, navigate in
                if navigate { selectedTab = .mood; notificationViewModel.navigateToMood = false }
            }
            .onChange(of: notificationViewModel.navigateToDashboard, initial: true) { _, navigate in
                if navigate { selectedTab = .home; notificationViewModel.navigateToDashboard = false }
            }
            // A tapped capsule or crown reminder: Journey comes forward and
            // opens what the reminder is about. `initial` covers a cold
            // launch from the reminder, which sets it before this view exists.
            .onChange(of: notificationViewModel.journeyFocus, initial: true) { _, focus in
                guard let focus else { return }
                notificationViewModel.journeyFocus = nil
                selectedTab = .anniversary
                if pendingJourneyFocus != nil || lettersViewModel.route != nil || showStatsSheet {
                    // Handed over by the closing sheet's onDismiss (the
                    // latest reminder wins); the timer is the backstop if no
                    // sheet was really up.
                    pendingJourneyFocus = focus
                    lettersViewModel.route = nil
                    showStatsSheet = false
                    Task {
                        try? await Task.sleep(for: .seconds(1))
                        releasePendingJourneyFocus()
                    }
                } else {
                    journeyFocus = focus
                }
            }
            // A letter the user opens (or starts writing) supersedes a reminder
            // Journey hasn't handled yet, e.g. one still waiting for the
            // memories listener: otherwise the capsule's detail could try to
            // present over the letters sheet. The latest thing the user did wins.
            .onChange(of: lettersViewModel.route != nil) { _, isUp in
                guard isUp else { return }
                journeyFocus = nil
                pendingJourneyFocus = nil
            }
            .onChange(of: deepLinkRouter.pendingDestination) { _, destination in
                handleWidgetDestination(destination)
            }
            .onAppear { handleWidgetDestination(deepLinkRouter.pendingDestination) }
            // The streak only advances inside `loadStats`, which used to run
            // on cold launch and when the Stats sheet opened — nowhere else.
            // A day on which both partners checked in but neither relaunched
            // was never counted, and the next launch then reset the streak to
            // zero. Whoever checks in second now counts the day immediately.
            .onReceive(NotificationCenter.default.publisher(for: .coupleyMoodSaved)) { _ in
                if sessionStore.isPaired { statsViewModel.loadStats() }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                if sessionStore.isPaired { statsViewModel.loadStats() }
                // Idempotent; ends by moving the letters' clock to now.
                lettersViewModel.start()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                // Midnight, a time-zone change, DST, or a manual clock change.
                lettersViewModel.refreshClock()
            }
            .onChange(of: sessionStore.session?.coupleId) { _, _ in
                // Pairing, unpairing, and a switch from one couple to another
                // that keeps this view (and so its StateObjects) alive.
                if let live = sessionStore.session { lettersViewModel.rebind(session: live) }
            }
            .onChange(of: sessionStore.isPaired) { _, paired in
                if paired {
                    coupleViewModel.startListening()
                    statsViewModel.loadStats()
                    profileViewModel.startListening()
                    nudgeViewModel.startListening()
                    // Use the live session from sessionStore — the `session`
                    // captured in init is a stale snapshot from when the
                    // user was still solo (empty coupleId/partnerId).
                    if let live = sessionStore.session {
                        chatUnreadCounter.start(session: live)
                    }
                } else {
                    chatUnreadCounter.stop()
                }
            }
    }

    // MARK: - Future letters

    /// The entry point Chat and Journey use (Home calls the view model
    /// directly, and hides its button when letters are unavailable). Returns
    /// false when there is no partner yet, after offering to connect one.
    @discardableResult
    private func writeLetter(seed: String? = nil, opensAt: Date? = nil) -> Bool {
        guard lettersViewModel.isAvailable else {
            showPairingSheet = true
            return false
        }
        lettersViewModel.compose(seed: seed, opensAt: opensAt)
        return true
    }

    // MARK: - Journey reminders

    /// Hands Journey a reminder's focus that waited for one of this view's
    /// sheets to slide away. A no-op when nothing is waiting.
    private func releasePendingJourneyFocus() {
        guard let focus = pendingJourneyFocus else { return }
        pendingJourneyFocus = nil
        journeyFocus = focus
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
                        Button {
                            dismiss()
                        } label: {
                            Text("Close", comment: "Button: close the connect-your-partner sheet")
                        }
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)

                        Spacer()

                        Button {
                            sessionStore.signOut()
                            dismiss()
                        } label: {
                            Text("Sign Out", comment: "Button: sign out of the account")
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
