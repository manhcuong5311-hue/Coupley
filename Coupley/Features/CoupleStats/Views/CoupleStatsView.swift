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
            Text("Loading your stats...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Try Again") {
                viewModel.refresh()
            }
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
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(viewModel.streak.currentStreak)")
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text(viewModel.streak.currentStreak == 1 ? "day" : "days")
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }

                    // Encouragement
                    if viewModel.streak.currentStreak > 0 {
                        streakEncouragement
                    } else {
                        Text("Check in together today to start your streak!")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
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
                                .foregroundStyle(.yellow)
                            Text("Longest: \(viewModel.streak.longestStreak) days")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var streakEncouragement: some View {
        Group {
            if let milestone = viewModel.streak.milestoneReached {
                HStack(spacing: 8) {
                    Image(systemName: milestone.icon)
                        .foregroundStyle(.orange)
                    Text(milestone.label)
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.orange.opacity(0.12))
                )
            } else {
                Text("Keep it going!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func milestoneProgress(next: StreakMilestone) -> some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.systemGray5))
                        .frame(height: 8)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.orange, .red],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
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
                    .foregroundStyle(.tertiary)
                Spacer()
                Image(systemName: next.icon)
                    .font(.caption2)
                    .foregroundStyle(.orange.opacity(0.5))
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
                        .foregroundStyle(.purple)
                    Spacer()

                    if let score = viewModel.todaySyncScore {
                        Text("Today")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
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
                    .stroke(Color(.systemGray5), lineWidth: 10)
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
                    Text("%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Label
            Text(score.syncLevel.label)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(score.syncLevel.encouragement)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Mood comparison
            HStack(spacing: 24) {
                VStack(spacing: 4) {
                    Text("You")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
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
                    Text("Partner")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
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
                .foregroundStyle(.secondary)

            Text("Both partners need to check in\nto see today's sync score")
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
                        .foregroundStyle(.green)
                    Spacer()
                }

                if viewModel.weeklyScores.isEmpty {
                    Text("Keep checking in to see your weekly trend")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 12)
                } else {
                    // Weekly average
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(viewModel.weeklyAverage)")
                            .font(.system(size: 36, weight: .bold, design: .rounded))

                        Text("% avg")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

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
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 110)
    }

    // MARK: - Helpers

    private func syncGradient(for level: SyncLevel) -> LinearGradient {
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

    private func dayLabel(for dateString: String) -> String {
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "yyyy-MM-dd"

        guard let date = inputFormatter.date(from: dateString) else { return "?" }

        if Calendar.current.isDateInToday(date) { return "Today" }

        let outputFormatter = DateFormatter()
        outputFormatter.dateFormat = "EEE"
        return outputFormatter.string(from: date)
    }
}

// MARK: - Stats Card Container

struct StatsCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack {
            content()
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.06), radius: 16, y: 6)
        )
    }
}

// MARK: - Previews

#Preview {
    CoupleStatsView(viewModel: CoupleStatsViewModel())
}
