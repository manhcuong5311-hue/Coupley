//
//  AuthView.swift
//  Coupley
//

import SwiftUI

struct AuthView: View {

    @StateObject private var viewModel = AuthViewModel()
    @FocusState private var focusedField: Field?

    private enum Field { case name, email, password, confirm }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                headerSection
                formSection
                submitSection
                toggleSection
                Spacer(minLength: 60)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .brandBackground()
        .animation(.spring(response: 0.38, dampingFraction: 0.85), value: viewModel.mode)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Brand.accentStart.opacity(0.15))
                    .frame(width: 110, height: 110)
                    .blur(radius: 30)

                Circle()
                    .fill(Brand.surfaceLight)
                    .frame(width: 80, height: 80)
                    .overlay(Circle().strokeBorder(Brand.divider, lineWidth: 1))
                    .overlay { Text("💑").font(.system(size: 34)) }
            }
            .padding(.top, 90)

            Text(viewModel.mode == .login ? "Welcome back" : "Create your account")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(Brand.textPrimary)
                .multilineTextAlignment(.center)

            Text(viewModel.mode == .login
                 ? "Sign in to reconnect with your partner."
                 : "Start your journey together.")
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(Brand.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 44)
    }

    // MARK: - Form

    private var formSection: some View {
        VStack(spacing: 14) {
            if viewModel.mode == .signUp {
                BrandField(icon: "person", placeholder: "Your name", text: $viewModel.displayName)
                    .focused($focusedField, equals: .name)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            BrandField(icon: "envelope", placeholder: "Email address",
                       text: $viewModel.email, keyboardType: .emailAddress, textContentType: .emailAddress)
                .focused($focusedField, equals: .email)

            BrandField(icon: "lock", placeholder: "Password",
                       text: $viewModel.password,
                       textContentType: viewModel.mode == .login ? .password : .newPassword,
                       isSecure: true)
                .focused($focusedField, equals: .password)

            if viewModel.mode == .signUp {
                BrandField(icon: "lock.fill", placeholder: "Confirm password",
                           text: $viewModel.confirmPassword,
                           textContentType: .newPassword, isSecure: true)
                    .focused($focusedField, equals: .confirm)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if let error = viewModel.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill").font(.system(size: 14))
                    Text(error).font(.system(size: 13, weight: .medium, design: .rounded))
                }
                .foregroundStyle(Color(red: 1.0, green: 0.42, blue: 0.42))
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 1.0, green: 0.25, blue: 0.25).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Submit

    private var submitSection: some View {
        PrimaryButton(title: viewModel.submitTitle,
                      isLoading: viewModel.isLoading,
                      isEnabled: viewModel.canSubmit) {
            focusedField = nil
            viewModel.submit()
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
    }

    // MARK: - Toggle

    private var toggleSection: some View {
        HStack(spacing: 5) {
            Text(viewModel.togglePrompt).foregroundStyle(Brand.textSecondary)
            Button(viewModel.toggleAction) {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) { viewModel.toggleMode() }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            .foregroundStyle(Brand.accentStart).fontWeight(.semibold)
        }
        .font(.system(size: 14, weight: .regular, design: .rounded))
        .padding(.top, 24)
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
