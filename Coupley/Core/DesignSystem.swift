//
//  DesignSystem.swift
//  Coupley
//
//  Shared design tokens, colors, and interactive components.
//

import SwiftUI
import UIKit

// MARK: - Adaptive Color Helper

extension Color {
    /// Build a dynamic Color that switches between light and dark appearance.
    static func adaptive(dark: UIColor, light: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

// MARK: - Brand Colors

enum Brand {
    // Deep backgrounds (adapt light/dark)
    static let backgroundTop = Color.adaptive(
        dark:  UIColor(red: 0.07, green: 0.04, blue: 0.15, alpha: 1),
        light: UIColor(red: 0.98, green: 0.96, blue: 0.99, alpha: 1)
    )
    static let backgroundBottom = Color.adaptive(
        dark:  UIColor(red: 0.12, green: 0.06, blue: 0.22, alpha: 1),
        light: UIColor(red: 1.00, green: 0.94, blue: 0.92, alpha: 1)
    )
    static let backgroundMid = Color.adaptive(
        dark:  UIColor(red: 0.09, green: 0.05, blue: 0.18, alpha: 1),
        light: UIColor(red: 0.99, green: 0.95, blue: 0.96, alpha: 1)
    )

    // Accent gradient: rose → coral (same in both modes)
    static let accentStart  = Color(red: 1.00, green: 0.38, blue: 0.60)
    static let accentEnd    = Color(red: 1.00, green: 0.60, blue: 0.35)

    // Soft surfaces (adapt)
    static let surfaceLight = Color.adaptive(
        dark:  UIColor.white.withAlphaComponent(0.08),
        light: UIColor.black.withAlphaComponent(0.04)
    )
    static let surfaceMid = Color.adaptive(
        dark:  UIColor.white.withAlphaComponent(0.12),
        light: UIColor.black.withAlphaComponent(0.07)
    )
    static let divider = Color.adaptive(
        dark:  UIColor.white.withAlphaComponent(0.10),
        light: UIColor.black.withAlphaComponent(0.08)
    )

    // Text (adapt)
    static let textPrimary = Color.adaptive(
        dark:  UIColor.white,
        light: UIColor.black
    )
    static let textSecondary = Color.adaptive(
        dark:  UIColor.white.withAlphaComponent(0.62),
        light: UIColor.black.withAlphaComponent(0.60)
    )
    static let textTertiary = Color.adaptive(
        dark:  UIColor.white.withAlphaComponent(0.38),
        light: UIColor.black.withAlphaComponent(0.42)
    )

    // Accent gradient shorthand
    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accentStart, accentEnd], startPoint: .leading, endPoint: .trailing)
    }

    static var bgGradient: LinearGradient {
        LinearGradient(
            colors: [backgroundTop, backgroundMid, backgroundBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Bouncy Button Style

struct BouncyButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Primary Gradient Button

struct PrimaryButton: View {
    let title: String
    var isLoading: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        }) {
            ZStack {
                if isLoading {
                    ProgressView().tint(.white)
                } else {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                Group {
                    if isEnabled {
                        Brand.accentGradient
                    } else {
                        LinearGradient(colors: [Brand.accentStart.opacity(0.35), Brand.accentEnd.opacity(0.35)],
                                       startPoint: .leading, endPoint: .trailing)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: Brand.accentStart.opacity(isEnabled ? 0.40 : 0.0), radius: 16, y: 6)
        }
        .buttonStyle(BouncyButtonStyle())
        .disabled(!isEnabled || isLoading)
    }
}

// MARK: - Ghost Button

struct GhostButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(Brand.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Brand.surfaceLight)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Brand.divider, lineWidth: 1)
                )
        }
        .buttonStyle(BouncyButtonStyle())
    }
}

// MARK: - Glass Card

struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 20
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Brand.surfaceLight)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .strokeBorder(Brand.divider, lineWidth: 1)
                    )
            )
    }
}

// MARK: - Brand Background

struct BrandBackground: View {
    var body: some View {
        ZStack {
            Brand.bgGradient
                .ignoresSafeArea(.all)

            // Ambient glow top-left
            Circle()
                .fill(Brand.accentStart.opacity(0.18))
                .frame(width: 340, height: 340)
                .blur(radius: 90)
                .offset(x: -80, y: -120)

            // Ambient glow bottom-right
            Circle()
                .fill(Color(red: 0.35, green: 0.15, blue: 0.90).opacity(0.12))
                .frame(width: 280, height: 280)
                .blur(radius: 80)
                .offset(x: 100, y: 200)
        }
        .ignoresSafeArea(.all)
    }
}

// MARK: - Window Background Fixer (UIKit level)
//
// SwiftUI's ignoresSafeArea only works within the layout tree.
// The UIHostingController's view still has a black background.
// This UIView subclass sets all backgrounds the moment it attaches to a window.
//
final class _BrandWindowFixer: UIView {
    private static let brandUIColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.07, green: 0.04, blue: 0.15, alpha: 1.0)
            : UIColor(red: 0.98, green: 0.96, blue: 0.99, alpha: 1.0)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard let window else { return }
        window.backgroundColor = Self.brandUIColor
        var responder: UIResponder? = self
        while let r = responder {
            if let vc = r as? UIViewController {
                vc.view.backgroundColor = Self.brandUIColor
            }
            responder = r.next
        }
        window.rootViewController?.view.backgroundColor = Self.brandUIColor
    }
}

struct WindowBackgroundFixer: UIViewRepresentable {
    func makeUIView(context: Context) -> _BrandWindowFixer {
        let v = _BrandWindowFixer()
        v.backgroundColor = .clear
        v.isUserInteractionEnabled = false
        return v
    }
    func updateUIView(_ uiView: _BrandWindowFixer, context: Context) {}
}

extension View {
    /// Attach this to the very root view to guarantee no black bars.
    func fixWindowBackground() -> some View {
        self.background(WindowBackgroundFixer().ignoresSafeArea(.all))
    }
}

// MARK: - Full Screen Background Modifier

extension View {
    /// Applies the brand gradient as a true full-screen background.
    func brandBackground() -> some View {
        self
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Brand.bgGradient.ignoresSafeArea(.all))
            .fixWindowBackground()
    }
}

// MARK: - Shimmer Effect

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.15), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 3)
                    .offset(x: phase * geo.size.width * 3)
                }
                .clipped()
            )
            .onAppear {
                withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}
