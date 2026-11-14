//
//  CoupleDashboardView.swift
//  Coupley
//

import SwiftUI
import FirebaseFirestore

// MARK: - Couple Dashboard View

struct CoupleDashboardView: View {

    @ObservedObject var viewModel: CoupleViewModel
    @ObservedObject var statsViewModel: CoupleStatsViewModel
    @ObservedObject var profileViewModel: CouplePersonProfileViewModel
    @ObservedObject var microActionViewModel: MicroActionViewModel
    @ObservedObject var lettersViewModel: FutureLetterViewModel
    @Binding var showPairingSheet: Bool
    @Binding var showStatsSheet: Bool
    @Binding var selectedTab: AppTab

    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var premiumStore: PremiumStore
    @EnvironmentObject private var notificationViewModel: NotificationViewModel

    @State private var isSendingPing = false
    @State private var didSendPing = false
    @State private var showSettings = false
    @State private var showAvatarPicker = false
    @State private var showMyDetail = false
    @State private var showPartnerDetail = false
    @State private var showProfileHub = false
    @State private var limitReached: PremiumFeature?
    @State private var showAICoach = false
    @State private var sentReaction: ReactionKind? = nil
    @State private var sentLiveReaction: ReactionKind? = nil
    @State private var showTouchTogether = false
    /// Loaded from local storage on appear so the suggestion sheet opens with
    /// the real partner rather than the "Alex" fixture.
    @State private var suggestionProfile: PartnerProfile?
    @State private var isSendingReaction = false

    @StateObject private var aiCoachViewModel: AICoachViewModel = AICoachViewModel(session: .demo)
    @StateObject private var qotdViewModel: QuestionOfTheDayViewModel =
        QuestionOfTheDayViewModel(session: .demo)
    @StateObject private var dailyPhotoViewModel: DailyPhotoViewModel =
        DailyPhotoViewModel(session: .demo)
    /// Owned here, not built inside the sheet closure: a closure-built
    /// @ObservedObject is replaced on every dashboard re-render, and the
    /// partner's 60-second presence heartbeat guarantees those. The sheet
    /// would silently lose its listener about once a minute.
    @StateObject private var touchTogetherViewModel: TouchTogetherViewModel =
        TouchTogetherViewModel(session: .demo)

    private let reactionService: ReactionService = FirestoreReactionService()
    private let presenceService: PresenceService = FirestorePresenceService()
    private let nudgeService: NudgeServicing = FirestoreNudgeService()

    // MARK: - Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            // Explicit spacers, not a uniform VStack spacing: the gaps are
            // what encode grouping, so they cannot all be the same number.
            VStack(spacing: 0) {
                Color.clear.frame(height: 8)

                // ── T0 ────────────────────────────────────────────────────
                masthead
                    .padding(.horizontal, Brand.Space.gutter)

                // ── T0b ── pinned letters. The one sanctioned object between
                // the masthead and the hero, because the feature's promise is
                // "pinned on Home". One chip row (~56pt + 14pt), never hero
                // tier, never an accent wash, never an Eyebrow. A letter that
                // is ready for this user is the hero instead.
                if !pinnedLetters.isEmpty {
                    Color.clear.frame(height: Brand.Space.sibling)
                    FutureLetterPinnedRow(viewModel: lettersViewModel,
                                          partnerName: partnerName,
                                          includesReady: pinsReadyLetters)
                        .padding(.horizontal, Brand.Space.gutter)
                        .transition(.opacity)
                }

                // ── T1 ── the one hero. It sits directly under the masthead
                // because it has to be ABOVE THE FOLD to mean anything: the
                // visible box is ~674pt on an iPhone 15 once the tab bar and
                // the AdMob banner are subtracted, and anything below that is
                // hierarchy nobody sees.
                if homeHero != .none {
                    Color.clear.frame(height: Brand.Space.sibling)
                    heroSlot
                        .padding(.horizontal, SurfaceTier.hero.gutter)
                        .transition(.opacity)
                }

                // ── T4 ── us, ambient. No containers, one hairline each.
                Color.clear.frame(height: Brand.Space.zone)
                ambientZone
                    .padding(.horizontal, Brand.Space.gutter)

                // ── T2 ── the rest of today.
                if hasTodayZone {
                    Color.clear.frame(height: Brand.Space.zone)
                    todayZone
                        .padding(.horizontal, Brand.Space.gutter)
                }

                // ── T3 ── navigation, recessed below the content it leads to.
                Color.clear.frame(height: Brand.Space.zone)
                activitiesSection
                    .padding(.horizontal, Brand.Space.gutter)

                if !viewModel.weeklyHistory.isEmpty {
                    Color.clear.frame(height: Brand.Space.zone)
                    BrandCard(tier: .quiet) { weeklyHistorySection }
                        .padding(.horizontal, Brand.Space.gutter)
                }

                Color.clear.frame(height: 120)
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: homeHero)
            .animation(.spring(response: 0.45, dampingFraction: 0.85),
                       value: pinnedLetters.map(\.id))
        }
        .task { suggestionProfile = await viewModel.loadPartnerProfile() }
        .sheet(isPresented: $viewModel.showAISuggestions) {
            if let context = viewModel.suggestionContext {
                // Was `partnerProfile: .samplePartner` with no service, so the
                // sheet ran MockAISuggestionService against a fixture named
                // "Alex" while the real daily quota was being decremented.
                SuggestionView(
                    moodContext: context,
                    partnerProfile: suggestionProfile ?? .samplePartner,
                    suggestionService: HybridAISuggestionService()
                )
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView(session: sessionStore.session)
            }
            .environmentObject(sessionStore)
            .environmentObject(themeManager)
            .environmentObject(premiumStore)
            .environmentObject(notificationViewModel)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Brand.backgroundTop)
        }
        .sheet(isPresented: $showAvatarPicker) {
            AvatarPickerSheet(viewModel: profileViewModel)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Brand.backgroundTop)
        }
        .sheet(isPresented: $showMyDetail) {
            NavigationStack {
                PartnerProfileDetailView(
                    targetUserId: sessionStore.session?.userId ?? "",
                    currentUserId: sessionStore.session?.userId ?? "",
                    mode: .mine,
                    hasPartner: sessionStore.isPaired,
                    avatar: profileViewModel.myProfile.avatar,
                    displayName: profileViewModel.myProfile.displayName,
                    partnerPronounLabel: profileViewModel.partnerProfile.avatar.pronounLabel
                )
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Brand.backgroundTop)
        }
        .sheet(isPresented: $showPartnerDetail) {
            NavigationStack {
                PartnerProfileDetailView(
                    targetUserId: sessionStore.session?.partnerId ?? "",
                    currentUserId: sessionStore.session?.userId ?? "",
                    mode: .partner,
                    hasPartner: sessionStore.isPaired,
                    avatar: profileViewModel.partnerProfile.avatar,
                    displayName: profileViewModel.partnerProfile.displayName,
                    partnerPronounLabel: profileViewModel.partnerProfile.avatar.pronounLabel
                )
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Brand.backgroundTop)
        }
        .sheet(isPresented: $showProfileHub) {
            PartnerAndMeProfileView(
                profileViewModel: profileViewModel,
                session: sessionStore.session ?? .demo
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Brand.backgroundTop)
        }
        .sheet(isPresented: $showTouchTogether) {
            TouchTogetherView(
                partnerName: profileViewModel.partnerProfile.displayName,
                viewModel: touchTogetherViewModel
            )
            .presentationDetents([.large])
            .presentationBackground(Brand.backgroundTop)
        }
        .dailyLimitAlert($limitReached)
        .sheet(item: $qotdViewModel.quizBeingAnswered) { quiz in
            // Presented from here so it survives the question card moving
            // between the hero slot and the today zone.
            QuizAnswerSheet(
                quiz: quiz,
                partnerName: partnerName,
                onSubmit: { qotdViewModel.submit(answer: $0, for: quiz) },
                onCancel: { qotdViewModel.quizBeingAnswered = nil },
                submitFailed: qotdViewModel.submitError != nil
            )
            .alert("Couldn't send your answer", isPresented: Binding(
                get: { qotdViewModel.submitError != nil },
                set: { if !$0 { qotdViewModel.dismissError() } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Check your connection and try again. Your choices are still here.")
            }
            .presentationDetents([.medium, .large])
            .presentationBackground(Brand.backgroundTop)
        }
        .sheet(isPresented: $showAICoach) {
            NavigationStack {
                AICoachHomeView(viewModel: aiCoachViewModel)
            }
            .environmentObject(premiumStore)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Brand.backgroundTop)
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85),
                   value: viewModel.partnerIsOnline)
        #if DEBUG
        .task { await openLaunchArgumentScreen() }
        #endif
        // `onAppear` does not fire when a suspended app comes back, so an app
        // left open overnight kept showing yesterday's finished question until
        // someone switched tabs. Both calls are throttled and idempotent.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            qotdViewModel.start()
            dailyPhotoViewModel.start()
        }
        .onAppear {
            viewModel.startListening()
            if let s = sessionStore.session {
                aiCoachViewModel.rebind(session: s)
                qotdViewModel.rebind(session: s)
                dailyPhotoViewModel.rebind(session: s)
            }
            qotdViewModel.start()
            dailyPhotoViewModel.start()
            aiCoachViewModel.updateContext(
                myName: profileViewModel.myProfile.displayName,
                partnerName: profileViewModel.partnerProfile.displayName,
                partnerProfile: nil,
                recentMoodNote: viewModel.partnerMood?.note
            )
        }
        .onDisappear { viewModel.stopListening() }
    }

    // MARK: - Masthead (T0)

    /// The buttons get their own row so the headline can run the full measure.
    /// A 34pt line beside two 36pt circles would have to wrap at 2 words.
    private var masthead: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                mastheadButtons
            }

            Eyebrow(dateline)
                .padding(.top, 8)

            // The screen's ceiling used to be 22pt. At 34pt this is the only
            // thing the eye can land on first, and because it lives in the one
            // view that renders unconditionally it can never go missing.
            Text(heroHeadline)
                .font(BrandType.display)
                .foregroundStyle(Brand.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)

            if let heroStandfirst {
                Text(heroStandfirst)
                    .font(BrandType.meta)
                    .foregroundStyle(Brand.textSecondary)
                    // One line in English; German and Russian run 30-50%
                    // longer, and a truncated standfirst loses its point.
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var mastheadButtons: some View {
        HStack(alignment: .center, spacing: 10) {
            if lettersViewModel.isAvailable {
                writeLetterHeaderButton
            }

            aiCoachHeaderButton

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showSettings = true
            } label: {
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        Circle()
                            .fill(Brand.surfaceLight)
                            .frame(width: 36, height: 36)
                            .overlay(Circle().strokeBorder(Brand.divider, lineWidth: 1))
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Brand.textPrimary)
                    }
                    if notificationViewModel.unreadCount > 0 {
                        Circle()
                            .fill(Brand.accentStart)
                            .frame(width: 9, height: 9)
                            .overlay(Circle().strokeBorder(Brand.backgroundTop, lineWidth: 1.5))
                            .offset(x: 2, y: -2)
                    }
                }
            }
            .buttonStyle(BouncyButtonStyle(scale: 0.92))
        }
    }

    /// One tap to a new future letter, always above the fold. Outlined like
    /// Settings, so the hero's CTA stays the screen's one filled accent; the
    /// amber glyph matches the pinned row the letter will create. The letter
    /// sheet itself is presented by ContentView.
    private var writeLetterHeaderButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            lettersViewModel.compose()
        } label: {
            ZStack {
                Circle()
                    .fill(Brand.surfaceLight)
                    .frame(width: 36, height: 36)
                    .overlay(Circle().strokeBorder(Brand.divider, lineWidth: 1))
                Image(systemName: "envelope.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(FutureLetterStyle.accent)
            }
        }
        .buttonStyle(BouncyButtonStyle(scale: 0.92))
        .accessibilityLabel("Write a future letter")
        .contextMenu {
            Button(LocalizedStringResource("All letters",
                                           comment: "Context menu on Home's envelope button: open the list of future letters"),
                   systemImage: "tray.full") { lettersViewModel.openHub() }
        }
    }

    private var aiCoachHeaderButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            openAICoach()
        } label: {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.95, green: 0.55, blue: 0.72),
                                Color(red: 0.52, green: 0.44, blue: 0.95)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                    .shadow(color: Color(red: 0.95, green: 0.55, blue: 0.72).opacity(0.35), radius: 10, y: 3)

                Image(systemName: "sparkle")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(BouncyButtonStyle(scale: 0.92))
        .accessibilityLabel("AI Relationship Coach")
    }

    private func openAICoach() {
        if let s = sessionStore.session { aiCoachViewModel.rebind(session: s) }
        aiCoachViewModel.updateContext(
            myName: profileViewModel.myProfile.displayName,
            partnerName: profileViewModel.partnerProfile.displayName,
            partnerProfile: nil,
            recentMoodNote: viewModel.partnerMood?.note
        )
        showAICoach = true
    }

    private var partnerName: String { profileViewModel.partnerProfile.displayName }

    private static let datelineFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return f
    }()

    private var dateline: String {
        Self.datelineFormatter.string(from: Date())
    }

    // MARK: - Hero resolution

    /// Which single block is today's job.
    ///
    /// Tier is a function of state, never of scroll position, so QotD, Photo
    /// and TogetherNow can all render nothing and the hierarchy is unchanged.
    /// A ready letter is the hero unless the two of them are here right now;
    /// then it is pinned, so it never drops out of sight.
    private var pinsReadyLetters: Bool { homeHero == .togetherNow }

    private var pinnedLetters: [FutureLetter] {
        lettersViewModel.pinnedLetters(includingReady: pinsReadyLetters)
    }

    private enum HomeHero: Equatable {
        case letter, togetherNow, question, photo, microAction, mood, none
    }

    private var homeHero: HomeHero {
        // Co-presence first: it is the only thing on this screen that is true
        // *right now* rather than true all day.
        if viewModel.partnerIsOnline { return .togetherNow }

        // A letter that has reached its moment: it waited days or years for
        // this, it happens once, and only its reader can do the job, so it
        // must not be missable. It yields only to the two of them being here
        // at once, which passes; then it is pinned first, right above.
        if lettersViewModel.heroLetter != nil { return .letter }

        // Something still to do.
        if case .awaitingMe = qotdViewModel.state       { return .question }
        if case .awaitingMe = dailyPhotoViewModel.state { return .photo }

        // The day's payoff. Falling through these is what used to put a 230pt
        // micro-action in the hero slot while a 290pt photo reveal sat below
        // it at card tier — tier and visual mass disagreeing, and mass wins.
        if case .complete = qotdViewModel.state         { return .question }
        if case .revealed = dailyPhotoViewModel.state   { return .photo }

        // Only ever promote an action that can still be acted on. A
        // struck-through finished task wrapped in the screen's only accent
        // wash is the exact inversion of what this slot is for.
        if microActionViewModel.todaysActions.contains(where: { $0.isActionable }) {
            return .microAction
        }

        if case .available = viewModel.partnerMoodState { return .mood }

        // Nothing is pending. Rather than dress up an apology — emptyMoodCard
        // is "Waiting for your partner", with no CTA — the slot collapses and
        // the masthead carries the screen alone. An empty day should look empty.
        return .none
    }

    private var heroHeadline: LocalizedStringResource {
        switch homeHero {
        case .letter:
            let count = lettersViewModel.readyForMeCount
            return count > 1 ? "\(count) letters for you." : "A letter for you."
        case .togetherNow: return "You're both here."
        case .question:
            if case .awaitingMe = qotdViewModel.state { return "One question today." }
            return "Your answers are in."
        case .photo:
            if case .awaitingMe = dailyPhotoViewModel.state { return "One photo today." }
            return "Today, side by side."
        case .microAction: return "One small thing."
        case .mood:        return "\(partnerName) checked in."
        case .none:        return "All done for today."
        }
    }

    /// nil only in a state the resolver never produces (a letter hero with no
    /// letter); the masthead then drops the line instead of drawing an empty one.
    private var heroStandfirst: LocalizedStringResource? {
        switch homeHero {
        case .letter:
            return lettersViewModel.heroLetter.map { letterStandfirst(for: $0) }
        case .togetherNow: return "Reach for them while they are here"
        case .question:
            if case .awaitingMe = qotdViewModel.state { return "Answer blind, then compare" }
            return "See how the two of you lined up"
        case .photo:
            if case .awaitingMe = dailyPhotoViewModel.state { return "Send yours to unlock theirs" }
            return "Both of you, the same moment"
        case .microAction: return "A gentle idea, just for you"
        case .mood:        return "Here is how their day is going"
        case .none:        return "Nothing waiting — enjoy the quiet"
        }
    }

    /// "Sam sealed it yesterday", as whole sentences.
    ///
    /// Was a frame with `FutureLetterClock.sealedPhrase` ("today", "yesterday",
    /// "on Nov 13") spliced into it, which hands a translator the day word with
    /// no sentence around it. Same buckets, same English, one key per sentence.
    private func letterStandfirst(for letter: FutureLetter) -> LocalizedStringResource {
        let sealed = letter.sealedMoment
        let now = lettersViewModel.now
        let calendar = Calendar.current
        let several = lettersViewModel.readyForMeCount > 1

        if calendar.isDate(sealed, inSameDayAs: now) {
            return several
                ? LocalizedStringResource("From \(partnerName), the first sealed today",
                                          comment: "Home, under 'N letters for you.'; the placeholder is the partner's name")
                : LocalizedStringResource("\(partnerName) sealed it today",
                                          comment: "Home, under 'A letter for you.'; the placeholder is the partner's name")
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(sealed, inSameDayAs: yesterday) {
            return several
                ? LocalizedStringResource("From \(partnerName), the first sealed yesterday",
                                          comment: "Home, under 'N letters for you.'; the placeholder is the partner's name")
                : LocalizedStringResource("\(partnerName) sealed it yesterday",
                                          comment: "Home, under 'A letter for you.'; the placeholder is the partner's name")
        }
        let date = FutureLetterClock.shortDate(sealed, now: now, calendar: calendar)
        return several
            ? LocalizedStringResource("From \(partnerName), the first sealed on \(date)",
                                      comment: "Home, under 'N letters for you.'; partner's name, then a short date such as 'Nov 13'")
            : LocalizedStringResource("\(partnerName) sealed it on \(date)",
                                      comment: "Home, under 'A letter for you.'; partner's name, then a short date such as 'Nov 13'")
    }

    // MARK: - Hero slot (T1)

    @ViewBuilder
    private var heroSlot: some View {
        switch homeHero {
        case .letter:
            if let letter = lettersViewModel.heroLetter {
                FutureLetterHeroCard(
                    letter: letter,
                    partnerName: partnerName,
                    moreReady: lettersViewModel.readyForMeCount - 1,
                    now: lettersViewModel.now,
                    onOpen: { lettersViewModel.show(letter) }
                )
            }
        case .togetherNow:
            TogetherNowCard(
                partnerName: partnerName,
                sentReaction: sentLiveReaction,
                onSend: sendLiveReaction,
                onTouchTogether: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    if let s = sessionStore.session {
                        touchTogetherViewModel.rebind(session: s)
                    }
                    showTouchTogether = true
                },
                tier: .hero
            )
        case .question:
            QuestionOfTheDayCard(viewModel: qotdViewModel, partnerName: partnerName, tier: .hero)
        case .photo:
            DailyPhotoCard(viewModel: dailyPhotoViewModel, partnerName: partnerName, tier: .hero)
        case .microAction:
            MicroActionCard(viewModel: microActionViewModel, tier: .hero)
        case .mood:
            partnerMoodSection(tier: .hero)
        case .none:
            EmptyView()
        }
    }

    // MARK: - Zones

    private var showsQotDBelow:  Bool { homeHero != .question && qotdViewModel.state != .hidden }
    private var showsPhotoBelow: Bool { homeHero != .photo && dailyPhotoViewModel.state != .hidden }
    private var showsMicroBelow: Bool { homeHero != .microAction }
    private var showsMoodBelow:  Bool { homeHero != .mood }

    private var hasTodayZone: Bool {
        showsQotDBelow || showsPhotoBelow || showsMicroBelow || showsMoodBelow
    }

    /// Everything today still holds, at card tier. The spacers are conditional
    /// because both daily cards return `EmptyView` when hidden, and an
    /// unconditional spacer around nothing is just dead air the size of a gap
    /// that is supposed to mean something.
    @ViewBuilder
    private var todayZone: some View {
        VStack(spacing: Brand.Space.sibling) {
            if showsQotDBelow {
                QuestionOfTheDayCard(viewModel: qotdViewModel, partnerName: partnerName)
            }
            if showsPhotoBelow {
                DailyPhotoCard(viewModel: dailyPhotoViewModel, partnerName: partnerName)
            }
            if showsMicroBelow {
                MicroActionCard(viewModel: microActionViewModel)
            }
            if showsMoodBelow {
                partnerMoodSection(tier: .card)
            }
        }
    }

    /// Ambient readouts: true, but not a job. No containers at all — contrast
    /// is a ratio, and deleting the denominator is what lets the hero read.
    @ViewBuilder
    private var ambientZone: some View {
        VStack(spacing: Brand.Space.sibling) {
            BrandCard(tier: .quiet) { coupleAvatarsAndStats }
            if homeHero != .togetherNow {
                BrandCard(tier: .quiet) { presenceRow }
            }
        }
    }

    // MARK: - Avatars + Stats Row

    private var coupleAvatarsAndStats: some View {
        HStack(alignment: .center, spacing: 14) {
            avatarTile(
                profile: profileViewModel.myProfile,
                tappable: true,
                editAction: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showAvatarPicker = true
                }
            ) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showMyDetail = true
            }

            avatarTile(
                profile: profileViewModel.partnerProfile,
                tappable: sessionStore.isPaired,
                editAction: nil
            ) {
                guard sessionStore.isPaired else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showPartnerDetail = true
            }
            .opacity(sessionStore.isPaired ? 1 : 0.55)

            statsPreviewCompact
        }
        // statsPreviewCompact is this HStack's only flexible child; both
        // avatar tiles are hard-pinned. Without this the pair would re-centre
        // itself under a leading-aligned masthead if the stats chip ever
        // stopped rendering.
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func avatarTile(
        profile: CouplePersonProfile,
        tappable: Bool,
        editAction: (() -> Void)?,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                Button(action: action) {
                    ZStack {
                        Circle()
                            .fill(Brand.backgroundTop)
                            .overlay(Circle().strokeBorder(Brand.divider, lineWidth: 1))
                        profile.avatar.image()
                            .clipShape(Circle())
                            .padding(3)
                    }
                    .frame(width: 72, height: 72)
                }
                .buttonStyle(BouncyButtonStyle(scale: tappable ? 0.94 : 1))
                .disabled(!tappable)

                if let editAction {
                    Button(action: editAction) {
                        // Neutral, not accent. This badge used to be the most
                        // saturated object above the fold, so the eye landed
                        // on a 24pt edit affordance before anything else.
                        Circle()
                            .fill(Brand.surfaceMid)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Image(systemName: "pencil")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Brand.textSecondary)
                            )
                            .overlay(Circle().strokeBorder(Brand.backgroundTop, lineWidth: 2))
                    }
                    .buttonStyle(BouncyButtonStyle(scale: 0.9))
                }
            }

            Text(profile.displayName)
                .font(BrandType.meta)
                .foregroundStyle(Brand.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        // Was maxWidth: .infinity. Two tiles each taking everything they
        // could left the stats box ~50pt of text width, which is why
        // "check-ins" clipped on every device at the default text size.
        // Was also 92pt, which made a static avatar pair the largest object
        // on the screen — visual mass beats type size, so no headline could
        // outrank it no matter how big it got set.
        .frame(width: 72)
    }

    private var statsPreviewCompact: some View {
        let streak = shownStats.streak
        let checkIns = shownStats.checkIns
        return VStack(alignment: .leading, spacing: 8) {
            statsLine(
                icon: "flame.fill",
                iconColor: Color(red: 1.0, green: 0.55, blue: 0.20),
                value: streak.formatted(),
                label: Text(verbatim: Self.streakCaption(streak))
            )
            Divider().opacity(0.6)
            statsLine(
                icon: "arrow.triangle.2.circlepath",
                iconColor: Brand.accentStart,
                value: shownStats.syncScore.map {
                    String(localized: "\($0)%", comment: "Home stats chip: today's mood sync score as a percentage, e.g. 72%")
                } ?? "--",
                label: Text("sync",
                            comment: "Home stats chip caption beside a percentage: how in sync your moods are today")
            )
            Divider().opacity(0.6)
            statsLine(
                icon: "calendar",
                iconColor: Color(red: 0.40, green: 0.70, blue: 1.0),
                value: checkIns.formatted(),
                label: Text(verbatim: Self.checkInsCaption(checkIns))
            )
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        // The block around this is now container-less, so a 0.6-alpha fill of
        // the page's own background colour would have read as nothing at all.
        .background(
            RoundedRectangle(cornerRadius: 14, style: Brand.cornerStyle)
                .fill(Brand.surfaceLight)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: Brand.cornerStyle)
                        .strokeBorder(Brand.divider, lineWidth: 1)
                )
        )
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showStatsSheet = true
        }
    }

    /// The three numbers in the stats chip. Screenshot builds
    /// (`-coupleyDemoData`, Debug) show a lived-in couple instead of zeros.
    private var shownStats: (streak: Int, syncScore: Int?, checkIns: Int) {
        #if DEBUG
        if DemoContent.current != nil { return (12, 86, 5) }
        #endif
        return (statsViewModel.streak.currentStreak,
                statsViewModel.todaySyncScore?.score,
                viewModel.weeklyHistory.count)
    }

    /// "streak" in a form that agrees with the count of days drawn before it.
    private static func streakCaption(_ days: Int) -> String {
        CountedCaption.removingCount(from: String(
            localized: "home.stats.streakDays",
            defaultValue: "\(days) streak",
            comment: "Home stats chip: how many days in a row you both checked in. The number is drawn in bold just before this text and the app removes it from here, so keep %lld and write each plural form to read naturally without the number ('%lld streak' shows as 'streak'; Russian '%lld дней подряд' shows as 'дней подряд')."))
    }

    /// "check-ins" in a form that agrees with the count drawn before it.
    private static func checkInsCaption(_ count: Int) -> String {
        // Its own key: "%lld check-ins" already means ticking off a
        // challenge, which several languages word differently.
        CountedCaption.removingCount(from: String(
            localized: "home.stats.moodCheckIns",
            defaultValue: "\(count) check-ins",
            comment: "Home stats chip: your partner's MOOD check-ins this week (not challenge check-ins). The number is drawn in bold just before this text and the app removes it from here, so keep %lld and write each plural form to read naturally without the number ('%lld check-ins' shows as 'check-ins')."))
    }

    private func statsLine(icon: String, iconColor: Color, value: String, label: Text) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 14)

            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Brand.textPrimary)

            label
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Brand.textSecondary)
                // Wraps before it truncates: most languages run longer than
                // "check-ins" in a box this narrow.
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 0)
        }
    }

    // MARK: - Activities

    private var activitiesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Not an Eyebrow: the dateline is the screen's only uppercase
            // tracked label, so that signal keeps meaning one thing.
            Text("Our Activities")
                .font(BrandType.label)
                .foregroundStyle(Brand.textTertiary)
                .padding(.leading, 4)
                .padding(.bottom, 2)

            HStack(spacing: 10) {
                activityCard(
                    icon: "heart.fill",
                    tint: Brand.accentStart,
                    title: LocalizedStringResource("Mood", comment: "Home activity tile: opens the Mood tab"),
                    subtitle: "Share today"
                ) { selectedTab = .mood }

                activityCard(
                    icon: "bubble.left.and.bubble.right.fill",
                    tint: Color(red: 0.40, green: 0.70, blue: 1.0),
                    title: LocalizedStringResource("Couple Chat", comment: "Home activity tile: opens the chat tab"),
                    subtitle: "Talk together"
                ) { selectedTab = .chat }
            }

            HStack(spacing: 10) {
                activityCard(
                    icon: "sparkles",
                    tint: Color(red: 1.0, green: 0.55, blue: 0.20),
                    title: LocalizedStringResource("Date Ideas", comment: "Home activity tile: AI date suggestions"),
                    subtitle: "Plan a night"
                ) {
                    if !premiumStore.hasAccess(to: .dateIdeas) {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        limitReached = .dateIdeas
                        return
                    }
                    if let mood = viewModel.partnerMood {
                        premiumStore.recordUsage(for: .dateIdeas)
                        viewModel.suggestionContext = mood.toMoodContext()
                        viewModel.showAISuggestions = true
                    }
                }
                .opacity(viewModel.partnerMood == nil ? 0.55 : 1)
                .disabled(viewModel.partnerMood == nil)

                activityCard(
                    icon: "chart.bar.fill",
                    tint: Color(red: 0.50, green: 0.40, blue: 1.0),
                    title: LocalizedStringResource("Our Stats", comment: "Home activity tile: opens the couple's streak and sync stats"),
                    subtitle: "Track progress"
                ) { showStatsSheet = true }
            }

            HStack(spacing: 10) {
                activityCard(
                    icon: "heart.text.square.fill",
                    tint: Color(red: 1.0, green: 0.40, blue: 0.55),
                    title: LocalizedStringResource("Profile", comment: "Home activity tile: opens both partners' profiles (likes, dislikes)"),
                    subtitle: "Likes, dislikes & more"
                ) { showProfileHub = true }

                activityCard(
                    icon: "envelope.fill",
                    tint: FutureLetterStyle.accent,
                    title: LocalizedStringResource("Future Letters", comment: "Home activity tile: letters sealed until a chosen date"),
                    subtitle: "Sealed until a day you choose"
                ) {
                    if lettersViewModel.isAvailable {
                        lettersViewModel.openHub()
                    } else {
                        showPairingSheet = true
                    }
                }
            }

            aiCoachActivityCard
        }
    }

    private var aiCoachActivityCard: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            openAICoach()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.95, green: 0.55, blue: 0.72),
                                    Color(red: 0.52, green: 0.44, blue: 0.95)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                        .shadow(color: Color(red: 0.95, green: 0.55, blue: 0.72).opacity(0.35), radius: 10, y: 3)
                    Image(systemName: "sparkle")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("AI Relationship Coach")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(Brand.textPrimary)
                        Text("NEW", comment: "Badge on the AI coach card: the feature is new. Keep it short, capitals")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .scriptAwareTracking(0.4)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [Brand.accentStart, Brand.accentEnd],
                                            startPoint: .leading, endPoint: .trailing
                                        )
                                    )
                            )
                    }

                    Text("Help us solve this — together")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Brand.accentStart)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Brand.surfaceLight)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.95, green: 0.55, blue: 0.72).opacity(0.55),
                                        Color(red: 0.52, green: 0.44, blue: 0.95).opacity(0.40)
                                    ],
                                    startPoint: .leading, endPoint: .trailing
                                ),
                                lineWidth: 1.5
                            )
                    )
                    .shadow(color: .black.opacity(0.08), radius: 10, y: 3)
            )
        }
        .buttonStyle(BouncyButtonStyle(scale: 0.96))
    }

    /// - Parameter subtitle: Not drawn (see the body). Deliberately left a
    ///   plain `String`, so the string catalog does not extract copy nobody
    ///   sees and translators are not paid for it.
    private func activityCard(
        icon: String,
        tint: Color,
        title: LocalizedStringResource,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            // The subtitles are gone. "Couple Chat / Talk together" and
            // "Our Stats / Track progress" said the title twice and cost five
            // rows of height that the hero needed.
            BrandCard(tier: .chip) {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 26, height: 26)

                    Text(title)
                        .font(BrandType.label)
                        .foregroundStyle(Brand.textPrimary)
                        // Half-width tile: "Unsere Statistiken" needs a
                        // second line rather than an ellipsis.
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)

                    Spacer(minLength: 0)
                }
            }
        }
        .buttonStyle(BouncyButtonStyle(scale: 0.96))
    }

    // MARK: - Partner Mood

    @ViewBuilder
    private func partnerMoodSection(tier: SurfaceTier) -> some View {
        VStack(spacing: 0) {
            switch viewModel.partnerMoodState {
            case .unknown:   emptyMoodCard
            case .loading:   loadingMoodCard
            case .available(let entry): liveMoodCard(entry: entry, tier: tier)
            // A placeholder and an error may never be hero, whatever the
            // resolver says: neither is a job and neither has a CTA.
            case .error(let msg): errorMoodCard(message: msg)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: viewModel.partnerMoodState)
    }

    private var emptyMoodCard: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Brand.accentStart.opacity(0.10))
                    .frame(width: 72, height: 72)
                Image(systemName: "heart.text.square")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(Brand.accentStart.opacity(0.70))
            }

            VStack(spacing: 6) {
                Text("Waiting for your partner")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)

                // No hardcoded "\n": it would become part of the catalog key,
                // and every language breaks this line in a different place.
                Text("Their mood will appear here once they check in today")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Brand.surfaceLight)
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Brand.divider, lineWidth: 1))
                .shadow(color: .black.opacity(0.16), radius: 18, y: 5)
        )
    }

    private var loadingMoodCard: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(Brand.accentStart)
                .controlSize(.regular)
            Text("Connecting…")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Brand.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Brand.surfaceLight)
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Brand.divider, lineWidth: 1))
        )
    }

    private func liveMoodCard(entry: SharedMoodEntry, tier: SurfaceTier = .card) -> some View {
        let isHero = tier == .hero
        return VStack(spacing: isHero ? 20 : 14) {
            HStack {
                Text("\(partnerName)'s mood")
                    .font(BrandType.label)
                    .foregroundStyle(Brand.textSecondary)

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                    Text(entry.relativeTimestamp)
                        .font(BrandType.meta)
                }
                .foregroundStyle(Brand.textTertiary)
            }

            VStack(spacing: isHero ? 14 : 10) {
                // 72pt made a demoted mood card the biggest object on the
                // screen, out-massing both the masthead and the hero title.
                Text(entry.moodValue.emoji)
                    .font(.system(size: isHero ? 60 : 34))
                    .shadow(color: moodColor(entry).opacity(0.35), radius: 20, y: 6)

                Text(entry.moodValue.label)
                    .font(isHero ? BrandType.hero : BrandType.title)
                    .foregroundStyle(Brand.textPrimary)

                HStack(spacing: 6) {
                    Image(systemName: entry.energyValue.icon)
                        .font(.system(size: 12, weight: .semibold))
                    Text(energyPhrase(entry.energyValue))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                }
                .foregroundStyle(Brand.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(moodColor(entry).opacity(0.12))
                        .overlay(Capsule().strokeBorder(moodColor(entry).opacity(0.25), lineWidth: 1))
                )
            }

            if let note = entry.note, !note.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "quote.opening")
                        .font(.system(size: 12))
                        .foregroundStyle(Brand.textTertiary)
                        .padding(.top, 2)

                    Text(note)
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)
                        .italic()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineSpacing(2)
                }
                .padding(14)
                // A nested panel is always one step DOWN its own card's
                // ladder. This used to fill surfaceLight on a surfaceLight
                // card — a 1pt outline around nothing.
                .wellBackground(in: tier, radius: 12)
            }

            reactionBar(for: entry)

            if entry.needsAttention {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    if !premiumStore.hasAccess(to: .aiMoodSuggestions) {
                        limitReached = .aiMoodSuggestions
                        return
                    }
                    premiumStore.recordUsage(for: .aiMoodSuggestions)
                    viewModel.openSuggestions()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Get Suggestions")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Spacer()
                        Text("\(premiumStore.remainingUsage(for: .aiMoodSuggestions)) left today")
                            .font(.system(size: 12, design: .rounded))
                            .opacity(0.8)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Brand.accentGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: Brand.accentStart.opacity(0.35), radius: 12, y: 4)
                }
                .buttonStyle(BouncyButtonStyle())
            }
        }
        .modifier(TierContainer(tier: tier))
    }

    private func errorMoodCard(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(Brand.textTertiary)

            Text("Connection issue")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Brand.textSecondary)

            Button("Retry") {
                viewModel.stopListening()
                viewModel.startListening()
            }
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(Brand.accentStart)
            .padding(.horizontal, 20)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(Brand.accentStart.opacity(0.10))
                    .overlay(Capsule().strokeBorder(Brand.accentStart.opacity(0.30), lineWidth: 1))
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Brand.surfaceLight)
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Brand.divider, lineWidth: 1))
        )
    }

    // MARK: - Attention Banner

    // MARK: - Presence Row

    private var presenceRow: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(viewModel.partnerIsOnline
                          ? Color(red: 0.25, green: 0.85, blue: 0.55).opacity(0.18)
                          : Brand.surfaceLight)
                    .frame(width: 38, height: 38)

                Circle()
                    .fill(viewModel.partnerIsOnline
                          ? Color(red: 0.25, green: 0.85, blue: 0.55)
                          : Brand.textTertiary)
                    .frame(width: 10, height: 10)
            }

            VStack(alignment: .leading, spacing: 2) {
                // Was the literal string "Partner" while the avatar directly
                // above it, the question card and the photo card all used the
                // real name — one person, two names, one screen.
                Text(partnerName)
                    .font(BrandType.label)
                    .foregroundStyle(Brand.textPrimary)
                    .lineLimit(1)

                Text(presenceSubtitle)
                    .font(BrandType.meta)
                    .foregroundStyle(Brand.textSecondary)
            }

            Spacer()

            Button(action: sendThinkingOfYou) {
                HStack(spacing: 6) {
                    if isSendingPing {
                        ProgressView().tint(.white).controlSize(.small)
                    } else {
                        Image(systemName: didSendPing ? "checkmark" : "heart.fill")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    Text(didSendPing
                         ? LocalizedStringResource("Sent", comment: "Ping button just after sending: the ping went through")
                         : LocalizedStringResource("Ping", comment: "Button: send your partner a 'thinking of you' ping"))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                // Outlined, not filled. The accent used to appear on the Ping
                // pill, the Answer button, the Send button, the Done button
                // and the AI banner at once — an accent that is everywhere
                // points at nothing. The hero's CTA is now the only accent
                // fill on the screen.
                .foregroundStyle(Brand.accentStart)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    Capsule()
                        .fill(Brand.surfaceLight)
                        .overlay(Capsule().strokeBorder(Brand.accentStart.opacity(0.45), lineWidth: 1))
                )
            }
            .buttonStyle(BouncyButtonStyle())
            .disabled(isSendingPing || didSendPing || !isRealSession)
        }
    }

    private var presenceSubtitle: LocalizedStringResource {
        if viewModel.partnerIsOnline {
            return LocalizedStringResource("Active now", comment: "Home presence row: your partner has the app open")
        }
        guard let lastSeen = viewModel.partnerLastSeen else {
            return LocalizedStringResource("No recent activity", comment: "Home presence row: your partner has not been seen lately")
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = RelativeDateTimeFormatter.compactUnitsStyle
        let relative = formatter.localizedString(for: lastSeen, relativeTo: Date())
        // One key with the relative time as its argument. Was "Last seen " +
        // the formatter's output: an English frame around a localized phrase.
        return LocalizedStringResource("Last seen \(relative)",
                                       comment: "Home presence row; the placeholder is a relative time such as '5 min. ago'")
    }

    private func sendThinkingOfYou() {
        guard let session = sessionStore.session, session.isPaired else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        isSendingPing = true
        Task {
            defer { isSendingPing = false }
            do {
                async let ping: () = presenceService.sendPing(coupleId: session.coupleId, fromUserId: session.userId)
                async let nudge: () = nudgeService.send(
                    coupleId: session.coupleId,
                    fromUserId: session.userId,
                    toUserId: session.partnerId,
                    kind: .ping,
                    reactionKind: nil
                )
                _ = try await (ping, nudge)
                withAnimation { didSendPing = true }
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                withAnimation { didSendPing = false }
            } catch {
                print("[Dashboard] Failed to send ping: \(error.localizedDescription)")
            }
        }
    }

    private var isRealSession: Bool {
        sessionStore.session?.isPaired ?? false
    }

    // MARK: - Reaction Bar

    private func reactionBar(for entry: SharedMoodEntry) -> some View {
        let isPaired = sessionStore.session?.isPaired ?? false
        return HStack(spacing: 8) {
            ForEach(ReactionKind.allCases) { kind in
                let isSent = sentReaction == kind
                Button {
                    guard !isSendingReaction, isPaired else { return }
                    sendReaction(kind, to: entry)
                } label: {
                    VStack(spacing: 4) {
                        Text(kind.emoji).font(.system(size: 22))
                        // Was `isSent ? "Sent!" : kind.label` with a String
                        // label, which made the whole ternary a String and
                        // drew "Sent!" verbatim, in English, everywhere.
                        Text(isSent
                             ? LocalizedStringResource("Sent!", comment: "Reaction button just after tapping it: the reaction was sent")
                             : kind.label)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(isSent ? Brand.accentStart : Brand.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(isSent
                                  ? Brand.accentStart.opacity(0.12)
                                  : Brand.surfaceLight)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(
                                        isSent ? Brand.accentStart.opacity(0.5) : Brand.divider,
                                        lineWidth: isSent ? 1.5 : 1
                                    )
                            )
                    )
                    .opacity((!isPaired || (isSendingReaction && !isSent)) ? 0.45 : 1)
                }
                .buttonStyle(BouncyButtonStyle())
                .disabled(!isPaired || isSendingReaction)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSent)
            }
        }
    }

    /// Fires a reaction straight at the partner while they are on screen.
    /// Unlike `sendReaction(_:to:)` this is not tied to a mood entry — there
    /// is nothing to attach it to, the point is the live moment itself.
    private func sendLiveReaction(_ kind: ReactionKind) {
        guard let session = sessionStore.session, session.isPaired else { return }
        withAnimation { sentLiveReaction = kind }

        Task {
            do {
                try await nudgeService.send(
                    coupleId: session.coupleId,
                    fromUserId: session.userId,
                    toUserId: session.partnerId,
                    kind: .reaction,
                    reactionKind: kind
                )
            } catch {
                print("[Dashboard] Live reaction failed: \(error.localizedDescription)")
            }
            // Return to the picker so they can send another.
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            withAnimation { sentLiveReaction = nil }
        }
    }

    private func sendReaction(_ kind: ReactionKind, to entry: SharedMoodEntry) {
        guard let session = sessionStore.session, session.isPaired else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        isSendingReaction = true
        sentReaction = kind
        Task {
            do {
                async let reaction: () = reactionService.sendReaction(
                    coupleId: session.coupleId,
                    moodId: entry.documentId,
                    userId: session.userId,
                    kind: kind
                )
                async let nudge: () = nudgeService.send(
                    coupleId: session.coupleId,
                    fromUserId: session.userId,
                    toUserId: session.partnerId,
                    kind: .reaction,
                    reactionKind: kind
                )
                _ = try await (reaction, nudge)
            } catch {
                print("[Dashboard] Failed to send reaction: \(error.localizedDescription)")
                sentReaction = nil
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation { sentReaction = nil }
            isSendingReaction = false
        }
    }

    // MARK: - Weekly History

    private var weeklyHistorySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Past 7 days")
                    .font(BrandType.label)
                    .foregroundStyle(Brand.textTertiary)

                Spacer()

                Text("\(viewModel.weeklyHistory.count) check-ins")
                    .font(BrandType.meta)
                    .foregroundStyle(Brand.textTertiary)
            }

            HStack(spacing: 8) {
                ForEach(weekDays, id: \.self) { date in
                    historyCell(for: date)
                }
            }
        }
    }

    private var weekDays: [Date] {
        let cal = Calendar.current
        return (0..<7).reversed().compactMap {
            cal.date(byAdding: .day, value: -$0, to: cal.startOfDay(for: Date()))
        }
    }

    private func historyCell(for date: Date) -> some View {
        let cal = Calendar.current
        let entry = viewModel.weeklyHistory.first {
            cal.isDate($0.timestamp, inSameDayAs: date)
        }
        // The locale's abbreviated weekday ("Mon", "Th 2", "月"). Was a
        // hardcoded narrow "EEEEE": ambiguous single letters in German
        // ("M D M D F S S"), and a 2-3 character label in Vietnamese in a
        // cell sized for one. Also no longer a formatter per cell per render.
        let dayLabel = date.formatted(.dateTime.weekday(.abbreviated))

        return VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(entry.map { moodColor($0).opacity(0.18) } ?? Brand.surfaceLight)
                    .overlay(
                        Circle().strokeBorder(
                            entry.map { moodColor($0).opacity(0.45) } ?? Brand.divider,
                            lineWidth: 1
                        )
                    )
                    .frame(width: 36, height: 36)

                if let entry {
                    Text(entry.moodValue.emoji).font(.system(size: 18))
                } else {
                    Image(systemName: "minus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Brand.textTertiary)
                }
            }

            Text(dayLabel)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Brand.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    /// Whole phrases, not "\(level.label) energy": an adjective translated on
    /// its own cannot agree with a noun it has never seen ("énergie faible",
    /// "niedrige Energie").
    private func energyPhrase(_ level: EnergyLevel) -> LocalizedStringResource {
        switch level {
        case .low:
            return LocalizedStringResource("Low energy", comment: "Partner's energy level on the Home mood card")
        case .medium:
            return LocalizedStringResource("Medium energy", comment: "Partner's energy level on the Home mood card")
        case .high:
            return LocalizedStringResource("High energy", comment: "Partner's energy level on the Home mood card")
        }
    }

    private func moodColor(_ entry: SharedMoodEntry) -> Color {
        switch entry.moodValue {
        case .happy:   return Color(red: 0.25, green: 0.85, blue: 0.55)
        case .neutral: return Color(red: 0.40, green: 0.70, blue: 1.0)
        case .sad:     return Color(red: 0.50, green: 0.40, blue: 1.0)
        case .stressed: return Color(red: 1.0, green: 0.55, blue: 0.25)
        }
    }
}

#if DEBUG
// MARK: - Screenshot launch argument

extension CoupleDashboardView {

    /// DEBUG only, for automated localization screenshots: the screen named
    /// by the `-coupleyOpen coach|letters|compose` launch argument. Read once.
    private static let launchArgumentScreen: String? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-coupleyOpen"),
              arguments.indices.contains(flag + 1) else { return nil }
        return arguments[flag + 1]
    }()

    private static var didOpenLaunchArgumentScreen = false

    /// Opens that screen once per process, after Home has settled.
    private func openLaunchArgumentScreen() async {
        guard let screen = Self.launchArgumentScreen, !Self.didOpenLaunchArgumentScreen else { return }
        Self.didOpenLaunchArgumentScreen = true
        try? await Task.sleep(for: .seconds(1.5))
        switch screen {
        case "coach":   openAICoach()
        case "letters": lettersViewModel.openHub()
        case "compose": lettersViewModel.compose()
        default:        break
        }
    }
}
#endif

// MARK: - Preview

#Preview {
    ZStack {
        Brand.bgGradient.ignoresSafeArea()
        CoupleDashboardView(
            viewModel: CoupleViewModel(),
            statsViewModel: CoupleStatsViewModel(),
            profileViewModel: CouplePersonProfileViewModel(session: .demo),
            microActionViewModel: MicroActionViewModel(session: .demo),
            lettersViewModel: FutureLetterViewModel(session: .demo),
            showPairingSheet: .constant(false),
            showStatsSheet: .constant(false),
            selectedTab: .constant(.home)
        )
        .environmentObject(SessionStore())
    }
}
