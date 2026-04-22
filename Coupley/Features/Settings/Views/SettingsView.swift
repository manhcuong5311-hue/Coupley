//
//  SettingsView.swift
//  Coupley
//
//  Central settings hub — Account, Appearance, Notifications, Premium, About.
//  Opened from the top-right gear button in CoupleDashboardView.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct SettingsView: View {

    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var premiumStore: PremiumStore
    @EnvironmentObject var notificationViewModel: NotificationViewModel

    @Environment(\.dismiss) private var dismiss

    @State private var showSignOutConfirm = false
    @State private var showEditName = false
    @State private var currentDisplayName: String = Auth.auth().currentUser?.displayName ?? "—"
    @State private var showThemePaywall = false

    let session: UserSession?

    var body: some View {
        ZStack {
            Brand.bgGradient.ignoresSafeArea(.all)

            List {
                premiumSection
                accountSection
                partnerSection
                themeStyleSection
                appearanceSection
                notificationsSection
                faqSection
                aboutSection
                signOutSection
            }
            .scrollContentBackground(.hidden)
            .listRowSpacing(8)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
                    .foregroundStyle(Brand.accentStart)
            }
        }
        .confirmationDialog("Sign out of Coupley?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) {
                sessionStore.signOut()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Premium

    @ViewBuilder
    private var premiumSection: some View {
        Section {
            NavigationLink {
                PremiumPaywallView()
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Brand.accentGradient)
                            .frame(width: 34, height: 34)
                        Image(systemName: "sparkles")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(premiumStore.isActive ? "Coupley Premium" : "Upgrade to Premium")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(Brand.textPrimary)
                        Text(premiumSubtitle)
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(Brand.textSecondary)
                    }
                }
            }
            .listRowBackground(premiumRowBackground)
        }
    }

    private var premiumSubtitle: String {
        if !premiumStore.isActive { return "Unlock all features for both of you" }
        switch premiumStore.source {
        case .partner: return "Shared from your partner"
        case .self_:   return "Active — thanks for supporting Coupley"
        case .none:    return "Active"
        }
    }

    private var premiumRowBackground: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Brand.accentStart.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Brand.accentStart.opacity(0.25), lineWidth: 1)
            )
    }

    // MARK: - Account

    @ViewBuilder
    private var accountSection: some View {
        Section("Account") {
            Button {
                showEditName = true
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Brand.accentStart.opacity(0.15))
                            .frame(width: 30, height: 30)
                        Image(systemName: "person.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Brand.accentStart)
                    }
                    Text("Name")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                    Spacer()
                    Text(currentDisplayName)
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Brand.textTertiary)
                }
            }
            .sheet(isPresented: $showEditName, onDismiss: {
                currentDisplayName = Auth.auth().currentUser?.displayName ?? "—"
            }) {
                EditNameSheet()
            }
            SettingsRow(
                icon: "envelope.fill",
                iconTint: Brand.accentStart,
                title: "Email",
                value: Auth.auth().currentUser?.email ?? "—"
            )
        }
        .listRowBackground(surfaceRowBackground)
    }

    // MARK: - Partner

    @ViewBuilder
    private var partnerSection: some View {
        Section("Partner") {
            if let session, session.isPaired {
                NavigationLink {
                    ManagePartnerView(
                        session: session,
                        partnerDisplayName: nil
                    )
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8).fill(Brand.accentStart.opacity(0.15))
                                .frame(width: 30, height: 30)
                            Image(systemName: "heart.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Brand.accentStart)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Connected")
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundStyle(Brand.textPrimary)
                            Text("Tap to manage or disconnect")
                                .font(.system(size: 12, design: .rounded))
                                .foregroundStyle(Brand.textSecondary)
                        }
                        Spacer()
                    }
                }
            } else {
                NavigationLink {
                    SettingsPairingContainer(session: session)
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8).fill(Brand.accentStart.opacity(0.15))
                                .frame(width: 30, height: 30)
                            Image(systemName: "link.badge.plus")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Brand.accentStart)
                        }
                        Text("Connect a partner")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(Brand.textPrimary)
                    }
                }
            }

            // Surfaces after a disconnect — archived data is kept until
            // the user chooses to remove it.
            if let lastCoupleId = sessionStore.lastCoupleId, !lastCoupleId.isEmpty {
                NavigationLink {
                    ManageSharedDataView(
                        connectionId: lastCoupleId,
                        partnerDisplayName: sessionStore.lastPartnerName
                    )
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Brand.textSecondary.opacity(0.15))
                                .frame(width: 30, height: 30)
                            Image(systemName: "tray.full.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Brand.textSecondary)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Manage shared data")
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundStyle(Brand.textPrimary)
                            Text("Review or delete data from a past partner")
                                .font(.system(size: 12, design: .rounded))
                                .foregroundStyle(Brand.textSecondary)
                        }
                        Spacer()
                    }
                }
            }
        }
        .listRowBackground(surfaceRowBackground)
    }

    // MARK: - Theme Style (variant picker)

    @ViewBuilder
    private var themeStyleSection: some View {
        Section {
            ForEach(ThemeVariant.allCases) { variant in
                let isDefault = variant == ThemeVariant.allCases.first
                let isLocked = !isDefault && !premiumStore.hasAccess(to: .allThemes)

                Button {
                    if isLocked {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        showThemePaywall = true
                    } else {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        themeManager.variant = variant
                    }
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isLocked
                                      ? Brand.textTertiary.opacity(0.12)
                                      : Brand.accentStart.opacity(0.15))
                                .frame(width: 30, height: 30)
                            Image(systemName: isLocked ? "lock.fill" : variant.icon)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(isLocked ? Brand.textTertiary : Brand.accentStart)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(variant.label)
                                    .font(.system(size: 15, weight: .medium, design: .rounded))
                                    .foregroundStyle(isLocked ? Brand.textSecondary : Brand.textPrimary)
                                if isLocked {
                                    Text("Premium")
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .foregroundStyle(Color(red: 0.95, green: 0.65, blue: 0.15))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            Capsule().fill(Color(red: 0.95, green: 0.65, blue: 0.15).opacity(0.15))
                                        )
                                }
                            }
                            Text(variant.tagline)
                                .font(.system(size: 12, design: .rounded))
                                .foregroundStyle(Brand.textTertiary)
                        }
                        Spacer()
                        if !isLocked && themeManager.variant == variant {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Brand.accentStart)
                        }
                    }
                }
            }
        } header: {
            Text("Theme Style")
        } footer: {
            if !premiumStore.isActive {
                Text("Additional themes require Premium. Free tier includes the default style.")
                    .font(.system(size: 12, design: .rounded))
            } else {
                Text("Pick between the new CoupleSync look or the classic gradient.")
                    .font(.system(size: 12, design: .rounded))
            }
        }
        .listRowBackground(surfaceRowBackground)
        .sheet(isPresented: $showThemePaywall) {
            NavigationStack { PremiumPaywallView() }
                .environmentObject(premiumStore)
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Appearance

    @ViewBuilder
    private var appearanceSection: some View {
        Section("Appearance") {
            ForEach(AppTheme.allCases) { theme in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    themeManager.theme = theme
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Brand.accentStart.opacity(0.15))
                                .frame(width: 30, height: 30)
                            Image(systemName: theme.icon)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Brand.accentStart)
                        }
                        Text(theme.label)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(Brand.textPrimary)
                        Spacer()
                        if themeManager.theme == theme {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Brand.accentStart)
                        }
                    }
                }
            }
        }
        .listRowBackground(surfaceRowBackground)
    }

    // MARK: - Notifications

    @ViewBuilder
    private var notificationsSection: some View {
        Section("Notifications") {
            NavigationLink {
                NotificationSettingsView(viewModel: notificationViewModel)
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8).fill(Brand.accentStart.opacity(0.15))
                            .frame(width: 30, height: 30)
                        Image(systemName: "bell.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Brand.accentStart)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notifications & alerts")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(Brand.textPrimary)
                        if notificationViewModel.unreadCount > 0 {
                            Text("\(notificationViewModel.unreadCount) unread")
                                .font(.system(size: 12, design: .rounded))
                                .foregroundStyle(Brand.accentStart)
                        }
                    }
                    Spacer()
                    if notificationViewModel.unreadCount > 0 {
                        Text("\(notificationViewModel.unreadCount)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Brand.accentStart))
                    }
                }
            }
        }
        .listRowBackground(surfaceRowBackground)
    }

    // MARK: - FAQ

    @ViewBuilder
    private var faqSection: some View {
        Section("FAQ") {
            NavigationLink {
                FAQView()
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Brand.accentStart.opacity(0.15))
                            .frame(width: 30, height: 30)
                        Image(systemName: "questionmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Brand.accentStart)
                    }
                    Text("Frequently Asked Questions")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                }
            }
        }
        .listRowBackground(surfaceRowBackground)
    }

    // MARK: - About

    @ViewBuilder
    private var aboutSection: some View {
        Section("About") {
            SettingsRow(icon: "info.circle.fill", iconTint: Brand.textSecondary,
                        title: "Version", value: appVersion)
            if let url = URL(string: "https://coupley.app/privacy") {
                Link(destination: url) {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8).fill(Brand.textSecondary.opacity(0.15))
                                .frame(width: 30, height: 30)
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Brand.textSecondary)
                        }
                        Text("Privacy Policy")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(Brand.textPrimary)
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Brand.textTertiary)
                    }
                }
            }
        }
        .listRowBackground(surfaceRowBackground)
    }

    // MARK: - Sign Out

    @ViewBuilder
    private var signOutSection: some View {
        Section {
            Button(role: .destructive) {
                showSignOutConfirm = true
            } label: {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text("Sign Out")
                        .fontWeight(.semibold)
                    Spacer()
                }
                .foregroundStyle(Color(red: 1.0, green: 0.40, blue: 0.40))
            }
        }
        .listRowBackground(surfaceRowBackground)
    }

    // MARK: - Shared styling

    private var surfaceRowBackground: some View {
        RoundedRectangle(cornerRadius: 12).fill(Brand.surfaceLight)
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}

// MARK: - Settings Row

private struct SettingsRow: View {
    let icon: String
    let iconTint: Color
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconTint.opacity(0.15))
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(iconTint)
            }
            Text(title)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Brand.textPrimary)
            Spacer()
            Text(value)
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(Brand.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

// MARK: - Edit Name Sheet

private struct EditNameSheet: View {

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = Auth.auth().currentUser?.displayName ?? ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let db = Firestore.firestore()

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.bgGradient.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 20) {
                    BrandField(icon: "person", placeholder: "Your name", text: $name)
                        .autocorrectionDisabled()

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(Color(red: 1.0, green: 0.42, blue: 0.42))
                    }

                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
            }
            .navigationTitle("Edit Name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Brand.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { save() }
                            .foregroundStyle(Brand.accentStart)
                            .fontWeight(.semibold)
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let user = Auth.auth().currentUser else { return }
        isSaving = true
        errorMessage = nil
        Task {
            do {
                let request = user.createProfileChangeRequest()
                request.displayName = trimmed
                try await request.commitChanges()
                try await db.collection(FirestorePath.users).document(user.uid)
                    .setData(["displayName": trimmed], merge: true)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

// MARK: - Pairing container (inside settings)

private struct SettingsPairingContainer: View {
    let session: UserSession?

    @EnvironmentObject private var sessionStore: SessionStore
    @StateObject private var viewModel: PairingViewModel

    init(session: UserSession?) {
        self.session = session
        let uid = session?.userId ?? Auth.auth().currentUser?.uid ?? ""
        let name = Auth.auth().currentUser?.displayName ?? "You"
        _viewModel = StateObject(wrappedValue: PairingViewModel(userId: uid, displayName: name))
    }

    var body: some View {
        ZStack {
            Brand.bgGradient.ignoresSafeArea(.all)
            PairingView(viewModel: viewModel)
        }
        .navigationTitle("Connect")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        SettingsView(session: .demo)
            .environmentObject(SessionStore())
            .environmentObject(ThemeManager())
            .environmentObject(PremiumStore(service: MockPremiumService()))
            .environmentObject(NotificationViewModel())
    }
}
