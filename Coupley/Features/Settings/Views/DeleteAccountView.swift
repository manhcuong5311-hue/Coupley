//
//  DeleteAccountView.swift
//  Coupley
//
//  Apple Guideline 5.1.1(v) — In-app account deletion flow.
//
//  Four steps, surfaced as a navigation push from Settings:
//
//    1. Warning      — What gets deleted, irreversibility, "I understand"
//                      toggle, Continue button (disabled until toggle is on).
//    2. Confirm      — Type "DELETE" verification field. Email accounts also
//                      enter their password here so the entire confirmation
//                      lives on one screen. Single red destructive CTA.
//    3. Deleting     — Full-screen loading overlay while the pipeline runs.
//                      Re-auth (system Apple/Google sheet or password) is
//                      driven from inside the pipeline.
//    4. Finished     — Success state. After the user dismisses, the auth
//                      state listener has already routed RootView → Welcome.
//
//  Every destructive action requires explicit user gesture. There is no
//  silent path to deletion.
//

import SwiftUI
import FirebaseAuth

// MARK: - Delete Step

private enum DeleteStep: Equatable {
    case warning
    case confirm
    case deleting
    case finished
}

// MARK: - View

struct DeleteAccountView: View {

    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var premiumStore: PremiumStore
    @Environment(\.dismiss) private var dismiss

    @StateObject private var deletionService = AccountDeletionService()

    // Flow state
    @State private var step: DeleteStep = .warning
    @State private var hasAcknowledged = false
    @State private var typedConfirmation = ""
    @State private var password = ""
    @State private var errorMessage: String?

    // Status copy shown during the .deleting phase
    @State private var deletingStatus = "Removing your account…"

    @FocusState private var focusedField: ConfirmField?

    private let requiredPhrase = "DELETE"

    private enum ConfirmField: Hashable { case typed, password }

    var body: some View {
        ZStack {
            Brand.bgGradient.ignoresSafeArea(.all)

            switch step {
            case .warning:   warningStep
            case .confirm:   confirmStep
            case .deleting:  deletingStep
            case .finished:  finishedStep
            }
        }
        .navigationTitle("Delete Account")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(step == .deleting || step == .finished)
        .interactiveDismissDisabled(step == .deleting)
        .animation(.easeInOut(duration: 0.25), value: step)
    }

    // MARK: - Step 1 — Warning

    private var warningStep: some View {
        ScrollView {
            VStack(spacing: 28) {
                warningIcon
                    .padding(.top, 24)

                VStack(spacing: 10) {
                    Text("Delete your account?")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("This action is permanent. You will not be able to recover your data.")
                        .font(.system(size: 15, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }

                deletionSummaryCard

                if premiumStore.isActive {
                    subscriptionNoticeCard
                }

                acknowledgeToggle

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    typedConfirmation = ""
                    password = ""
                    errorMessage = nil
                    step = .confirm
                } label: {
                    Text("Continue")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(hasAcknowledged
                                    ? AnyShapeStyle(destructiveGradient)
                                    : AnyShapeStyle(Color.gray.opacity(0.35)))
                        )
                }
                .buttonStyle(BouncyButtonStyle())
                .disabled(!hasAcknowledged)

                Button("Cancel") {
                    dismiss()
                }
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Brand.textSecondary)
                .padding(.bottom, 32)
            }
            .padding(.horizontal, 22)
        }
    }

    private var warningIcon: some View {
        ZStack {
            Circle()
                .fill(destructiveColor.opacity(0.12))
                .frame(width: 100, height: 100)
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(destructiveColor)
        }
    }

    private var deletionSummaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What will be deleted")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Brand.textTertiary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 12) {
                summaryRow(
                    icon: "person.crop.circle.fill",
                    title: "Your profile",
                    detail: "Name, email, sign-in info, preferences"
                )
                summaryRow(
                    icon: "bubble.left.and.bubble.right.fill",
                    title: "Shared mood & memory data",
                    detail: "Moods, reactions, chat, quizzes, anniversaries, dream board"
                )
                summaryRow(
                    icon: "heart.slash.fill",
                    title: "Your partner connection",
                    detail: "Your partner is notified and returned to free tier"
                )
                summaryRow(
                    icon: "iphone",
                    title: "Local data on this device",
                    detail: "Cache, draft messages, sign-in session"
                )
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Brand.surfaceLight)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Brand.divider, lineWidth: 1)
                )
        )
    }

    private func summaryRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(destructiveColor)
                .frame(width: 22)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                Text(detail)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var subscriptionNoticeCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Brand.accentStart)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text("Active subscription")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                Text("Deleting your account will not cancel your subscription. " +
                     "Cancel separately in Settings → Apple ID → Subscriptions to stop billing.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Open Manage Subscriptions") {
                    Task { await premiumStore.openManageSubscriptions() }
                }
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Brand.accentStart)
                .padding(.top, 4)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Brand.accentStart.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Brand.accentStart.opacity(0.20), lineWidth: 1)
                )
        )
    }

    private var acknowledgeToggle: some View {
        Toggle(isOn: $hasAcknowledged) {
            Text("I understand this action is permanent and my data cannot be recovered.")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Brand.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .tint(destructiveColor)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Brand.surfaceLight)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Brand.divider, lineWidth: 1)
                )
        )
    }

    // MARK: - Step 2 — Confirm (type DELETE + password if email)

    private var confirmStep: some View {
        ScrollView {
            VStack(spacing: 22) {
                ZStack {
                    Circle()
                        .fill(destructiveColor.opacity(0.12))
                        .frame(width: 80, height: 80)
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(destructiveColor)
                }
                .padding(.top, 28)

                VStack(spacing: 8) {
                    Text("Final confirmation")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                    Text("Type \(requiredPhrase) below to permanently delete your account.")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }

                typeConfirmField

                if isPasswordRequired {
                    passwordField
                }

                providerHintCard

                if let errorMessage, !errorMessage.isEmpty {
                    errorBanner(errorMessage)
                }

                Button {
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    runDeletion()
                } label: {
                    Text("Permanently Delete My Account")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(canConfirmDelete
                                    ? AnyShapeStyle(destructiveGradient)
                                    : AnyShapeStyle(Color.gray.opacity(0.35)))
                        )
                }
                .buttonStyle(BouncyButtonStyle())
                .disabled(!canConfirmDelete)

                Button("Cancel") {
                    typedConfirmation = ""
                    password = ""
                    errorMessage = nil
                    step = .warning
                }
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Brand.textSecondary)
                .padding(.bottom, 32)
            }
            .padding(.horizontal, 22)
        }
    }

    private var typeConfirmField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Type \(requiredPhrase)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Brand.textTertiary)
                .textCase(.uppercase)
            HStack {
                TextField(requiredPhrase, text: $typedConfirmation)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                    .focused($focusedField, equals: .typed)
                if typedConfirmation == requiredPhrase {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(red: 0.30, green: 0.78, blue: 0.50))
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Brand.surfaceLight)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(
                                typedConfirmation == requiredPhrase
                                    ? Color(red: 0.30, green: 0.78, blue: 0.50).opacity(0.5)
                                    : Brand.divider,
                                lineWidth: 1
                            )
                    )
            )
        }
    }

    private var passwordField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your password")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Brand.textTertiary)
                .textCase(.uppercase)
            SecureField("Password", text: $password)
                .textContentType(.password)
                .autocorrectionDisabled()
                .font(.system(size: 16, design: .rounded))
                .foregroundStyle(Brand.textPrimary)
                .focused($focusedField, equals: .password)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Brand.surfaceLight)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(Brand.divider, lineWidth: 1)
                        )
                )

            if let email = deletionService.currentEmail {
                Text("Account: \(email)")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Brand.textTertiary)
            }
        }
    }

    private var providerHintCard: some View {
        let provider = deletionService.currentProvider
        let label: String
        let icon: String
        switch provider {
        case .apple:
            label = "We'll ask you to confirm with Apple before deleting."
            icon  = "applelogo"
        case .google:
            label = "We'll ask you to confirm with Google before deleting."
            icon  = "g.circle"
        case .password:
            label = "Enter your password above so we can verify your identity."
            icon  = "envelope.fill"
        case .none:
            label = "Sign in again before deleting your account."
            icon  = "exclamationmark.triangle"
        }
        return HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Brand.textSecondary)
            Text(label)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(Brand.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Brand.surfaceLight.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Brand.divider, lineWidth: 1)
                )
        )
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(destructiveColor)
                .padding(.top, 1)
            Text(message)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Brand.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(destructiveColor.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(destructiveColor.opacity(0.30), lineWidth: 1)
                )
        )
    }

    // MARK: - Step 3 — Deleting

    private var deletingStep: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.6)
                .padding(.bottom, 6)

            VStack(spacing: 6) {
                Text("Deleting your account")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                Text(deletingStatus)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Text("Please don't close the app.")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(Brand.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 22)
    }

    // MARK: - Step 4 — Finished

    private var finishedStep: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.30, green: 0.78, blue: 0.50).opacity(0.12))
                    .frame(width: 100, height: 100)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(Color(red: 0.30, green: 0.78, blue: 0.50))
            }

            VStack(spacing: 8) {
                Text("Account deleted")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                Text("Your account and all your data have been removed. " +
                     "You'll be signed out automatically.")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
            }

            if premiumStore.isActive {
                Text("Remember to cancel your subscription in Settings → Apple ID → Subscriptions if you no longer want to be charged.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Brand.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            Button("Done") {
                // The auth-state listener has already routed RootView →
                // WelcomeView. This dismiss is a safety net for the brief
                // moment between user.delete() and the listener firing.
                sessionStore.signOut()
                dismiss()
            }
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Brand.accentGradient)
            )
            .padding(.top, 6)
            .padding(.horizontal, 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 22)
    }

    // MARK: - Run deletion pipeline

    private var canConfirmDelete: Bool {
        guard typedConfirmation == requiredPhrase else { return false }
        if isPasswordRequired { return !password.isEmpty }
        return true
    }

    private var isPasswordRequired: Bool {
        deletionService.currentProvider == .password
    }

    private func runDeletion() {
        focusedField = nil
        errorMessage = nil
        step = .deleting

        Task { @MainActor in
            do {
                deletingStatus = "Verifying your identity…"
                let appleAuthCode = try await deletionService.reauthenticate(
                    password: isPasswordRequired ? password : nil
                )

                deletingStatus = "Removing your shared data…"

                // Detach the user-doc listener so the impending /users/{uid}
                // delete doesn't briefly re-route to the pairing screen.
                sessionStore.prepareForDeletion()

                let session = sessionStore.session
                let archived = sessionStore.lastCoupleId
                let partnerName = sessionStore.lastPartnerName

                deletingStatus = "Removing your profile…"
                try await deletionService.deleteEverything(
                    session: session,
                    partnerDisplayName: partnerName,
                    archivedCoupleId: archived,
                    appleAuthorizationCode: appleAuthCode
                )

                deletingStatus = "All done."
                step = .finished
            } catch let error as AccountDeletionError {
                handle(error)
            } catch {
                handle(.deletionFailed(error.localizedDescription))
            }
        }
    }

    private func handle(_ error: AccountDeletionError) {
        // If the deletion pipeline ran far enough to detach the user-doc
        // listener via `prepareForDeletion()`, restore it now so the app
        // doesn't end up in a half-detached state with no Firestore
        // observer on /users/{uid}. `refreshSession()` is idempotent.
        sessionStore.refreshSession()

        // User-cancelled is the only "silent" failure mode — they tapped
        // Cancel on the system Apple/Google sheet, which isn't really an
        // error. Drop them back to the confirm step without surfacing copy.
        if case .userCancelledReauth = error {
            step = .confirm
            return
        }
        password = ""
        errorMessage = error.errorDescription
        step = .confirm
    }

    // MARK: - Style helpers

    private var destructiveColor: Color {
        Color(red: 0.92, green: 0.30, blue: 0.30)
    }

    private var destructiveGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.95, green: 0.35, blue: 0.30),
                Color(red: 0.85, green: 0.20, blue: 0.25)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

#Preview {
    NavigationStack {
        DeleteAccountView()
            .environmentObject(SessionStore())
            .environmentObject(PremiumStore(service: MockPremiumService()))
    }
}
