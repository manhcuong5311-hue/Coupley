//
//  AuthViewModel.swift
//  Coupley
//

import Foundation
import Combine
// MARK: - Auth Mode

enum AuthMode {
    case login
    case signUp
}

// MARK: - Auth ViewModel

@MainActor
final class AuthViewModel: ObservableObject {

    @Published var mode: AuthMode = .login
    @Published var email: String = ""
    @Published var password: String = ""
    @Published var confirmPassword: String = ""
    @Published var displayName: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private let authService: any AuthServiceProtocol

    init(authService: (any AuthServiceProtocol)? = nil) {
        self.authService = authService ?? FirebaseAuthService()
        let pending = UserDefaults.standard.string(forKey: "pendingOnboardingName") ?? ""
        if !pending.isEmpty {
            self.displayName = pending
            self.mode = .signUp
        }
    }

    // MARK: - Computed

    var canSubmit: Bool {
        guard !isLoading else { return false }
        if mode == .login {
            return !email.isEmpty && !password.isEmpty
        } else {
            return !email.isEmpty && !password.isEmpty && !displayName.isEmpty
        }
    }

    var submitTitle: String {
        mode == .login ? "Sign In" : "Create Account"
    }

    var togglePrompt: String {
        mode == .login ? "Don't have an account? " : "Already have an account? "
    }

    var toggleAction: String {
        mode == .login ? "Sign up" : "Sign in"
    }

    // MARK: - Actions

    func submit() {
        errorMessage = nil

        if mode == .signUp && password != confirmPassword {
            errorMessage = "Passwords do not match."
            return
        }

        isLoading = true

        Task {
            do {
                let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
                if mode == .login {
                    try await authService.signIn(email: trimmedEmail, password: password)
                } else {
                    let trimmedName = displayName.trimmingCharacters(in: .whitespaces)
                    try await authService.signUp(email: trimmedEmail, password: password, displayName: trimmedName)
                    UserDefaults.standard.removeObject(forKey: "pendingOnboardingName")
                }
                // SessionStore auth listener fires automatically on success
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    func toggleMode() {
        mode = mode == .login ? .signUp : .login
        errorMessage = nil
        password = ""
        confirmPassword = ""
    }
}
