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

    /// Only the hero card is allowed a larger radius than the card tier.
    static var heroCornerRadius:   CGFloat { cardCornerRadius + 6 }

    /// coupleSync is the soft/continuous shape language; classic is circular.
    static var cornerStyle: RoundedCornerStyle {
        ThemeVariant.current.usesSolidPrimary ? .continuous : .circular
    }

    /// Vertical rhythm. A uniform `VStack(spacing: 20)` is a metronome: it
    /// cannot encode grouping, so nine cards read as nine peers. 40:14 is
    /// ~2.9x, past the proximity threshold, so the stack chunks into zones
    /// before a single glyph is parsed.
    enum Space {
        static let sibling: CGFloat = 14
        static let zone:    CGFloat = 40
        static let gutter:  CGFloat = 20
        /// The hero bleeds 8pt wider per side than every sibling. A 16pt break
        /// in the screen's single vertical edge is visible in a screenshot;
        /// 6pt of extra corner radius is not.
        static let heroGutter: CGFloat = 12
    }
}

// MARK: - Type Scale

/// Six rungs with nothing in the gaps, replacing the 22/18/17/16/15/14/13/12/11
/// mush that made every line on Home read at the same volume.
/// `Font.system` never touches `Palette`, so these are safe as `static let` and
/// cannot resolve wrongly in any ThemeVariant × appearance combination.
enum BrandType {
    /// Masthead. The screen's ceiling was 22pt; this is a 1.55x jump.
    static let display = Font.system(size: 34, weight: .bold,     design: .rounded)
    /// The one hero card's title. 1.6x over `title`, with nothing between.
    static let hero    = Font.system(size: 24, weight: .bold,     design: .rounded)
    static let title   = Font.system(size: 17, weight: .semibold, design: .rounded)
    static let label   = Font.system(size: 13, weight: .semibold, design: .rounded)
    static let body    = Font.system(size: 13, weight: .regular,  design: .rounded)
    static let meta    = Font.system(size: 11, weight: .medium,   design: .rounded)
    static let cta     = Font.system(size: 17, weight: .semibold, design: .rounded)
}

/// The screen's uppercase tracked label.
///
/// Home used to carry six of these, identically styled, so the small-caps
/// signal carried no information at all. Keep them scarce: when the eye catches
/// tracked small caps it should already know what it has found.
struct Eyebrow: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(BrandType.label)
            .foregroundStyle(Brand.textSecondary)
            .textCase(.uppercase)
            .tracking(1.2)
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

// MARK: - Surface Tiers

/// Four levels of surface, so a block's importance is readable from its
/// container alone, before any text is parsed.
///
/// The old screen had exactly one level — every block was
/// `RoundedRectangle(22).fill(surfaceLight)` — and contrast is a ratio, so a
/// screen of fourteen identical slabs cannot make any of them look important.
/// The fix is as much about *removing* containers (`.quiet`) and *recessing*
/// them (`.chip`) as about lifting one (`.hero`).
///
/// # The rules, so the next screen does not re-litigate them
///
/// 1. `.hero` — one per render, resolved by a state enum, rendered at
///    `Brand.Space.sibling` directly under the masthead, slot collapses when
///    the resolver returns none. A component may VETO the resolver: a
///    finished, empty, loading, locked or error state is never hero even if
///    the resolver picked it. A job belongs to exactly one tab's hero.
/// 2. `.card` — content with something still to do. When the thing is done,
///    the tier drops. Tier is a function of state, not of type.
/// 3. `.chip` — navigation, shortcuts, and nested wells. Always carries its
///    1pt divider: the fill is only a real step on the dark palettes. Never a
///    decorative ornament — an ornament gets no container at all.
/// 4. `.quiet` — ambient readouts. ONE ruled block per zone; every other
///    quiet row passes `showsRule: false`.
/// 5. `innerFill` is never used bare — always through `.wellBackground(in:)`,
///    because the fill inverts in both Light variants.
/// 6. One filled accent per screen, enforced structurally by `BrandCTA`:
///    filled at hero, outlined everywhere else. Never hand-counted.
/// 7. `Eyebrow` — one per screen, in the masthead, on the page. Never on the
///    hero wash, where it measures 3.1–3.8:1 in all four resolutions.
enum SurfaceTier {
    /// Exactly one per render: today's job. The only accent-washed object.
    case hero
    /// Content with a container.
    case card
    /// Navigation and shortcuts, and *nested* recessed wells. Never a
    /// decorative ornament — that is no container at all.
    case chip
    /// No container at all, just a rule. Ambient readouts live here.
    case quiet

    var radius: CGFloat {
        switch self {
        case .hero:  return Brand.heroCornerRadius
        case .card:  return Brand.cardCornerRadius
        case .chip:  return 14
        case .quiet: return 0
        }
    }

    var fill: Color? {
        switch self {
        case .hero:  return Brand.surfaceMid
        case .card:  return Brand.surfaceLight
        // backgroundTop is already this app's recessed semantic (stats chip,
        // photo thumbnails, micro-action wells). In the shipping coupleSync
        // dark palette it sits ~ΔL*10 under surfaceLight — a bigger step than
        // the one that lifts the hero.
        case .chip:  return Brand.backgroundTop
        case .quiet: return nil
        }
    }

    /// A nested panel is always a recessed well, never the same colour as the
    /// card holding it. The mood note box used to fill `surfaceLight` on a
    /// `surfaceLight` card — a 1pt outline around nothing.
    ///
    /// Never use this bare — go through `View.wellBackground(in:)`. Measured
    /// against the real palette, `backgroundTop` is the step it claims to be
    /// only on the two dark resolutions:
    ///
    ///     well vs .card    syncDark −9.2   syncLight +5.1
    ///     well vs .hero    syncDark −13.0  syncLight +8.6
    ///
    /// In both Light variants `backgroundTop` is the *lightest* surface token
    /// in the palette, so a bare fill renders a raised panel — the opposite of
    /// a well. `wellBackground` adds the divider edge that reads in all four.
    var innerFill: Color {
        switch self {
        case .hero, .card:  return Brand.backgroundTop
        case .chip, .quiet: return Brand.surfaceLight
        }
    }

    var padding: CGFloat {
        switch self {
        case .hero:  return 22
        case .card:  return 16
        case .chip:  return 12
        case .quiet: return 0
        }
    }

    /// Keeps the hero from being out-massed by a taller sibling when it lands
    /// on a short card. Visual mass beats type size in a squint test.
    var minHeight: CGFloat? { self == .hero ? 160 : nil }

    /// Horizontal gutter. The hero's is narrower, so it bleeds 8pt wider per
    /// side and breaks the screen's single vertical edge.
    var gutter: CGFloat { self == .hero ? Brand.Space.heroGutter : Brand.Space.gutter }
}

// MARK: - Tier Container

/// Applies a tier's container to any view. Use this to retrofit a card that
/// already builds its own content; use `BrandCard` when you are writing the
/// content inline.
struct TierContainer: ViewModifier {
    var tier: SurfaceTier = .card
    /// Tints the hero wash and border. Ignored by every other tier.
    var accent: Color? = nil
    /// `.quiet` only. The rule marks a ZONE, so exactly one block per zone
    /// draws it and every other quiet row passes `false`. Seven stacked
    /// hairlines stop meaning "new zone" and start meaning nothing.
    /// It also carries its own 16pt, so a zone spacer in front of a ruled
    /// block must be budgeted as `Brand.Space.zone - 16`.
    var showsRule: Bool = true

    private var tint: Color { accent ?? Brand.accentStart }

    func body(content: Content) -> some View {
        if tier == .quiet {
            // A gap cannot group edgeless text — proximity needs edges. One
            // hairline per zone gives the 40pt boundaries something to bound,
            // and costs exactly 1pt of height.
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, showsRule ? 16 : 0)
                .overlay(alignment: .top) {
                    if showsRule {
                        Rectangle().fill(Brand.divider).frame(height: 1)
                    }
                }
        } else {
            content
                .padding(tier.padding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: tier.minHeight, alignment: .topLeading)
                .background(filledBackground)
        }
    }

    @ViewBuilder
    private var filledBackground: some View {
        let shape = RoundedRectangle(cornerRadius: tier.radius, style: Brand.cornerStyle)
        ZStack {
            if let fill = tier.fill { shape.fill(fill) }

            if tier == .hero {
                // A vertical ramp, not a diagonal: a diagonal decays to ~0.03
                // opacity by the card's own centre, so the tint would be gone
                // exactly where the title sits. Built from `accent` directly
                // and never from `Brand.accentGradient`, which collapses to
                // flat whenever `usesSolidPrimary` is true — the shipping
                // default.
                shape.fill(
                    LinearGradient(
                        colors: [tint.opacity(0.26), tint.opacity(0.06)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            }

            // Every filled tier carries an edge, the chip included.
            //
            // The chip's fill is `backgroundTop`, which is ALSO the first stop
            // of `Brand.bgGradient` — so a chip sitting on the page is the
            // exact colour of the page behind it (ΔL* 0.0 at the top of the
            // scroll, drifting to only ~4 at the bottom). The ~ΔL*10 step the
            // chip is named for exists only when it is nested inside a card.
            // Without this border the quiet tier's hairline (±19.8 against the
            // page) out-reads the chip, inverting the ladder's bottom two
            // rungs — which is what Home shipped.
            shape.strokeBorder(
                tier == .hero ? tint.opacity(0.45) : Brand.divider,
                lineWidth: tier == .hero ? 1.5 : 1
            )
        }
        // Near-invisible on the dark palettes — the background's own relative
        // luminance is ~0.009, so a shadow has almost nothing left to subtract
        // — but in the two Light variants the shadow *is* the card's edge.
        .shadow(color: .black.opacity(tier == .hero ? 0.16 : 0.10),
                radius: tier == .hero ? 20 : 12,
                y: tier == .hero ? 8 : 3)
    }
}

// MARK: - Brand Card

/// The one container primitive. Both parameters are defaulted, so an existing
/// call site keeps compiling untouched.
struct BrandCard<Content: View>: View {
    var tier: SurfaceTier = .card
    var accent: Color? = nil
    /// `.quiet` only — one ruled block per zone. See `TierContainer`.
    var showsRule: Bool = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        content().modifier(TierContainer(tier: tier, accent: accent, showsRule: showsRule))
    }
}

// MARK: - Recessed Well

extension View {
    /// A recessed panel nested inside a tier.
    ///
    /// The fill alone is not enough: `innerFill` is `backgroundTop`, which is
    /// the *lightest* surface token in both Light variants, so filling a well
    /// with it renders a raised panel there instead of a sunken one. The 1pt
    /// divider is what makes the well read in all four ThemeVariant ×
    /// appearance resolutions — it measures +19.8 ΔL* on syncDark and −12.3 on
    /// syncLight, supra-threshold in both directions.
    func wellBackground(in parent: SurfaceTier = .card,
                        radius: CGFloat = 14) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: Brand.cornerStyle)
        return background(shape.fill(parent.innerFill))
            .overlay(shape.strokeBorder(Brand.divider, lineWidth: 1))
    }
}

// MARK: - Brand CTA

/// The one call-to-action primitive.
///
/// Filled at hero tier, outlined everywhere else. Routing every CTA through
/// this makes "one filled accent per screen" structural rather than something
/// each screen has to count by hand — the fill is a function of the tier, so
/// a demoted card cannot keep a saturated button by accident.
struct BrandCTA: View {
    let title: String
    var icon: String? = nil
    var tier: SurfaceTier = .card
    var accent: Color? = nil
    var isEnabled: Bool = true
    var isBusy: Bool = false
    let action: () -> Void

    private var tint: Color { accent ?? Brand.accentStart }
    private var isFilled: Bool { tier == .hero }

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        } label: {
            HStack(spacing: 7) {
                if isBusy {
                    ProgressView()
                        .tint(isFilled ? .white : tint)
                        .controlSize(.small)
                } else if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(title).font(BrandType.cta)
            }
            .foregroundStyle(isFilled ? Color.white : tint)
            .frame(maxWidth: .infinity)
            .frame(height: isFilled ? 52 : 44)
            .background(background)
        }
        .buttonStyle(BouncyButtonStyle())
        .disabled(!isEnabled || isBusy)
    }

    @ViewBuilder
    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: Brand.buttonCornerRadius,
                                     style: Brand.cornerStyle)
        if isFilled {
            // `accentStart.opacity(0.35)` is the app's existing disabled idiom
            // (see PrimaryButton) — a dimmed accent, not a dead neutral, so the
            // control still reads as a button while it waits.
            shape.fill(tint.opacity(isEnabled ? 1.0 : 0.35))
        } else {
            shape.fill(Brand.surfaceLight)
                .overlay(shape.strokeBorder(tint.opacity(isEnabled ? 0.45 : 0.18),
                                            lineWidth: 1))
        }
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
