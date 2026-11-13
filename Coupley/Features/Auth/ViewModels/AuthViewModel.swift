//
//  AuthViewModel.swift
//  Coupley
//
//  Single view model serving every entry point on the auth surface:
//    • WelcomeView   — Apple / Google / Email provider buttons
//    • EmailAuthView — email + password (login or sign-up)
//
//  Keeping one observable means the loading / error states are coherent
//  across the surface — tapping Apple disables Email, tapping Email disables
//  Apple, and an error shown on one route is cleared the moment the user
//  pivots to another.
//

import Foundation
import Combine

// MARK: - Mode

enum AuthMode {
    case login
    case signUp
}

// MARK: - Provider

enum AuthProvider: String {
    case apple, google, email
}

// MARK: - View Model

@MainActor
final class AuthViewModel: ObservableObject {

    // Email form state
    @Published var mode: AuthMode = .login
    @Published var email: String = ""
    @Published var password: String = ""
    @Published var confirmPassword: String = ""
    @Published var displayName: String = ""

    // Cross-provider state
    @Published var isLoading: Bool = false
    @Published var loadingProvider: AuthProvider?
    @Published var errorMessage: String?

    private let authService: any AuthServiceProtocol

    init(authService: (any AuthServiceProtocol)? = nil) {
        self.authService = authService ?? FirebaseAuthService()
    }

    // MARK: - Email validation

    var canSubmit: Bool {
        guard !isLoading else { return false }
        if mode == .login {
            return !trimmedEmail.isEmpty && !password.isEmpty
        } else {
            return !trimmedEmail.isEmpty &&
                !password.isEmpty &&
                !displayName.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    var submitTitle: LocalizedStringResource {
        mode == .login
            ? LocalizedStringResource("Sign In", comment: "Email sign-in screen: title and submit button")
            : LocalizedStringResource("Create Account", comment: "Email sign-up screen: title and submit button")
    }

    var togglePrompt: LocalizedStringResource {
        mode == .login ? "New to Coupley?" : "Already have an account?"
    }

    var toggleAction: LocalizedStringResource {
        mode == .login
            ? LocalizedStringResource("Sign up", comment: "Link after 'New to Coupley?': switch the form to creating an account")
            : LocalizedStringResource("Sign in", comment: "Link after 'Already have an account?': switch the form to signing in")
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Email actions

    func submitEmail() {
        errorMessage = nil

        if mode == .signUp && password != confirmPassword {
            errorMessage = String(localized: "Passwords do not match.")
            return
        }

        runProvider(.email) { [self] in
            if mode == .login {
                try await authService.signIn(email: trimmedEmail, password: password)
            } else {
                let trimmedName = displayName.trimmingCharacters(in: .whitespaces)
                try await authService.signUp(
                    email: trimmedEmail,
                    password: password,
                    displayName: trimmedName
                )
            }
        }
    }

    func toggleMode() {
        mode = mode == .login ? .signUp : .login
        errorMessage = nil
        password = ""
        confirmPassword = ""
    }

    // MARK: - Apple / Google

    func signInWithApple() {
        runProvider(.apple) { [self] in
            try await authService.signInWithApple()
        }
    }

    func signInWithGoogle() {
        runProvider(.google) { [self] in
            try await authService.signInWithGoogle()
        }
    }

    // MARK: - Provider runner

    /// Centralizes loading/error handling so each provider entry point is a
    /// single line. `AuthError.providerCancelled` is silent — a deliberate
    /// user cancel shouldn't flash a scary banner.
    private func runProvider(_ provider: AuthProvider,
                             _ work: @escaping () async throws -> Void) {
        guard !isLoading else { return }
        isLoading = true
        loadingProvider = provider
        errorMessage = nil

        Task {
            do {
                try await work()
                // SessionStore auth listener flips appState automatically.
            } catch let error as AuthError {
                if case .providerCancelled = error {
                    // silent
                } else if !error.localizedDescription.isEmpty {
                    errorMessage = error.localizedDescription
                }
            } catch {
                // Firebase's own messages are English-only; the common,
                // fixable failures (wrong password, email in use…) get ours.
                errorMessage = AuthError.friendlyMessage(for: error, isEmailSignIn: provider == .email)
                    ?? error.localizedDescription
            }
            isLoading = false
            loadingProvider = nil
        }
    }
}
