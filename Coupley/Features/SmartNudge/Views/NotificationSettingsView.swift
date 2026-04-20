//
//  NotificationSettingsView.swift
//  Coupley
//
//  Created by Sam Manh Cuong on 1/4/26.
//

import SwiftUI

// MARK: - Notification Settings View

struct NotificationSettingsView: View {

    @ObservedObject var viewModel: NotificationViewModel

    var body: some View {
        List {
            // Permission status
            permissionSection

            // Recent nudges
            if !viewModel.recentNudges.isEmpty {
                recentNudgesSection
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if !viewModel.recentNudges.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Mark All as Read") {
                            viewModel.markAllAsRead()
                        }
                        Button("Clear All", role: .destructive) {
                            viewModel.clearAll()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }

    // MARK: - Permission Section

    private var permissionSection: some View {
        Section {
            HStack(spacing: 14) {
                Image(systemName: permissionIcon)
                    .font(.title2)
                    .foregroundStyle(permissionColor)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Push Notifications")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text(permissionDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if viewModel.permissionState == .denied {
                    Button("Settings") {
                        openAppSettings()
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else if viewModel.permissionState == .unknown {
                    Button("Enable") {
                        viewModel.requestPermissionIfNeeded()
                    }
                    .font(.caption)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Status")
        } footer: {
            Text("Notifications help you stay connected with your partner.")
        }
    }

    // MARK: - Recent Nudges Section

    private var recentNudgesSection: some View {
        Section {
            ForEach(viewModel.recentNudges) { nudge in
                NudgeRow(nudge: nudge) {
                    viewModel.handleNudgeTap(nudge)
                }
            }
        } header: {
            HStack {
                Text("Recent")
                Spacer()
                if viewModel.unreadCount > 0 {
                    Text("\(viewModel.unreadCount) unread")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    // MARK: - Helpers

    private var permissionIcon: String {
        switch viewModel.permissionState {
        case .authorized, .provisional: return "bell.badge.fill"
        case .denied: return "bell.slash.fill"
        case .unknown: return "bell.fill"
        }
    }

    private var permissionColor: Color {
        switch viewModel.permissionState {
        case .authorized, .provisional: return .green
        case .denied: return .red
        case .unknown: return .secondary
        }
    }

    private var permissionDescription: String {
        switch viewModel.permissionState {
        case .authorized: return "Enabled — you'll receive smart nudges"
        case .provisional: return "Provisional — delivered quietly"
        case .denied: return "Disabled — enable in Settings to stay connected"
        case .unknown: return "Not yet configured"
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
                // Type icon
                Image(systemName: nudge.nudgeType?.icon ?? "bell.fill")
                    .font(.subheadline)
                    .foregroundStyle(nudge.isRead ? Color.secondary : Color.accentColor)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(nudge.isRead
                                  ? Color(.systemGray5)
                                  : Color.accentColor.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(nudge.title)
                            .font(.subheadline)
                            .fontWeight(nudge.isRead ? .regular : .semibold)
                            .foregroundStyle(.primary)

                        Spacer()

                        Text(nudge.relativeTime)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    if !nudge.body.isEmpty {
                        Text(nudge.body)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    if let type = nudge.nudgeType {
                        Text(type.label)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Notification Badge View (Reusable)

struct NotificationBadge: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Text(count > 9 ? "9+" : "\(count)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(.red))
        }
    }
}

#Preview {
    NavigationStack {
        NotificationSettingsView(viewModel: NotificationViewModel())
    }
}
