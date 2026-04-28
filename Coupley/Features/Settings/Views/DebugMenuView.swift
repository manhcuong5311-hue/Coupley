//
//  DebugMenuView.swift
//  Coupley
//
//  Hidden developer / QA tools sheet. Surfaced by tapping the version row
//  in Settings 5× within ~2.5 seconds.
//
//  Production-safe:
//    – Every action is gated behind the gesture.
//    – No surface is reachable to a normal user.
//    – Nothing it does writes data the signed-in user can't already write.
//    – The "Replay Onboarding" action only flips a local @AppStorage flag —
//      premium, pairing, and Firestore data are never touched.
//

import SwiftUI
import UserNotifications
import FirebaseFirestore

struct DebugMenuView: View {

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sessionStore: SessionStore
    @ObservedObject private var logger = NotificationLogger.shared

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    @State private var permissionState: NotificationPermissionState = .unknown
    @State private var fcmToken: String? = NotificationService.shared.latestFCMToken
    @State private var apnsToken: String? = NotificationService.shared.latestAPNsToken
    @State private var partnerTokenStatus: String = "Checking…"
    @State private var actionToast: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.bgGradient.ignoresSafeArea()

                List {
                    actionsSection
                    statusSection
                    logsSection
                }
                .scrollContentBackground(.hidden)
                .listRowSpacing(8)

                if let toast = actionToast {
                    VStack {
                        Spacer()
                        Text(toast)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                Capsule().fill(Color.black.opacity(0.78))
                            )
                            .padding(.bottom, 30)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle("Developer Tools")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Brand.accentStart)
                }
            }
        }
        .task { await refreshAll() }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        Section {
            actionRow(
                icon: "arrow.counterclockwise.circle.fill",
                tint: Color(red: 1.0, green: 0.42, blue: 0.55),
                title: "Replay Onboarding",
                subtitle: "Restart the onboarding flow now"
            ) {
                hasCompletedOnboarding = false
                NotificationLogger.shared.info("Debug", "Replay onboarding triggered")
                // Dismiss the debug sheet so RootView can route to onboarding.
                // The Settings sheet (which presented this) is dismissed by
                // its own onChange(of: hasCompletedOnboarding).
                dismiss()
            }

            actionRow(
                icon: "bell.badge.fill",
                tint: Color.orange,
                title: "Send Test Notification",
                subtitle: "Local push fires in 5 seconds"
            ) {
                Task {
                    await NotificationService.shared.scheduleLocalTest(after: 5)
                    flashToast("Test notification scheduled")
                }
            }

            actionRow(
                icon: "arrow.triangle.2.circlepath.circle.fill",
                tint: Color.blue,
                title: "Force FCM Token Refresh",
                subtitle: "Re-fetches and re-saves the push token"
            ) {
                Task {
                    if let t = await NotificationService.shared.refreshFCMToken() {
                        fcmToken = t
                        flashToast("Token refreshed")
                        await refreshPartnerToken()
                    } else {
                        flashToast("Refresh failed — see logs")
                    }
                }
            }

            actionRow(
                icon: "bell.circle.fill",
                tint: Color.purple,
                title: "Re-request Permission",
                subtitle: permissionState == .denied
                    ? "Will deep-link to Settings"
                    : "Forces the system prompt if undecided"
            ) {
                if permissionState == .denied {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } else {
                    Task {
                        let s = await NotificationService.shared.requestPermission()
                        permissionState = s
                        flashToast("Permission: \(label(for: s))")
                    }
                }
            }
        } header: {
            Text("Actions")
        }
        .listRowBackground(rowBackground)
    }

    // MARK: - Status

    private var statusSection: some View {
        Section {
            statusRow(label: "Permission", value: label(for: permissionState))
            statusRow(label: "APNs Token", value: shortened(apnsToken),
                      copyValue: apnsToken)
            statusRow(label: "FCM Token", value: shortened(fcmToken),
                      copyValue: fcmToken)
            statusRow(label: "Last received",
                      value: logger.lastReceivedAt.map { Self.dateFmt.string(from: $0) } ?? "Never")
            statusRow(label: "Partner token", value: partnerTokenStatus)
            statusRow(label: "Bound user",
                      value: shortened(NotificationService.shared.currentlyBoundUserId))
            statusRow(label: "Bundle ID",
                      value: Bundle.main.bundleIdentifier ?? "—")
            statusRow(label: "Build", value: buildLabel)
            statusRow(label: "Mode", value: buildMode)
        } header: {
            HStack {
                Text("Status")
                Spacer()
                Button {
                    Task { await refreshAll() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Brand.accentStart)
                }
            }
        }
        .listRowBackground(rowBackground)
    }

    // MARK: - Logs

    private var logsSection: some View {
        Section {
            if logger.entries.isEmpty {
                HStack {
                    Image(systemName: "tray")
                        .foregroundStyle(Brand.textTertiary)
                    Text("No log entries yet")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Brand.textTertiary)
                    Spacer()
                }
                .listRowBackground(rowBackground)
            } else {
                ForEach(logger.entries.prefix(80)) { entry in
                    logRow(entry)
                        .listRowBackground(rowBackground)
                }
            }
        } header: {
            HStack {
                Text("Logs (\(logger.entries.count))")
                Spacer()
                if !logger.entries.isEmpty {
                    Button {
                        UIPasteboard.general.string = exportedLogs()
                        flashToast("Logs copied")
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    Button("Clear") {
                        logger.clear()
                    }
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Color.red.opacity(0.85))
                }
            }
        }
    }

    private func logRow(_ entry: NotificationLogger.Entry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(entry.level.glyph)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(color(for: entry.level))
                .frame(width: 14, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(entry.category)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Brand.accentStart)
                    Spacer()
                    Text(Self.timeFmt.string(from: entry.timestamp))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Brand.textTertiary)
                }
                Text(entry.message)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Row Helpers

    private func actionRow(icon: String, tint: Color, title: String, subtitle: String,
                           action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Brand.textTertiary)
            }
        }
        .buttonStyle(.plain)
    }

    private func statusRow(label: String, value: String, copyValue: String? = nil) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Brand.textSecondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Brand.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            if let copy = copyValue, !copy.isEmpty, copy != "—" {
                Button {
                    UIPasteboard.general.string = copy
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    flashToast("Copied")
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                        .foregroundStyle(Brand.accentStart)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Helpers

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .medium
        return f
    }()

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 12).fill(Brand.surfaceLight)
    }

    private func label(for state: NotificationPermissionState) -> String {
        switch state {
        case .authorized:  return "Authorized"
        case .denied:      return "Denied"
        case .provisional: return "Provisional"
        case .unknown:     return "Not determined"
        }
    }

    private func shortened(_ token: String?) -> String {
        guard let token, !token.isEmpty else { return "—" }
        if token.count <= 18 { return token }
        let head = token.prefix(8), tail = token.suffix(6)
        return "\(head)…\(tail)"
    }

    private func color(for level: NotificationLogger.Level) -> Color {
        switch level {
        case .success: return Color(red: 0.20, green: 0.75, blue: 0.45)
        case .warn:    return Color.orange
        case .error:   return Color.red
        case .info:    return Brand.textSecondary
        }
    }

    private var buildLabel: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    private var buildMode: String {
        #if DEBUG
        return "DEBUG"
        #else
        return "RELEASE"
        #endif
    }

    private func exportedLogs() -> String {
        logger.entries.reversed().map {
            let ts = Self.timeFmt.string(from: $0.timestamp)
            return "\(ts) [\($0.level.rawValue)] \($0.category): \($0.message)"
        }.joined(separator: "\n")
    }

    @MainActor
    private func flashToast(_ text: String) {
        withAnimation(.easeOut(duration: 0.2)) { actionToast = text }
        Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            withAnimation(.easeIn(duration: 0.2)) { actionToast = nil }
        }
    }

    // MARK: - Refresh

    private func refreshAll() async {
        permissionState = await NotificationService.shared.checkCurrentPermission()
        fcmToken  = NotificationService.shared.latestFCMToken
        apnsToken = NotificationService.shared.latestAPNsToken
        await refreshPartnerToken()
    }

    private func refreshPartnerToken() async {
        guard let session = sessionStore.session, session.isPaired else {
            partnerTokenStatus = "Not paired"
            return
        }
        do {
            let snap = try await Firestore.firestore()
                .collection(FirestorePath.users)
                .document(session.partnerId)
                .getDocument()
            if let token = snap.data()?["fcmToken"] as? String, !token.isEmpty {
                partnerTokenStatus = "Present (\(token.prefix(8))…)"
            } else {
                partnerTokenStatus = "Missing — partner has no token"
            }
        } catch {
            partnerTokenStatus = "Lookup failed"
        }
    }
}

#Preview {
    DebugMenuView()
        .environmentObject(SessionStore())
}
