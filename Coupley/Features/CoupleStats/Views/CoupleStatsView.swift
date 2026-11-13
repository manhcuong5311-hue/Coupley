//
//  CoupleStatsView.swift
//  Coupley
//
//  Created by Sam Manh Cuong on 1/4/26.
//

import SwiftUI

// MARK: - Couple Stats View

struct CoupleStatsView: View {

    @ObservedObject var viewModel: CoupleStatsViewModel

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.bgGradient.ignoresSafeArea()

                Group {
                    switch viewModel.loadState {
                    case .idle, .loading:
                        loadingView

                    case .loaded:
                        statsContent

                    case .error(let message):
                        errorView(message: message)
                    }
                }
            }
            .navigationTitle("Your Stats")
            .navigationBarTitleDisplayMode(.large)
        }
        .onAppear {
            viewModel.loadStats()
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .controlSize(.large)
                .tint(Brand.accentStart)
            Text("Loading your stats...")
                .font(.subheadline)
                .foregroundStyle(Brand.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Stats Content

    private var statsContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                streakSection
                syncScoreSection
                weeklyTrendSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .refreshable {
            viewModel.refresh()
        }
    }

    // MARK: - Error

    private func errorView(message: String) -> some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 48))
                .foregroundStyle(Brand.textSecondary)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(Brand.textSecondary)
                .multilineTextAlignment(.center)

            Button("Try Again") {
                viewModel.refresh()
            }
            .tint(Brand.accentStart)
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Streak Section

    private var streakSection: some View {
        VStack(spacing: 0) {
            StatsCard {
                VStack(spacing: 20) {
                    // Header
                    HStack {
                        Label("Check-in Streak", systemImage: "flame.fill")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.orange)
                        Spacer()
                    }

                    // Big number
                    streakDaysText(viewModel.streak.currentStreak)

                    // Encouragement
                    if viewModel.streak.currentStreak > 0 {
                        streakEncouragement
                    } else {
                        Text("Check in together today to start your streak!")
                            .font(.subheadline)
                            .foregroundStyle(Brand.textSecondary)
                            .multilineTextAlignment(.center)
                    }

                    // Progress to next milestone
                    if let next = viewModel.nextMilestone {
                        milestoneProgress(next: next)
                    }

                    // Longest streak
                    if viewModel.streak.longestStreak > 0 {
                        HStack {
                            Image(systemName: "trophy.fill")
                                .font(.caption)
                                .foregroundStyle(Brand.accentEnd)
                            Text("Longest: \(viewModel.streak.longestStreak) days")
                                .font(.caption)
                                .foregroundStyle(Brand.textSecondary)
                        }
                    }
                }
            }
        }
    }

    /// "12 days" as one plural-aware key, with the number drawn large.
    ///
    /// Was a 56pt number beside `count == 1 ? "day" : "days"`: two keys with
    /// no number in them, so a translator could not choose between the forms
    /// Polish or Russian use for 2 and for 5. Now the count is the key's own
    /// argument and the catalog can vary it by plural; the run that holds the
    /// number (replacement index 1, the first argument) gets the display font
    /// wherever the translation puts it. A translation that drops the number
    /// simply renders at the unit's size.
    private func streakDaysText(_ count: Int) -> Text {
        var text = count == 1
            ? AttributedString(localized: "\(count) day",
                               options: .applyReplacementIndexAttribute,
                               comment: "Stats: a check-in streak of exactly one day; the number is drawn large")
            : AttributedString(localized: "\(count) days",
                               options: .applyReplacementIndexAttribute,
                               comment: "Stats: current check-in streak length; the number is drawn large")
        text.font = .title3.weight(.medium)
        text.foregroundColor = Brand.textSecondary
        for (index, range) in text.runs[\.replacementIndex] where index == 1 {
            text[range].font = .system(size: 56, weight: .bold, design: .rounded)
            text[range].foregroundColor = Brand.textPrimary
        }
        return Text(text)
    }

    private var streakEncouragement: some View {
        Group {
            if let milestone = viewModel.streak.milestoneReached {
                HStack(spacing: 8) {
                    Image(systemName: milestone.icon)
                        .foregroundStyle(Brand.accentStart)
                    Text(milestone.label)
                        .fontWeight(.semibold)
                        .foregroundStyle(Brand.textPrimary)
                }
                .font(.subheadline)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Brand.accentStart.opacity(0.12))
                )
            } else {
                Text("Keep it going!")
                    .font(.subheadline)
                    .foregroundStyle(Brand.textSecondary)
            }
        }
    }

    private func milestoneProgress(next: StreakMilestone) -> some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Brand.surfaceMid)
                        .frame(height: 8)

                    Capsule()
                        .fill(Brand.accentGradient)
                        .frame(
                            width: max(
                                geo.size.width * viewModel.streakProgressToNextMilestone,
                                8
                            ),
                            height: 8
                        )
                        .animation(.spring(response: 0.6), value: viewModel.streakProgressToNextMilestone)
                }
            }
            .frame(height: 8)

            HStack {
                Text("\(viewModel.daysToNextMilestone) days to \(next.label)")
                    .font(.caption2)
                    .foregroundStyle(Brand.textTertiary)
                Spacer()
                Image(systemName: next.icon)
                    .font(.caption2)
                    .foregroundStyle(Brand.accentStart.opacity(0.6))
            }
        }
    }

    // MARK: - Sync Score Section

    private var syncScoreSection: some View {
        StatsCard {
            VStack(spacing: 20) {
                HStack {
                    Label("Sync Score", systemImage: "waveform.path.ecg")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Brand.accentStart)
                    Spacer()

                    if let score = viewModel.todaySyncScore {
                        Text("Today", comment: "Stats sync score header: the emoji beside it rates today's score")
                            .font(.caption2)
                            .foregroundStyle(Brand.textTertiary)
                            .padding(.trailing, 2)
                        Text(score.syncLevel.emoji)
                    }
                }

                if let score = viewModel.todaySyncScore {
                    syncScoreDisplay(score: score)
                } else {
                    noScoreYet
                }
            }
        }
    }

    private func syncScoreDisplay(score: SyncScore) -> some View {
        VStack(spacing: 16) {
            // Ring gauge
            ZStack {
                Circle()
                    .stroke(Brand.surfaceMid, lineWidth: 10)
                    .frame(width: 120, height: 120)

                Circle()
                    .trim(from: 0, to: Double(score.score) / 100.0)
                    .stroke(
                        syncGradient(for: score.syncLevel),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.8), value: score.score)

                VStack(spacing: 2) {
                    Text("\(score.score)")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                    Text("%", comment: "Percent sign on its own line under the sync score number")
                        .font(.caption)
                        .foregroundStyle(Brand.textSecondary)
                }
            }

            // Label
            Text(score.syncLevel.label)
                .font(.headline)
                .foregroundStyle(Brand.textPrimary)

            Text(score.syncLevel.encouragement)
                .font(.subheadline)
                .foregroundStyle(Brand.textSecondary)
                .multilineTextAlignment(.center)

            // Mood comparison
            HStack(spacing: 24) {
                VStack(spacing: 4) {
                    Text("You", comment: "Stats mood comparison: label above your own mood emoji")
                        .font(.caption2)
                        .foregroundStyle(Brand.textTertiary)
                    Text(Mood(rawValue: score.userAMood)?.emoji ?? "?")
                        .font(.title2)
                }

                Image(systemName: score.moodMatch ? "equal" : "not.equal")
                    .font(.caption)
                    .foregroundStyle(score.moodMatch ? .green : .orange)
                    .padding(8)
                    .background(
                        Circle()
                            .fill(score.moodMatch
                                  ? Color.green.opacity(0.1)
                                  : Color.orange.opacity(0.1))
                    )

                VStack(spacing: 4) {
                    Text("Partner", comment: "Stats mood comparison: label above your partner's mood emoji")
                        .font(.caption2)
                        .foregroundStyle(Brand.textTertiary)
                    Text(Mood(rawValue: score.userBMood)?.emoji ?? "?")
                        .font(.title2)
                }
            }
        }
    }

    private var noScoreYet: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 36))
                .foregroundStyle(Brand.textSecondary)

            // No hardcoded "\n": it would be welded into the catalog key.
            Text("Both partners need to check in to see today's sync score")
                .font(.subheadline)
                .foregroundStyle(Brand.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 16)
    }

    // MARK: - Weekly Trend Section

    private var weeklyTrendSection: some View {
        StatsCard {
            VStack(spacing: 20) {
                HStack {
                    Label("Weekly Trend", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Brand.accentStart)
                    Spacer()
                }

                if viewModel.weeklyScores.isEmpty {
                    Text("Keep checking in to see your weekly trend")
                        .font(.subheadline)
                        .foregroundStyle(Brand.textSecondary)
                        .padding(.vertical, 12)
                } else {
                    // Weekly average
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(viewModel.weeklyAverage)")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(Brand.textPrimary)

                        Text("% avg", comment: "After the weekly average number: percent, averaged over the week")
                            .font(.subheadline)
                            .foregroundStyle(Brand.textSecondary)

                        Spacer()

                        // Trend indicator
                        Label(viewModel.trend.label, systemImage: viewModel.trend.icon)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(viewModel.trend.isPositive ? .green : .orange)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(viewModel.trend.isPositive
                                          ? Color.green.opacity(0.1)
                                          : Color.orange.opacity(0.1))
                            )
                    }

                    // Bar chart
                    weeklyBarChart
                }
            }
        }
    }

    private var weeklyBarChart: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(viewModel.weeklyScores) { score in
                VStack(spacing: 6) {
                    // Bar
                    RoundedRectangle(cornerRadius: 4)
                        .fill(barGradient(for: score))
                        .frame(
                            height: max(CGFloat(score.score) / 100.0 * 80, 4)
                        )
                        .animation(.spring(response: 0.5), value: score.score)

                    // Day label
                    Text(dayLabel(for: score.date))
                        .font(.system(size: 10))
                        .foregroundStyle(Brand.textTertiary)
                        // One line under each bar: a second line would lift
                        // that bar off the shared baseline.
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 110)
    }

    // MARK: - Helpers

    private func syncGradient(for level: SyncLevel) -> LinearGradient {
        // In CoupleSync variant, collapse all tiers to the brand gradient so the
        // warm palette stays consistent. Classic keeps the vibrant semantic hues.
        if ThemeVariant.current == .coupleSync {
            return Brand.accentGradient
        }
        switch level {
        case .highlyInSync:
            return LinearGradient(colors: [.green, .mint], startPoint: .leading, endPoint: .trailing)
        case .inSync:
            return LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing)
        case .slightlyOff:
            return LinearGradient(colors: [.orange, .yellow], startPoint: .leading, endPoint: .trailing)
        case .outOfSync:
            return LinearGradient(colors: [.purple, .indigo], startPoint: .leading, endPoint: .trailing)
        }
    }

    private func barGradient(for score: SyncScore) -> LinearGradient {
        let level = SyncLevel.from(score: score.score)
        return syncGradient(for: level)
    }

    /// Stays a `String`: its usual result is a formatted weekday, already in
    /// the user's language, which must be drawn verbatim.
    private func dayLabel(for dateString: String) -> String {
        guard let date = DayKey.date(from: dateString) else { return "?" }

        if Calendar.current.isDateInToday(date) {
            return String(localized: "Today", comment: "Weekly sync chart: label under today's bar")
        }

        // The abbreviated weekday for the locale, as the "EEE" pattern gave,
        // without allocating a formatter per bar per render.
        return date.formatted(.dateTime.weekday(.abbreviated))
    }
}

// MARK: - Stats Card Container

struct StatsCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        let r = Brand.cardCornerRadius
        VStack {
            content()
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: r)
                .fill(Brand.surfaceLight)
                .overlay(
                    RoundedRectangle(cornerRadius: r)
                        .strokeBorder(Brand.divider, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.06), radius: 16, y: 6)
        )
    }
}

// MARK: - Previews

#Preview {
    CoupleStatsView(viewModel: CoupleStatsViewModel())
}
