//
//  ChallengeDetailSheet.swift
//  Coupley
//
//  Detail view for a couple challenge. Hero progress, streak block, and a
//  calendar-style heat map of the last few weeks of check-ins. Heat map is
//  the "wow" element here — a vivid premium-feeling visualization that
//  doesn't show up anywhere else in the app.
//

import SwiftUI

struct ChallengeDetailSheet: View {

    let challenge: CoupleChallenge
    @ObservedObject var viewModel: TogetherViewModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // Live read so check-ins reflect immediately without waiting for sheet
        // re-presentation.
        let live = viewModel.challenges.first { $0.id == challenge.id } ?? challenge

        return NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    heroBlock(live)
                    streakStatsCard(live)
                    checkInBlock(live)
                    heatmap(live)
                    historyPanel(live)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .background(Brand.bgGradient.ignoresSafeArea())
            .navigationTitle(live.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Brand.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            Task {
                                await viewModel.deleteChallenge(live)
                                dismiss()
                            }
                        } label: {
                            Label("Delete challenge", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(Brand.textSecondary)
                    }
                }
            }
        }
    }

    // MARK: - Hero Block

    private func heroBlock(_ live: CoupleChallenge) -> some View {
        ZStack {
            TogetherHeroBackground(colorway: live.colorway)

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: live.category.icon)
                        .font(.system(size: 12, weight: .semibold))
                    Text(live.category.label)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .kerning(0.4)
                        .textCase(.uppercase)
                }
                .foregroundStyle(.white.opacity(0.85))

                Text(live.statusLine)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                TogetherProgressBar(progress: live.progress, colorway: live.colorway, height: 12, showsHighlight: false)
                    .padding(.top, 4)

                HStack(spacing: 16) {
                    Label("\(live.totalCheckIns) check-ins", systemImage: "checkmark")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Label("Ends \(live.endDate.formatted(.dateTime.month(.abbreviated).day()))", systemImage: "flag.checkered")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white.opacity(0.78))
                .padding(.top, 2)
            }
            .padding(22)
        }
    }

    // MARK: - Streak Stats

    private func streakStatsCard(_ live: CoupleChallenge) -> some View {
        TogetherCard(tint: live.colorway) {
            HStack(alignment: .center, spacing: 16) {
                streakStat(value: "\(live.streak.current)", label: "Current")
                Divider().frame(height: 36).opacity(0.5)
                streakStat(value: "\(live.streak.longest)", label: "Longest")
                Divider().frame(height: 36).opacity(0.5)
                streakStat(
                    value: "\(live.targetCount - live.totalCheckIns)",
                    label: "To go"
                )
            }
        }
    }

    private func streakStat(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Brand.textPrimary)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .kerning(0.4)
                .textCase(.uppercase)
                .foregroundStyle(Brand.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Check-in Block

    private func checkInBlock(_ live: CoupleChallenge) -> some View {
        let alreadyChecked = live.hasCheckedIn(for: viewModel.sessionUserId)
        return TogetherCard(tint: live.colorway) {
            VStack(spacing: 12) {
                Text(alreadyChecked ? "You've checked in today" :
                        (live.hasStarted ? "Ready to check in?" : "Starts \(live.startDate.formatted(.dateTime.month(.abbreviated).day()))"))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                    .multilineTextAlignment(.center)

                if alreadyChecked {
                    Text("Come back tomorrow to extend the streak.")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)
                        .multilineTextAlignment(.center)
                } else if !live.hasStarted {
                    Text("This challenge isn't live yet. The first check-in starts your streak.")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)
                        .multilineTextAlignment(.center)
                } else {
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        Task { await viewModel.checkInToChallenge(live) }
                    }) {
                        Label("Check in for today", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(live.colorway.gradient)
                                    .shadow(color: live.colorway.primary.opacity(0.45), radius: 14, y: 5)
                            )
                    }
                    .buttonStyle(BouncyButtonStyle())
                }
            }
        }
    }

    // MARK: - Heat Map

    private func heatmap(_ live: CoupleChallenge) -> some View {
        // 5 weeks × 7 days
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weeksToShow = 5
        let totalDays = weeksToShow * 7

        // Day labels for the leading column
        let weekdaySymbols = calendar.veryShortWeekdaySymbols

        // Build a set of "checked-in days" rounded to startOfDay for fast lookup.
        let checkedDays: Set<Date> = Set(live.checkInLog.map { calendar.startOfDay(for: $0) })

        // The grid runs left→right, oldest→newest. Compute the leftmost date.
        guard let startOfRange = calendar.date(byAdding: .day, value: -(totalDays - 1), to: today) else {
            return AnyView(EmptyView())
        }

        return AnyView(
            TogetherCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Last 5 weeks")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)

                    GeometryReader { geo in
                        let cellSpacing: CGFloat = 4
                        let labelWidth: CGFloat = 18
                        let usableWidth = geo.size.width - labelWidth - 4
                        let cellW = (usableWidth - cellSpacing * CGFloat(weeksToShow - 1)) / CGFloat(weeksToShow)

                        HStack(alignment: .top, spacing: 4) {
                            // Weekday labels
                            VStack(spacing: cellSpacing) {
                                ForEach(0..<7, id: \.self) { row in
                                    Text(weekdaySymbols[row])
                                        .font(.system(size: 9, weight: .medium, design: .rounded))
                                        .foregroundStyle(Brand.textTertiary)
                                        .frame(width: labelWidth, height: cellW)
                                }
                            }

                            // Grid: weeks across, days down
                            HStack(spacing: cellSpacing) {
                                ForEach(0..<weeksToShow, id: \.self) { col in
                                    VStack(spacing: cellSpacing) {
                                        ForEach(0..<7, id: \.self) { row in
                                            let dayIndex = col * 7 + row
                                            if let date = calendar.date(byAdding: .day, value: dayIndex, to: startOfRange) {
                                                heatCell(
                                                    date: date,
                                                    checked: checkedDays.contains(calendar.startOfDay(for: date)),
                                                    isToday: calendar.isDate(date, inSameDayAs: today),
                                                    colorway: live.colorway,
                                                    size: cellW
                                                )
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .frame(height: 7 * 32)

                    HStack(spacing: 10) {
                        Circle().fill(live.colorway.primary).frame(width: 8, height: 8)
                        Text("Checked-in day")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Brand.textSecondary)
                        Spacer()
                    }
                    .padding(.top, 4)
                }
            }
        )
    }

    private func heatCell(date: Date, checked: Bool, isToday: Bool,
                          colorway: TogetherColorway, size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(checked
                  ? AnyShapeStyle(colorway.gradient)
                  : AnyShapeStyle(Brand.surfaceMid.opacity(0.65)))
            .frame(width: size, height: size)
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(isToday ? colorway.deep : Brand.divider.opacity(0.3),
                                  lineWidth: isToday ? 1.5 : 0.5)
            )
            .shadow(color: checked ? colorway.primary.opacity(0.35) : .clear,
                    radius: 3, y: 1)
    }

    // MARK: - History Panel

    private func historyPanel(_ live: CoupleChallenge) -> some View {
        TogetherCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Story so far")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)

                historyRow(
                    icon: "leaf.fill",
                    title: "Started",
                    detail: live.startDate.formatted(date: .abbreviated, time: .omitted),
                    accent: live.colorway.primary
                )
                Divider().opacity(0.4)
                historyRow(
                    icon: "flame.fill",
                    title: "Best streak",
                    detail: "\(live.streak.longest) \(live.cadence == .daily ? "days" : "weeks")",
                    accent: Color(red: 1.0, green: 0.55, blue: 0.30)
                )
                Divider().opacity(0.4)
                historyRow(
                    icon: "person.2.fill",
                    title: "Together",
                    detail: "\(Int(live.contribution.amount(for: viewModel.sessionUserId))) by you · \(Int(live.contribution.total - live.contribution.amount(for: viewModel.sessionUserId))) by partner",
                    accent: Brand.accentStart
                )
                if let completed = live.completedAt {
                    Divider().opacity(0.4)
                    historyRow(
                        icon: "checkmark.seal.fill",
                        title: "Completed",
                        detail: completed.formatted(date: .long, time: .omitted),
                        accent: Color(red: 0.30, green: 0.78, blue: 0.50)
                    )
                }
            }
        }
    }

    private func historyRow(icon: String, title: String, detail: String, accent: Color) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.18))
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                Text(detail)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
            }
            Spacer()
        }
    }
}
