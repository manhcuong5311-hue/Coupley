//
//  NotificationSettingsView.swift
//  Coupley
//

import SwiftUI

// MARK: - Notification Settings View

struct NotificationSettingsView: View {

    @ObservedObject var viewModel: NotificationViewModel

    private var isAuthorized: Bool {
        viewModel.permissionState == .authorized || viewModel.permissionState == .provisional
    }

    var body: some View {
        ZStack {
            Brand.bgGradient.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    permissionCard

                    if isAuthorized {
                        notificationTypesCard
                        reminderTimeCard
                    }

                    if !viewModel.recentNudges.isEmpty {
                        recentNudgesCard
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if !viewModel.recentNudges.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Mark All as Read") { viewModel.markAllAsRead() }
                        Button("Clear All", role: .destructive) { viewModel.clearAll() }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(Brand.accentStart)
                    }
                }
            }
        }
    }

    // MARK: - Permission Card

    private var permissionCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(permissionIconColor.opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: permissionIconName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(permissionIconColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Push Notifications")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                Text(permissionDescription)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if viewModel.permissionState == .denied {
                actionButton(label: "Open Settings", action: openAppSettings)
            } else if viewModel.permissionState == .unknown {
                actionButton(label: "Enable", action: viewModel.requestPermissionIfNeeded)
            }
        }
        .padding(16)
        .background(surfaceCard)
    }

    private func actionButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Brand.accentGradient)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Notification Types Card

    private var notificationTypesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader("Notify Me When")

            Group {
                toggleRow(
                    icon: "heart.fill",
                    iconColor: Color(red: 1.0, green: 0.32, blue: 0.56),
                    title: "Partner Mood Alert",
                    subtitle: "Your partner is having a tough day",
                    isOn: preferenceBinding(\.partnerMoodAlert)
                )
                rowDivider
                toggleRow(
                    icon: "arrow.triangle.2.circlepath",
                    iconColor: Brand.accentStart,
                    title: "Daily Sync Reminder",
                    subtitle: "Your partner checked in — your turn",
                    isOn: preferenceBinding(\.dailySyncReminder)
                )
                rowDivider
                toggleRow(
                    icon: "clock.fill",
                    iconColor: Color.orange,
                    title: "Inactivity Reminder",
                    subtitle: "You haven't checked in for 24+ hours",
                    isOn: preferenceBinding(\.inactivityReminder)
                )
                rowDivider
                toggleRow(
                    icon: "paperplane.fill",
                    iconColor: Color(red: 0.50, green: 0.32, blue: 1.0),
                    title: "Thinking of You Ping",
                    subtitle: "Your partner sends a loving ping",
                    isOn: preferenceBinding(\.partnerPing)
                )
                rowDivider
                toggleRow(
                    icon: "face.smiling.fill",
                    iconColor: Color(red: 1.0, green: 0.58, blue: 0.18),
                    title: "Mood Reactions",
                    subtitle: "Your partner reacts to your mood",
                    isOn: preferenceBinding(\.partnerReaction)
                )
            }
        }
        .background(surfaceCard)
    }

    private func toggleRow(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconColor.opacity(0.14))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
            }

            Spacer()

            Toggle("", isOn: isOn)
                .tint(Brand.accentStart)
                .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    // MARK: - Reminder Time Card

    private var reminderTimeCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader("Daily Reminder Time")

            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Brand.accentStart.opacity(0.14))
                        .frame(width: 32, height: 32)
                    Image(systemName: "alarm.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Brand.accentStart)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Reminder Hour")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                    Text("When to prompt your daily check-in")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)
                }

                Spacer()

                Picker("", selection: reminderHourBinding()) {
                    ForEach(0..<24, id: \.self) { hour in
                        Text(hourLabel(hour)).tag(hour)
                    }
                }
                .pickerStyle(.menu)
                .tint(Brand.accentStart)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
        }
        .background(surfaceCard)
    }

    // MARK: - Recent Nudges Card

    private var recentNudgesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                cardHeader("Recent")
                Spacer()
                if viewModel.unreadCount > 0 {
                    Text("\(viewModel.unreadCount) unread")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Brand.accentStart))
                }
            }
            .padding(.trailing, 16)

            ForEach(Array(viewModel.recentNudges.enumerated()), id: \.element.id) { index, nudge in
                if index > 0 {
                    rowDivider.padding(.leading, 62)
                }
                NudgeRow(nudge: nudge) { viewModel.handleNudgeTap(nudge) }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
        }
        .background(surfaceCard)
    }

    // MARK: - Shared Helpers

    private func cardHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(Brand.textSecondary)
            .textCase(.uppercase)
            .tracking(0.5)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)
    }

    private var rowDivider: some View {
        Divider()
            .background(Brand.divider)
            .padding(.leading, 62)
    }

    private var surfaceCard: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Brand.surfaceLight)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Brand.divider, lineWidth: 1)
            )
    }

    // Binding that immediately saves preferences to Firestore on change
    private func preferenceBinding(_ keyPath: WritableKeyPath<NotificationPreferences, Bool>) -> Binding<Bool> {
        Binding(
            get: { viewModel.preferences[keyPath: keyPath] },
            set: { newValue in
                viewModel.preferences[keyPath: keyPath] = newValue
                viewModel.savePreferences()
            }
        )
    }

    private func reminderHourBinding() -> Binding<Int> {
        Binding(
            get: { viewModel.preferences.reminderHour },
            set: { newValue in
                viewModel.preferences.reminderHour = newValue
                viewModel.savePreferences()
            }
        )
    }

    private func hourLabel(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        let date = Calendar.current.date(from: components) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "h:00 a"
        return formatter.string(from: date)
    }

    // MARK: - Permission Helpers

    private var permissionIconName: String {
        switch viewModel.permissionState {
        case .authorized, .provisional: return "bell.badge.fill"
        case .denied:                   return "bell.slash.fill"
        case .unknown:                  return "bell.fill"
        }
    }

    private var permissionIconColor: Color {
        switch viewModel.permissionState {
        case .authorized, .provisional: return Color(red: 0.25, green: 0.78, blue: 0.50)
        case .denied:                   return Color(red: 1.0, green: 0.38, blue: 0.38)
        case .unknown:                  return Brand.textSecondary
        }
    }

    private var permissionDescription: String {
        switch viewModel.permissionState {
        case .authorized:   return "Enabled — you'll receive smart nudges from your partner"
        case .provisional:  return "Delivered quietly — tap to grant full access"
        case .denied:       return "Disabled — open Settings to stay connected with your partner"
        case .unknown:      return "Tap Enable to get notified when it matters most"
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Nudge Row

private struct NudgeRow: View {

    let nudge: NudgeRecord
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(nudge.isRead
                              ? Color(.systemGray5)
                              : Brand.accentStart.opacity(0.14))
                        .frame(width: 34, height: 34)
                    Image(systemName: nudge.nudgeType?.icon ?? "bell.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(nudge.isRead ? Color(.systemGray3) : Brand.accentStart)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(nudge.title.isEmpty ? "Coupley" : nudge.title)
                            .font(.system(size: 14, weight: nudge.isRead ? .regular : .semibold, design: .rounded))
                            .foregroundStyle(Brand.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        Text(nudge.relativeTime)
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(Brand.textTertiary)
                    }

                    if !nudge.body.isEmpty {
                        Text(nudge.body)
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(Brand.textSecondary)
                            .lineLimit(2)
                    }

                    if let type = nudge.nudgeType {
                        Text(type.label)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(Brand.accentStart.opacity(0.8))
                    }
                }

                if !nudge.isRead {
                    Circle()
                        .fill(Brand.accentStart)
                        .frame(width: 7, height: 7)
                        .padding(.top, 4)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Notification Badge (Reusable)

struct NotificationBadge: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Text(count > 9 ? "9+" : "\(count)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(Brand.accentStart))
        }
    }
}

#Preview {
    NavigationStack {
        NotificationSettingsView(viewModel: NotificationViewModel())
    }
}
