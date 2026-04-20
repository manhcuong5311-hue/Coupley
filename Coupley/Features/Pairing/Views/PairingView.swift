//
//  PairingView.swift
//  Coupley
//
//  In-app partner connection screen — accessible from Home banner.
//

import SwiftUI

struct PairingView: View {

    @ObservedObject var viewModel: PairingViewModel

    var body: some View {
        ZStack {
            Group {
                switch viewModel.step {
                case .choice:
                    choiceView
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                case .showCode(let code):
                    showCodeView(code: code)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                case .enterCode:
                    enterCodeView
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                }
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.85), value: stepID)
        }
    }

    // MARK: - Choice

    private var choiceView: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(Brand.accentStart.opacity(0.18))
                    .frame(width: 130, height: 130)
                    .blur(radius: 35)

                ZStack {
                    Circle()
                        .fill(Brand.surfaceLight)
                        .frame(width: 96, height: 96)
                        .overlay(Circle().strokeBorder(Brand.divider, lineWidth: 1))

                    Text("💑")
                        .font(.system(size: 40))
                }
            }
            .padding(.bottom, 28)

            VStack(spacing: 10) {
                Text("Connect with\nyour partner")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Hi \(viewModel.displayName)! Create an invite code or enter\nyour partner's code to start syncing.")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 16)
            }

            Spacer()

            VStack(spacing: 12) {
                // Create code
                Button(action: viewModel.generateCode) {
                    HStack(spacing: 10) {
                        if viewModel.isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "link.badge.plus")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Create Invite Code")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Brand.accentGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .shadow(color: Brand.accentStart.opacity(0.40), radius: 14, y: 5)
                }
                .buttonStyle(BouncyButtonStyle())
                .disabled(viewModel.isLoading)

                // Enter code
                GhostButton(title: "Enter Partner's Code") {
                    viewModel.showEnterCode()
                }
                .disabled(viewModel.isLoading)

                // Error
                if let error = viewModel.errorMessage {
                    errorBadge(error)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
    }

    // MARK: - Show Code

    private func showCodeView(code: String) -> some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color(red: 0.35, green: 0.20, blue: 0.90).opacity(0.18))
                        .frame(width: 110, height: 110)
                        .blur(radius: 30)

                    ZStack {
                        Circle()
                            .fill(Brand.surfaceLight)
                            .frame(width: 84, height: 84)
                            .overlay(Circle().strokeBorder(Brand.divider, lineWidth: 1))

                        Image(systemName: "link")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(colors: [Brand.accentStart, Brand.accentEnd],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                    }
                }

                VStack(spacing: 8) {
                    Text("Your invite code")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)

                    Text("Share this with your partner.\nSingle-use · valid for 24 hours")
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }

                // Code display
                Text(code)
                    .font(.system(size: 38, weight: .bold, design: .monospaced))
                    .tracking(10)
                    .foregroundStyle(Brand.textPrimary)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 22)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Brand.accentStart.opacity(0.10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: [Brand.accentStart.opacity(0.55), Brand.accentEnd.opacity(0.30)],
                                            startPoint: .leading, endPoint: .trailing
                                        ),
                                        lineWidth: 1.5
                                    )
                            )
                    )
                    .shimmer()

                InlineCopyButton(code: code)
            }

            Spacer()

            GhostButton(title: "Back") { viewModel.back() }
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
        }
    }

    // MARK: - Enter Code

    private var enterCodeView: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Brand.accentStart.opacity(0.18))
                        .frame(width: 110, height: 110)
                        .blur(radius: 30)

                    ZStack {
                        Circle()
                            .fill(Brand.surfaceLight)
                            .frame(width: 84, height: 84)
                            .overlay(Circle().strokeBorder(Brand.divider, lineWidth: 1))

                        Image(systemName: "keyboard")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(Brand.accentStart)
                    }
                }

                VStack(spacing: 8) {
                    Text("Enter invite code")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)

                    Text("Ask your partner for their 6-character code.")
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)
                        .multilineTextAlignment(.center)
                }

                // Code input
                TextField("e.g. ABC123", text: $viewModel.enteredCode)
                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .tracking(8)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .foregroundStyle(Brand.textPrimary)
                    .accentColor(Brand.accentStart)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Brand.surfaceLight)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(lookupBorderColor, lineWidth: 1.5)
                            )
                    )
                    .padding(.horizontal, 24)

                lookupStateView
                    .padding(.horizontal, 24)

                if let error = viewModel.errorMessage {
                    errorBadge(error)
                        .padding(.horizontal, 24)
                }
            }

            Spacer()

            VStack(spacing: 12) {
                PrimaryButton(
                    title: connectTitle,
                    isLoading: viewModel.isLoading,
                    isEnabled: viewModel.canConnect
                ) {
                    viewModel.joinWithCode()
                }

                GhostButton(title: "Back") { viewModel.back() }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
    }

    private var connectTitle: String {
        if let partner = viewModel.detectedPartner {
            return "Connect with \(partner.displayName)"
        }
        return "Connect"
    }

    private var lookupBorderColor: Color {
        switch viewModel.lookupState {
        case .found:  return Color(red: 0.25, green: 0.78, blue: 0.55).opacity(0.55)
        case .failed: return Color(red: 1.0, green: 0.40, blue: 0.40).opacity(0.55)
        case .loading, .idle: return Brand.divider
        }
    }

    @ViewBuilder
    private var lookupStateView: some View {
        switch viewModel.lookupState {
        case .idle:
            EmptyView()

        case .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Looking up code…")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
            }

        case .found(let preview):
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Brand.accentStart.opacity(0.18))
                        .frame(width: 40, height: 40)
                    Image(systemName: "person.fill.checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Brand.accentStart)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(preview.displayName)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                    Text("Ready to connect")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Color(red: 0.25, green: 0.78, blue: 0.55))
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(red: 0.25, green: 0.78, blue: 0.55).opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color(red: 0.25, green: 0.78, blue: 0.55).opacity(0.35), lineWidth: 1)
                    )
            )
            .transition(.opacity.combined(with: .scale(scale: 0.95)))

        case .failed(let message):
            errorBadge(message)
        }
    }

    // MARK: - Error Badge

    private func errorBadge(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 14))
            Text(message)
                .font(.system(size: 13, weight: .medium, design: .rounded))
        }
        .foregroundStyle(Color(red: 1.0, green: 0.40, blue: 0.40))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(red: 1.0, green: 0.25, blue: 0.25).opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // Used to drive animation
    private var stepID: Int {
        switch viewModel.step {
        case .choice:    return 0
        case .showCode:  return 1
        case .enterCode: return 2
        }
    }
}

// MARK: - Inline Copy Button

private struct InlineCopyButton: View {

    let code: String
    @State private var copied = false

    var body: some View {
        Button {
            UIPasteboard.general.string = code
            copied = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                copied = false
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 14, weight: .semibold))
                Text(copied ? "Copied!" : "Copy Code")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(copied ? Color(red: 0.25, green: 0.78, blue: 0.55) : Brand.accentStart)
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .background(
                Capsule()
                    .fill(copied
                          ? Color(red: 0.25, green: 0.78, blue: 0.55).opacity(0.12)
                          : Brand.accentStart.opacity(0.12))
                    .overlay(
                        Capsule().strokeBorder(
                            copied ? Color(red: 0.25, green: 0.78, blue: 0.55).opacity(0.40) : Brand.accentStart.opacity(0.30),
                            lineWidth: 1
                        )
                    )
            )
        }
        .buttonStyle(BouncyButtonStyle())
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: copied)
    }
}

#Preview {
    ZStack {
        BrandBackground()
        PairingView(viewModel: PairingViewModel(userId: "preview", displayName: "Sam"))
    }
}
