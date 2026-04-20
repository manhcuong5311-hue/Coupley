//
//  CoupleDashboardView.swift
//  Coupley
//

import SwiftUI

// MARK: - Couple Dashboard View

struct CoupleDashboardView: View {

    @ObservedObject var viewModel: CoupleViewModel
    @ObservedObject var statsViewModel: CoupleStatsViewModel
    @Binding var showPairingSheet: Bool

    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var premiumStore: PremiumStore
    @EnvironmentObject private var notificationViewModel: NotificationViewModel

    @State private var isSendingPing = false
    @State private var didSendPing = false
    @State private var showSettings = false

    private let reactionService: ReactionService = FirestoreReactionService()
    private let presenceService: PresenceService = FirestorePresenceService()

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default:      return "Good night"
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Top safe area spacer
                Color.clear.frame(height: 60)

                headerSection
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)

                statsRow
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)

                presenceRow
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)

                partnerMoodSection
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)

                if !viewModel.weeklyHistory.isEmpty {
                    weeklyHistorySection
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                }

                if viewModel.partnerNeedsAttention {
                    attentionBanner
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                }

                // Bottom padding for tab bar + banner
                Color.clear.frame(height: 120)
            }
        }
        .sheet(isPresented: $viewModel.showAISuggestions) {
            if let context = viewModel.suggestionContext {
                SuggestionView(moodContext: context, partnerProfile: .samplePartner)
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
            .presentationDragIndicator(.visible)
            .presentationBackground(Brand.backgroundTop)
        }
        .onAppear { viewModel.startListening() }
        .onDisappear { viewModel.stopListening() }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(greetingText)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)

                Text("How are you\ntwo doing?")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                    .lineSpacing(2)
            }

            Spacer()

            // Live indicator + settings
            VStack(alignment: .trailing, spacing: 10) {
                connectionPill

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
    }

    // MARK: - Connection Pill

    private var connectionPill: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(viewModel.isListening ? Color(red: 0.25, green: 0.85, blue: 0.55) : Brand.textTertiary)
                .frame(width: 7, height: 7)

            Text(viewModel.isListening ? "Live" : "Offline")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(viewModel.isListening ? Color(red: 0.25, green: 0.85, blue: 0.55) : Brand.textTertiary)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(viewModel.isListening
                      ? Color(red: 0.25, green: 0.85, blue: 0.55).opacity(0.12)
                      : Brand.surfaceLight)
                .overlay(
                    Capsule().strokeBorder(
                        viewModel.isListening
                            ? Color(red: 0.25, green: 0.85, blue: 0.55).opacity(0.30)
                            : Brand.divider,
                        lineWidth: 1
                    )
                )
        )
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 12) {
            statCard(
                icon: "flame.fill",
                iconColor: Color(red: 1.0, green: 0.55, blue: 0.20),
                value: "\(statsViewModel.streak.currentStreak)",
                label: "day streak"
            )

            statCard(
                icon: "arrow.triangle.2.circlepath",
                iconColor: Brand.accentStart,
                value: statsViewModel.todaySyncScore.map { "\($0.score)%" } ?? "--",
                label: statsViewModel.todaySyncScore != nil ? "sync today" : "check in first"
            )
        }
    }

    private func statCard(icon: String, iconColor: Color, value: String, label: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(iconColor)

            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(Brand.textPrimary)

            Text(label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Brand.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Brand.surfaceLight)
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Brand.divider, lineWidth: 1))
                .shadow(color: .black.opacity(0.16), radius: 18, y: 5)
        )
    }

    // MARK: - Partner Mood

    private var partnerMoodSection: some View {
        VStack(spacing: 0) {
            switch viewModel.partnerMoodState {
            case .unknown:   emptyMoodCard
            case .loading:   loadingMoodCard
            case .available(let entry): liveMoodCard(entry: entry)
            case .error(let msg): errorMoodCard(message: msg)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: viewModel.partnerMoodState)
    }

    // MARK: - Empty State

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

                Text("Their mood will appear here\nonce they check in today")
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

    // MARK: - Loading State

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

    // MARK: - Live Mood Card

    private func liveMoodCard(entry: SharedMoodEntry) -> some View {
        VStack(spacing: 20) {
            // Header row
            HStack {
                Text("Partner's mood")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 11))
                    Text(entry.relativeTimestamp)
                        .font(.system(size: 12, design: .rounded))
                }
                .foregroundStyle(Brand.textTertiary)
            }

            // Mood display
            VStack(spacing: 14) {
                Text(entry.moodValue.emoji)
                    .font(.system(size: 72))
                    .shadow(color: moodColor(entry).opacity(0.35), radius: 20, y: 6)

                Text(entry.moodValue.label)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)

                // Energy badge
                HStack(spacing: 6) {
                    Image(systemName: entry.energyValue.icon)
                        .font(.system(size: 12, weight: .semibold))
                    Text("\(entry.energyValue.label) energy")
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

            // Note
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
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Brand.surfaceLight)
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Brand.divider, lineWidth: 1))
                )
            }

            // Reaction bar — always shown, so the partner can respond to any mood
            reactionBar(for: entry)

            // Suggestion button for low moods
            if entry.needsAttention {
                Button {
                    viewModel.openSuggestions()
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Get Suggestions")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
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
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Brand.surfaceLight)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(
                            moodColor(entry).opacity(entry.needsAttention ? 0.45 : 0.15),
                            lineWidth: entry.needsAttention ? 1.5 : 1
                        )
                )
                .shadow(color: .black.opacity(0.18), radius: 20, y: 6)
        )
    }

    // MARK: - Error State

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

    private var attentionBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: "heart.fill")
                .font(.system(size: 20))
                .foregroundStyle(Brand.accentStart)
                .symbolEffect(.pulse, isActive: true)

            VStack(alignment: .leading, spacing: 3) {
                Text("Your partner might need you")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                Text("They seem to be having a tough time")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
            }

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Brand.accentStart.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(Brand.accentStart.opacity(0.25), lineWidth: 1)
                )
        )
        .transition(.asymmetric(
            insertion: .scale(scale: 0.9).combined(with: .opacity),
            removal: .opacity
        ))
    }

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
                Text(viewModel.partnerIsOnline ? "Partner is online" : "Partner")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)

                Text(presenceSubtitle)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
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
                    Text(didSendPing ? "Sent" : "Thinking of you")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Capsule().fill(Brand.accentGradient))
                .shadow(color: Brand.accentStart.opacity(0.35), radius: 10, y: 3)
            }
            .buttonStyle(BouncyButtonStyle())
            .disabled(isSendingPing || didSendPing || !isRealSession)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Brand.surfaceLight)
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Brand.divider, lineWidth: 1))
        )
    }

    private var presenceSubtitle: String {
        if viewModel.partnerIsOnline {
            return "Active now"
        }
        guard let lastSeen = viewModel.partnerLastSeen else {
            return "No recent activity"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Last seen " + formatter.localizedString(for: lastSeen, relativeTo: Date())
    }

    private func sendThinkingOfYou() {
        guard let session = sessionStore.session, session.isPaired else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        isSendingPing = true
        Task {
            defer { isSendingPing = false }
            do {
                try await presenceService.sendPing(coupleId: session.coupleId, fromUserId: session.userId)
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
        HStack(spacing: 8) {
            ForEach(ReactionKind.allCases) { kind in
                Button {
                    sendReaction(kind, to: entry)
                } label: {
                    VStack(spacing: 4) {
                        Text(kind.emoji).font(.system(size: 22))
                        Text(kind.label)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(Brand.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Brand.surfaceLight)
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Brand.divider, lineWidth: 1))
                    )
                }
                .buttonStyle(BouncyButtonStyle())
            }
        }
    }

    private func sendReaction(_ kind: ReactionKind, to entry: SharedMoodEntry) {
        guard let session = sessionStore.session, session.isPaired else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            do {
                try await reactionService.sendReaction(
                    coupleId: session.coupleId,
                    moodId: entry.documentId,
                    userId: session.userId,
                    kind: kind
                )
            } catch {
                print("[Dashboard] Failed to send reaction: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Weekly History

    private var weeklyHistorySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Past 7 days")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Spacer()

                Text("\(viewModel.weeklyHistory.count) check-ins")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Brand.textTertiary)
            }

            HStack(spacing: 8) {
                ForEach(weekDays, id: \.self) { date in
                    historyCell(for: date)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Brand.surfaceLight)
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Brand.divider, lineWidth: 1))
        )
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
        let dayLabel: String = {
            let f = DateFormatter()
            f.dateFormat = "EEEEE" // one-letter weekday
            return f.string(from: date)
        }()

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
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func moodColor(_ entry: SharedMoodEntry) -> Color {
        switch entry.moodValue {
        case .happy:   return Color(red: 0.25, green: 0.85, blue: 0.55)
        case .neutral: return Color(red: 0.40, green: 0.70, blue: 1.0)
        case .sad:     return Color(red: 0.50, green: 0.40, blue: 1.0)
        case .stressed: return Color(red: 1.0, green: 0.55, blue: 0.25)
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Brand.bgGradient.ignoresSafeArea()
        CoupleDashboardView(
            viewModel: CoupleViewModel(),
            statsViewModel: CoupleStatsViewModel(),
            showPairingSheet: .constant(false)
        )
        .environmentObject(SessionStore())
    }
}
