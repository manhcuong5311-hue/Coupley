//
//  AuthView.swift
//  Coupley
//
//  Email + password sub-flow, pushed onto WelcomeView's NavigationStack
//  when the user taps "Continue with Email". Shares an `AuthViewModel`
//  with WelcomeView so loading/error state is coherent across providers.
//
//  Two visual modes: `.login` (existing user) and `.signUp` (new user).
//  The toggle row at the bottom flips between them with a soft spring;
//  fields and CTA copy animate accordingly.
//

import SwiftUI

struct EmailAuthView: View {

    @ObservedObject var viewModel: AuthViewModel
    @FocusState private var focusedField: Field?
    @Environment(\.dismiss) private var dismiss

    private enum Field { case name, email, password, confirm }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                headerSection
                formSection
                submitSection
                Spacer(minLength: 24)
                toggleSection
                Spacer(minLength: 60)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .brandBackground()
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(viewModel.mode == .login ? "Sign In" : "Create Account")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.85), value: viewModel.mode)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Brand.accentStart.opacity(0.12))
                    .frame(width: 90, height: 90)
                    .blur(radius: 22)

                Circle()
                    .fill(Brand.surfaceLight)
                    .frame(width: 70, height: 70)
                    .overlay(Circle().strokeBorder(Brand.divider, lineWidth: 1))
                    .overlay {
                        Image(systemName: viewModel.mode == .login ? "lock.open.fill" : "person.fill.badge.plus")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(Brand.accentStart)
                    }
            }
            .padding(.top, 28)

            Text(viewModel.mode == .login ? "Welcome back" : "Create your account")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(Brand.textPrimary)
                .multilineTextAlignment(.center)

            Text(viewModel.mode == .login
                 ? "Sign in to reconnect with your partner."
                 : "Start your journey together.")
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundStyle(Brand.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 32)
    }

    // MARK: - Form

    private var formSection: some View {
        VStack(spacing: 14) {
            if viewModel.mode == .signUp {
                BrandField(icon: "person", placeholder: "Your name", text: $viewModel.displayName)
                    .focused($focusedField, equals: .name)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            BrandField(icon: "envelope",
                       placeholder: "Email address",
                       text: $viewModel.email,
                       keyboardType: .emailAddress,
                       textContentType: .emailAddress)
                .focused($focusedField, equals: .email)

            BrandField(icon: "lock",
                       placeholder: "Password",
                       text: $viewModel.password,
                       textContentType: viewModel.mode == .login ? .password : .newPassword,
                       isSecure: true)
                .focused($focusedField, equals: .password)

            if viewModel.mode == .signUp {
                BrandField(icon: "lock.fill",
                           placeholder: "Confirm password",
                           text: $viewModel.confirmPassword,
                           textContentType: .newPassword,
                           isSecure: true)
                    .focused($focusedField, equals: .confirm)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if let error = viewModel.errorMessage, !error.isEmpty {
                ErrorBanner(message: error)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Submit

    private var submitSection: some View {
        PrimaryButton(title: viewModel.submitTitle,
                      isLoading: viewModel.loadingProvider == .email,
                      isEnabled: viewModel.canSubmit) {
            focusedField = nil
            viewModel.submitEmail()
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
    }

    // MARK: - Toggle

    private var toggleSection: some View {
        HStack(spacing: 5) {
            Text(viewModel.togglePrompt).foregroundStyle(Brand.textSecondary)
            Button(viewModel.toggleAction) {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) { viewModel.toggleMode() }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            .foregroundStyle(Brand.accentStart)
            .fontWeight(.semibold)
        }
        .font(.system(size: 14, weight: .regular, design: .rounded))
        .padding(.top, 12)
    }
}

// MARK: - Brand Field

struct BrandField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType? = nil
    var isSecure: Bool = false
    @State private var isFocused = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isFocused ? Brand.accentStart : Brand.textSecondary)
                .frame(width: 20)
                .animation(.easeInOut(duration: 0.2), value: isFocused)

            if isSecure {
                SecureField(placeholder, text: $text)
                    .textContentType(textContentType)
                    .autocorrectionDisabled()
                    .font(.system(size: 16, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                    .tint(Brand.accentStart)
            } else {
                TextField(placeholder, text: $text)
                    .keyboardType(keyboardType)
                    .textContentType(textContentType)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(keyboardType == .emailAddress ? .never : .words)
                    .font(.system(size: 16, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                    .tint(Brand.accentStart)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isFocused ? Brand.accentStart.opacity(0.08) : Brand.surfaceLight)
                .overlay(RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isFocused ? Brand.accentStart.opacity(0.55) : Brand.divider,
                                  lineWidth: isFocused ? 1.5 : 1))
                .animation(.easeInOut(duration: 0.2), value: isFocused)
        )
        .onTapGesture { isFocused = true }
    }
}

#Preview {
    NavigationStack {
        EmailAuthView(viewModel: AuthViewModel())
    }
}
