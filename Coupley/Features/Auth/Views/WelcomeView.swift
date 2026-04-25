//
//  WelcomeView.swift
//  Coupley
//
//  Signed-out hero. Mirrors the reference layout:
//    • Brand wordmark + tagline at the top
//    • Hero illustration (`OnboardingPic`) centered, no chrome
//    • Provider stack at the bottom: Apple → Google → Email
//
//  Visual style is calm and warm — no glow orbs, no gradient buttons. The
//  brand background carries the warmth; the foreground is paper-soft.
//

import SwiftUI

struct WelcomeView: View {

    @StateObject private var viewModel = AuthViewModel()
    @State private var showEmailAuth = false

    var body: some View {
        NavigationStack {
            ZStack {
                Image("OnboardingPic")
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .offset(x: -24)
                    .clipped()
                    .ignoresSafeArea()
                    .accessibilityHidden(true)

                VStack(spacing: 0) {
                    wordmark
                        .padding(.top, 12)

                    tagline
                        .padding(.top, 6)

                    Spacer(minLength: 0)

                    providerStack
                        .padding(.horizontal, 24)

                    legalFooter
                        .padding(.top, 18)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, 48)
            }
            .preferredColorScheme(.light)
            .navigationDestination(isPresented: $showEmailAuth) {
                EmailAuthView(viewModel: viewModel)
            }
        }
    }

    // MARK: - Header

    private var wordmark: some View {
        HStack(spacing: 10) {
            ZStack {
                Image(systemName: "heart.fill")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Brand.accentEnd)
                    .offset(x: -6, y: 0)
                Image(systemName: "heart")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Brand.accentStart)
                    .offset(x: 6, y: 0)
            }

            HStack(spacing: 0) {
                Text("Coupley")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                Text("AI")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Brand.accentStart)
            }
        }
    }

    private var tagline: some View {
        Text("Stay connected, stay in tune.")
            .font(.system(size: 15, weight: .regular, design: .rounded))
            .foregroundStyle(Brand.textSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 36)
    }

    // MARK: - Providers

    private var providerStack: some View {
        VStack(spacing: 12) {
            AppleAuthButton(
                isLoading: viewModel.loadingProvider == .apple,
                isDisabled: viewModel.isLoading && viewModel.loadingProvider != .apple
            ) {
                viewModel.signInWithApple()
            }

            GoogleAuthButton(
                isLoading: viewModel.loadingProvider == .google,
                isDisabled: viewModel.isLoading && viewModel.loadingProvider != .google
            ) {
                viewModel.signInWithGoogle()
            }

            EmailAuthButton(
                isDisabled: viewModel.isLoading
            ) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showEmailAuth = true
            }

            if let error = viewModel.errorMessage, !error.isEmpty {
                ErrorBanner(message: error)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 4)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.errorMessage)
    }

    // MARK: - Legal

    private var legalFooter: some View {
        VStack(spacing: 6) {
            Text("By continuing you agree to our")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(Brand.textTertiary)
            HStack(spacing: 4) {
                legalLink("Terms", url: "https://coupley.app/terms")
                Text("·").foregroundStyle(Brand.textTertiary)
                legalLink("Privacy Policy", url: "https://coupley.app/privacy")
            }
            .font(.system(size: 11, weight: .medium, design: .rounded))
        }
    }

    private func legalLink(_ title: String, url: String) -> some View {
        Group {
            if let u = URL(string: url) {
                Link(title, destination: u)
                    .foregroundStyle(Brand.textSecondary)
            } else {
                Text(title).foregroundStyle(Brand.textSecondary)
            }
        }
    }
}

// MARK: - Provider buttons

/// Apple's HIG requires the SF Symbol logomark on a solid background. Black
/// in light mode, white in dark mode — we read color scheme dynamically so
/// the wordmark always reads.
struct AppleAuthButton: View {
    var isLoading: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView().tint(scheme == .dark ? .black : .white)
                } else {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 18, weight: .medium))
                    Text("Continue with Apple")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                }
            }
            .foregroundStyle(scheme == .dark ? .black : .white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(scheme == .dark ? Color.white : Color.black)
            )
            .opacity(isDisabled ? 0.55 : 1.0)
        }
        .buttonStyle(BouncyButtonStyle())
        .disabled(isDisabled || isLoading)
        .accessibilityLabel("Continue with Apple")
    }
}

/// Google's brand guidelines specify white surface, dark text, and the
/// canonical "G" mark. We approximate the mark with SF Symbol "globe" tinted
/// to Google red — close enough for an in-app entry point and safer than
/// shipping a bitmap that needs trademark sign-off.
struct GoogleAuthButton: View {
    var isLoading: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView().tint(Brand.textPrimary)
                } else {
                    GoogleGlyph()
                        .frame(width: 18, height: 18)
                    Text("Continue with Google")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                }
            }
            .foregroundStyle(Brand.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Brand.surfaceLight)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Brand.divider, lineWidth: 1)
                    )
            )
            .opacity(isDisabled ? 0.55 : 1.0)
        }
        .buttonStyle(BouncyButtonStyle())
        .disabled(isDisabled || isLoading)
        .accessibilityLabel("Continue with Google")
    }
}

/// Vector "G" approximation — four colored quarter rings on a thick stroke.
/// Recognizable enough to read as Google without shipping a logo PNG.
private struct GoogleGlyph: View {
    var body: some View {
        Canvas { ctx, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1.5, dy: 1.5)
            let lineWidth: CGFloat = size.width * 0.22

            // Four arcs of the canonical Google colors — visually approximates the
            // "G" mark. Direction: right-side blue, bottom green, left red,
            // top yellow.
            let colors: [(start: Double, end: Double, color: Color)] = [
                (-30, 60,  Color(red: 0.26, green: 0.52, blue: 0.96)),  // blue
                (60,  150, Color(red: 0.20, green: 0.66, blue: 0.33)),  // green
                (150, 240, Color(red: 0.92, green: 0.26, blue: 0.21)),  // red
                (240, 330, Color(red: 0.98, green: 0.74, blue: 0.02))   // yellow
            ]

            for arc in colors {
                var path = Path()
                path.addArc(
                    center: CGPoint(x: rect.midX, y: rect.midY),
                    radius: rect.width / 2 - lineWidth / 2,
                    startAngle: .degrees(arc.start),
                    endAngle: .degrees(arc.end),
                    clockwise: false
                )
                ctx.stroke(
                    path,
                    with: .color(arc.color),
                    lineWidth: lineWidth
                )
            }

            // Horizontal bar of the "G"
            let bar = CGRect(
                x: rect.midX,
                y: rect.midY - lineWidth * 0.45,
                width: rect.width / 2 - lineWidth * 0.5,
                height: lineWidth * 0.9
            )
            ctx.fill(Path(bar), with: .color(Color(red: 0.26, green: 0.52, blue: 0.96)))
        }
    }
}

struct EmailAuthButton: View {
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "envelope")
                    .font(.system(size: 16, weight: .semibold))
                Text("Continue with Email")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(Brand.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Brand.surfaceLight)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Brand.divider, lineWidth: 1)
                    )
            )
            .opacity(isDisabled ? 0.55 : 1.0)
        }
        .buttonStyle(BouncyButtonStyle())
        .disabled(isDisabled)
        .accessibilityLabel("Continue with Email")
    }
}

// MARK: - Error Banner

struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 14))
            Text(message)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .multilineTextAlignment(.leading)
            Spacer()
        }
        .foregroundStyle(Color(red: 0.85, green: 0.30, blue: 0.30))
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 1.0, green: 0.30, blue: 0.30).opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color(red: 1.0, green: 0.30, blue: 0.30).opacity(0.20),
                                      lineWidth: 1)
                )
        )
    }
}

#Preview {
    WelcomeView()
}
