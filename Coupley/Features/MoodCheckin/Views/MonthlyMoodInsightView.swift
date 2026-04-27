//
//  MonthlyMoodInsightView.swift
//  Coupley
//
//  Premium monthly mood journal. Renders a single month at a time:
//   • Hero: dominant mood + headline copy
//   • Calendar grid: each day's mood as a colored emoji dot
//   • Stats row: days logged, streak, average energy
//   • Mood distribution: stacked bar with per-mood counts
//   • Notes timeline: every note from the month, newest-first
//
//  Reads from `MoodLocalHistoryStore`. No network, no Firestore — works
//  fully offline. The header has prev/next month chevrons that walk
//  through the available history (months with at least one entry).
//

import SwiftUI

// MARK: - View

struct MonthlyMoodInsightView: View {

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store: MoodLocalHistoryStore

    /// First day of the currently-displayed month.
    @State private var monthAnchor: Date

    @MainActor
    init(store: MoodLocalHistoryStore = .shared) {
        self.store = store
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.dateInterval(of: .month, for: now)?.start ?? now
        _monthAnchor = State(initialValue: start)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    monthSwitcher
                    heroBlock
                    statsRow
                    calendarGrid
                    distributionCard
                    notesTimeline
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 36)
            }
            .background(Brand.bgGradient.ignoresSafeArea())
            .navigationTitle("Mood Journal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Brand.textSecondary)
                }
            }
        }
    }

    // MARK: - Month Switcher

    private var monthSwitcher: some View {
        HStack {
            Button(action: stepMonth(by: -1)) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(canStep(by: -1) ? Brand.textPrimary : Brand.textTertiary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Brand.surfaceLight))
                    .overlay(Circle().strokeBorder(Brand.divider, lineWidth: 1))
            }
            .disabled(!canStep(by: -1))

            Spacer()

            Text(monthFormatter.string(from: monthAnchor))
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Brand.textPrimary)

            Spacer()

            Button(action: stepMonth(by: 1)) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(canStep(by: 1) ? Brand.textPrimary : Brand.textTertiary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Brand.surfaceLight))
                    .overlay(Circle().strokeBorder(Brand.divider, lineWidth: 1))
            }
            .disabled(!canStep(by: 1))
        }
    }

    // MARK: - Hero

    private var heroBlock: some View {
        let dominant = store.dominantMood(in: monthAnchor)
        let entries = store.entries(in: monthAnchor)
        return ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: heroGradientColors(for: dominant),
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
            // Soft top blob for depth
            Circle()
                .fill(.white.opacity(0.18))
                .frame(width: 200, height: 200)
                .blur(radius: 60)
                .offset(x: -70, y: -80)

            VStack(alignment: .leading, spacing: 14) {
                Text("Your month")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .kerning(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.78))

                if entries.isEmpty {
                    Text("Nothing logged this month")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Mood entries you save will appear here automatically.")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineSpacing(2)
                } else if let dominant {
                    HStack(spacing: 12) {
                        Text(dominant.emoji)
                            .font(.system(size: 56))
                            .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(headline(for: dominant, count: entries.count))
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineSpacing(1)
                            Text("\(entries.count) check-in\(entries.count == 1 ? "" : "s") this month")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: (dominant?.color ?? Brand.accentStart).opacity(0.30), radius: 18, y: 8)
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        let avgEnergy = store.averageEnergyValue(in: monthAnchor)
        let isCurrentMonth = Calendar.current.isDate(monthAnchor, equalTo: Date(), toGranularity: .month)
        let streakValue: Int = isCurrentMonth ? store.currentStreak() : monthOnlyStreak()

        return HStack(spacing: 12) {
            statTile(
                icon: "calendar",
                title: "Days logged",
                value: "\(store.daysWithCheckin(in: monthAnchor))",
                accent: Color(red: 0.40, green: 0.76, blue: 0.95)
            )
            statTile(
                icon: "flame.fill",
                title: "Streak",
                value: "\(streakValue)d",
                accent: Color(red: 1.0, green: 0.55, blue: 0.30)
            )
            statTile(
                icon: "battery.50",
                title: "Avg energy",
                value: averageEnergyLabel(avgEnergy),
                accent: averageEnergyColor(avgEnergy)
            )
        }
    }

    private func statTile(icon: String, title: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accent)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Brand.textPrimary)
                .monospacedDigit()
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Brand.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Brand.surfaceLight)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Brand.divider, lineWidth: 1)
                )
        )
    }

    // MARK: - Calendar Grid

    private var calendarGrid: some View {
        let calendar = Calendar.current
        let monthInterval = calendar.dateInterval(of: .month, for: monthAnchor)
        let firstDay = monthInterval?.start ?? monthAnchor
        let daysInMonth = calendar.range(of: .day, in: .month, for: firstDay)?.count ?? 30
        // Day-of-week index of the 1st (Sunday=1...) → leading empty cells
        let firstWeekday = calendar.component(.weekday, from: firstDay)
        let leadingBlanks = (firstWeekday - calendar.firstWeekday + 7) % 7

        let dayEntries = store.latestPerDay(in: monthAnchor)
        let weekdaySymbols = calendar.veryShortWeekdaySymbols

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.grid.3x2.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Brand.textSecondary)
                Text("Calendar")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .kerning(0.4)
                    .textCase(.uppercase)
                    .foregroundStyle(Brand.textSecondary)
            }

            // Weekday header
            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { i in
                    let symbolIndex = (i + calendar.firstWeekday - 1) % 7
                    Text(weekdaySymbols[symbolIndex])
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(Brand.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }

            // 7-column grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(0..<leadingBlanks, id: \.self) { _ in
                    Color.clear.frame(height: 38)
                }
                ForEach(1...daysInMonth, id: \.self) { day in
                    let date = calendar.date(byAdding: .day, value: day - 1, to: firstDay) ?? firstDay
                    let key = calendar.startOfDay(for: date)
                    let entry = dayEntries[key]
                    calendarCell(day: day, entry: entry, isToday: calendar.isDateInToday(date))
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Brand.surfaceLight)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Brand.divider, lineWidth: 1)
                )
        )
    }

    private func calendarCell(day: Int, entry: LocalMoodEntry?, isToday: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(entry?.mood.color.opacity(0.18) ?? Brand.surfaceMid.opacity(0.45))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            isToday ? Brand.accentStart : (entry?.mood.color.opacity(0.40) ?? Color.clear),
                            lineWidth: isToday ? 1.5 : 1
                        )
                )

            VStack(spacing: 2) {
                Text(entry?.mood.emoji ?? "")
                    .font(.system(size: entry == nil ? 0 : 16))
                    .frame(height: entry == nil ? 0 : 18)
                Text("\(day)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(entry != nil ? entry!.mood.color : Brand.textTertiary)
                    .monospacedDigit()
            }
            .padding(.vertical, 4)
        }
        .frame(height: 38)
    }

    // MARK: - Distribution

    private var distributionCard: some View {
        let dist = store.distribution(in: monthAnchor)
        let total = max(1, dist.reduce(0) { $0 + $1.count })

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Brand.textSecondary)
                Text("Mood mix")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .kerning(0.4)
                    .textCase(.uppercase)
                    .foregroundStyle(Brand.textSecondary)
            }

            // Stacked horizontal bar
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(dist, id: \.mood) { item in
                        if item.count > 0 {
                            Rectangle()
                                .fill(item.mood.color)
                                .frame(width: max(4, geo.size.width * (Double(item.count) / Double(total))))
                        }
                    }
                    if total <= 1 && dist.allSatisfy({ $0.count == 0 }) {
                        Rectangle()
                            .fill(Brand.surfaceMid)
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 14)

            // Legend
            VStack(spacing: 8) {
                ForEach(dist, id: \.mood) { item in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(item.mood.color)
                            .frame(width: 10, height: 10)
                        Text(item.mood.label)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(Brand.textPrimary)
                        Spacer()
                        Text("\(item.count)")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Brand.textSecondary)
                            .monospacedDigit()
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Brand.surfaceLight)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Brand.divider, lineWidth: 1)
                )
        )
    }

    // MARK: - Notes Timeline

    private var notesTimeline: some View {
        let noted = store.notedEntries(in: monthAnchor)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "text.book.closed.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Brand.textSecondary)
                Text("Notes")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .kerning(0.4)
                    .textCase(.uppercase)
                    .foregroundStyle(Brand.textSecondary)
            }

            if noted.isEmpty {
                Text("No notes this month. Anything you jot down with a check-in lives here.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineSpacing(2)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(noted) { entry in
                        noteRow(entry)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Brand.surfaceLight)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Brand.divider, lineWidth: 1)
                )
        )
    }

    private func noteRow(_ entry: LocalMoodEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(entry.mood.color.opacity(0.16))
                    .frame(width: 36, height: 36)
                Text(entry.mood.emoji)
                    .font(.system(size: 18))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(entry.mood.label)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(entry.mood.color)
                    Text("·")
                        .foregroundStyle(Brand.textTertiary)
                    Text(noteDateFormatter.string(from: entry.timestamp))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Brand.textTertiary)
                }
                Text(entry.note ?? "")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Brand.surfaceMid.opacity(0.5))
        )
    }

    // MARK: - Helpers

    private func stepMonth(by delta: Int) -> () -> Void {
        return {
            guard canStep(by: delta) else { return }
            let calendar = Calendar.current
            if let next = calendar.date(byAdding: .month, value: delta, to: monthAnchor) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.easeInOut(duration: 0.22)) {
                    monthAnchor = calendar.dateInterval(of: .month, for: next)?.start ?? next
                }
            }
        }
    }

    private func canStep(by delta: Int) -> Bool {
        let calendar = Calendar.current
        guard let candidate = calendar.date(byAdding: .month, value: delta, to: monthAnchor) else {
            return false
        }
        // Don't allow stepping past the current month into the future.
        if delta > 0 {
            let now = Date()
            if calendar.compare(candidate, to: now, toGranularity: .month) == .orderedDescending {
                return false
            }
        }
        // Don't go further back than 24 months.
        if delta < 0 {
            let earliest = calendar.date(byAdding: .month, value: -24, to: Date()) ?? Date()
            if calendar.compare(candidate, to: earliest, toGranularity: .month) == .orderedAscending {
                return false
            }
        }
        return true
    }

    private func headline(for mood: Mood, count: Int) -> String {
        switch mood {
        case .happy:    return count > 14 ? "A bright month" : "Mostly bright days"
        case .neutral:  return "An even-keeled month"
        case .sad:      return "A heavier month"
        case .stressed: return "A heavy, busy month"
        }
    }

    private func averageEnergyLabel(_ value: Double?) -> String {
        guard let value else { return "—" }
        switch value {
        case ..<1.5:  return "Low"
        case ..<2.5:  return "Med"
        default:      return "High"
        }
    }

    private func averageEnergyColor(_ value: Double?) -> Color {
        guard let value else { return Brand.textTertiary }
        switch value {
        case ..<1.5:  return Color(red: 0.42, green: 0.56, blue: 1.00)
        case ..<2.5:  return Color(red: 0.40, green: 0.76, blue: 0.55)
        default:      return Color(red: 1.00, green: 0.60, blue: 0.20)
        }
    }

    private func heroGradientColors(for mood: Mood?) -> [Color] {
        guard let mood else {
            return [Brand.accentStart, Brand.accentEnd]
        }
        switch mood {
        case .happy:
            return [Color(red: 1.00, green: 0.78, blue: 0.30), Color(red: 0.95, green: 0.50, blue: 0.18)]
        case .neutral:
            return [Color(red: 0.55, green: 0.74, blue: 0.95), Color(red: 0.30, green: 0.40, blue: 0.78)]
        case .sad:
            return [Color(red: 0.42, green: 0.56, blue: 1.00), Color(red: 0.30, green: 0.40, blue: 0.78)]
        case .stressed:
            return [Color(red: 1.00, green: 0.55, blue: 0.42), Color(red: 0.78, green: 0.36, blue: 0.28)]
        }
    }

    /// Streak counted only within the displayed month. Used when the user is
    /// browsing a past month — the live "current streak" wouldn't make sense.
    private func monthOnlyStreak() -> Int {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: monthAnchor) else { return 0 }
        let logDays: Set<Date> = Set(
            store.entries(in: monthAnchor).map { calendar.startOfDay(for: $0.timestamp) }
        )

        // Walk from the last day of the month backward, counting the
        // longest run that ends within the month.
        var longest = 0
        var current = 0
        var cursor = calendar.startOfDay(for: interval.end.addingTimeInterval(-1))
        while cursor >= interval.start {
            if logDays.contains(cursor) {
                current += 1
                longest = max(longest, current)
            } else {
                current = 0
            }
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? interval.start
            if cursor < interval.start { break }
        }
        return longest
    }

    // MARK: - Formatters

    private let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "LLLL yyyy"
        return f
    }()

    private let noteDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d · h:mm a"
        return f
    }()
}
