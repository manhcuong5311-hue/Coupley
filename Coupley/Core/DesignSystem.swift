//
//  DesignSystem.swift
//  Coupley
//
//  Shared design tokens, colors, and interactive components.
//  Colors are sourced from `Palette` (which resolves the active ThemeVariant at
//  render time). Shape tokens (corner radii, glow, gradient vs. flat) are sourced
//  from `ThemeVariant.current`.
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

// MARK: - Brand Tokens

enum Brand {

    // Backgrounds
    static var backgroundTop:    Color { Palette.backgroundTop }
    static var backgroundMid:    Color { Palette.backgroundMid }
    static var backgroundBottom: Color { Palette.backgroundBottom }

    // Accents
    static var accentStart: Color { Palette.accentStart }
    static var accentEnd:   Color { Palette.accentEnd }

    // Surfaces
    static var surfaceLight: Color { Palette.surfaceLight }
    static var surfaceMid:   Color { Palette.surfaceMid }
    static var divider:      Color { Palette.divider }

    // Text
    static var textPrimary:   Color { Palette.textPrimary }
    static var textSecondary: Color { Palette.textSecondary }
    static var textTertiary:  Color { Palette.textTertiary }

    // Accent gradient (falls back to solid for flat variants)
    static var accentGradient: LinearGradient {
        if ThemeVariant.current.usesSolidPrimary {
            return LinearGradient(colors: [accentStart, accentStart],
                                  startPoint: .leading, endPoint: .trailing)
        }
        return LinearGradient(colors: [accentStart, accentEnd],
                              startPoint: .leading, endPoint: .trailing)
    }

    static var bgGradient: LinearGradient {
        LinearGradient(
            colors: [backgroundTop, backgroundMid, backgroundBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // Shape tokens (re-exposed for call sites)
    static var buttonCornerRadius: CGFloat { ThemeVariant.current.buttonCornerRadius }
    static var cardCornerRadius:   CGFloat { ThemeVariant.current.cardCornerRadius }
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
        let radius = Brand.buttonCornerRadius
        let variant = ThemeVariant.current

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
                        LinearGradient(
                            colors: [Brand.accentStart.opacity(0.35), Brand.accentEnd.opacity(0.35)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .shadow(
                color: Brand.accentStart.opacity(variant.showsAmbientGlow && isEnabled ? 0.40 : 0.0),
                radius: 16, y: 6
            )
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
        let radius = Brand.buttonCornerRadius - 2

        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(Brand.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Brand.surfaceLight)
                .clipShape(RoundedRectangle(cornerRadius: radius))
                .overlay(
                    RoundedRectangle(cornerRadius: radius)
                        .strokeBorder(Brand.divider, lineWidth: 1)
                )
        }
        .buttonStyle(BouncyButtonStyle())
    }
}

// MARK: - Glass Card

struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        let r = cornerRadius ?? Brand.cardCornerRadius
        content()
            .background(
                RoundedRectangle(cornerRadius: r)
                    .fill(Brand.surfaceLight)
                    .overlay(
                        RoundedRectangle(cornerRadius: r)
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

            if ThemeVariant.current.showsAmbientGlow {
                Circle()
                    .fill(Brand.accentStart.opacity(0.18))
                    .frame(width: 340, height: 340)
                    .blur(radius: 90)
                    .offset(x: -80, y: -120)

                Circle()
                    .fill(Color(red: 0.35, green: 0.15, blue: 0.90).opacity(0.12))
                    .frame(width: 280, height: 280)
                    .blur(radius: 80)
                    .offset(x: 100, y: 200)
            }
        }
        .ignoresSafeArea(.all)
    }
}

// MARK: - Window Background Fixer (UIKit level)
//
// SwiftUI's ignoresSafeArea only works within the layout tree. The hosting
// controller's view is still black. This UIView sets the window/VC background
// as soon as it attaches, and honors the active theme variant.
//
final class _BrandWindowFixer: UIView {
    private static let brandUIColor = UIColor { traits in
        let isDark = traits.userInterfaceStyle == .dark
        switch ThemeVariant.current {
        case .classic:
            return isDark
                ? UIColor(red: 0.07, green: 0.04, blue: 0.15, alpha: 1.0)
                : UIColor(red: 0.98, green: 0.96, blue: 0.99, alpha: 1.0)
        case .coupleSync:
            return isDark
                ? UIColor(red: 0.12, green: 0.09, blue: 0.07, alpha: 1.0)
                : UIColor(red: 0.96, green: 0.94, blue: 0.91, alpha: 1.0)
        }
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

// MARK: - App Theming (tab bar / global UIKit appearance)

enum AppTheming {

    /// Configures UITabBarAppearance from the current theme variant. Call at
    /// launch and again whenever the variant changes.
    static func configureTabBar() {
        let brandBg = UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            switch ThemeVariant.current {
            case .classic:
                return isDark
                    ? UIColor(red: 0.07, green: 0.04, blue: 0.15, alpha: 0.97)
                    : UIColor(red: 1.00, green: 0.98, blue: 0.99, alpha: 0.97)
            case .coupleSync:
                return isDark
                    ? UIColor(red: 0.14, green: 0.10, blue: 0.08, alpha: 0.97)
                    : UIColor(red: 0.96, green: 0.94, blue: 0.91, alpha: 0.97)
            }
        }

        let accent = UIColor { _ in
            switch ThemeVariant.current {
            case .classic:    return UIColor(red: 1.00, green: 0.38, blue: 0.60, alpha: 1.0)
            case .coupleSync: return UIColor(red: 0.78, green: 0.52, blue: 0.46, alpha: 1.0)
            }
        }

        let inactive = UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            switch ThemeVariant.current {
            case .classic:
                return isDark
                    ? UIColor.white.withAlphaComponent(0.38)
                    : UIColor.black.withAlphaComponent(0.42)
            case .coupleSync:
                return isDark
                    ? UIColor(red: 0.52, green: 0.47, blue: 0.42, alpha: 1.0)
                    : UIColor(red: 0.60, green: 0.55, blue: 0.50, alpha: 1.0)
            }
        }

        let a = UITabBarAppearance()
        a.configureWithOpaqueBackground()
        a.backgroundColor = brandBg
        a.stackedLayoutAppearance.normal.iconColor     = inactive
        a.stackedLayoutAppearance.selected.iconColor   = accent
        a.stackedLayoutAppearance.normal.titleTextAttributes   = [.foregroundColor: inactive]
        a.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: accent]

        UITabBar.appearance().standardAppearance   = a
        UITabBar.appearance().scrollEdgeAppearance = a

        // Poke existing tab bars so they pick up the new appearance immediately.
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene else { continue }
            for window in ws.windows {
                applyTabBarAppearance(a, to: window.rootViewController)
            }
        }
    }

    private static func applyTabBarAppearance(_ appearance: UITabBarAppearance,
                                              to vc: UIViewController?) {
        guard let vc else { return }
        if let tabVC = vc as? UITabBarController {
            tabVC.tabBar.standardAppearance = appearance
            tabVC.tabBar.scrollEdgeAppearance = appearance
        }
        if let presented = vc.presentedViewController {
            applyTabBarAppearance(appearance, to: presented)
        }
        for child in vc.children {
            applyTabBarAppearance(appearance, to: child)
        }
    }
}
