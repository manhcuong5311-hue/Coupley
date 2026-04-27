//
//  TogetherComponents.swift
//  Coupley
//
//  The premium design primitives the Together tab is built out of. These are
//  intentionally NOT promoted into Brand/Core — they're tuned for the
//  emotional, photo-friendly, glass-card visual register this tab needs.
//  The rest of the app keeps its existing components.
//

import SwiftUI

// MARK: - Section Title

struct TogetherSectionTitle: View {
    let title: String
    let subtitle: String?
    var trailing: AnyView?

    init(_ title: String, subtitle: String? = nil, trailing: (() -> AnyView)? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing?()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)
                }
            }
            Spacer()
            if let trailing {
                trailing
            }
        }
    }
}

// MARK: - Premium Card

/// The base card used throughout Together. Subtle background, soft border,
/// and a layered shadow for depth. Cards composed on top of this opt into
/// their own colorway treatment via `tint`.
struct TogetherCard<Content: View>: View {
    var tint: TogetherColorway?
    var padding: CGFloat = 18
    var cornerRadius: CGFloat = 24
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Brand.surfaceLight)

                    if let tint {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        tint.primary.opacity(0.10),
                                        tint.deep.opacity(0.02)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                (tint?.primary ?? Brand.accentStart).opacity(0.30),
                                Brand.divider.opacity(0.40)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: (tint?.primary ?? Brand.accentStart).opacity(0.10),
                    radius: 18, y: 8)
            .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }
}

// MARK: - Glass Tile (for hero metrics)

struct TogetherGlassTile<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                    )
            )
    }
}

// MARK: - Premium Progress Bar

/// A premium-feeling progress bar. The fill is a colorway gradient and the
/// trough is a subtle inset. Two-stop highlight at the leading edge gives
/// the illusion of an embossed surface.
struct TogetherProgressBar: View {
    let progress: Double  // 0...1
    let colorway: TogetherColorway
    var height: CGFloat = 10
    var showsHighlight: Bool = true

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Brand.surfaceMid.opacity(0.7))
                    .overlay(
                        Capsule()
                            .strokeBorder(Brand.divider.opacity(0.6), lineWidth: 0.5)
                    )

                Capsule()
                    .fill(colorway.gradient)
                    .frame(width: max(8, geo.size.width * CGFloat(min(1, max(0, progress)))))
                    .overlay {
                        if showsHighlight {
                            Capsule()
                                .stroke(.white.opacity(0.35), lineWidth: 0.7)
                                .padding(0.5)
                                .blendMode(.overlay)
                        }
                    }
                    .shadow(color: colorway.primary.opacity(0.45), radius: 6, y: 2)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Streak Pill

struct StreakPill: View {
    let streak: Int
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "flame.fill")
                .font(.system(size: 11, weight: .semibold))
            Text("\(streak)d")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.30))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(Color(red: 1.0, green: 0.55, blue: 0.30).opacity(0.14))
        )
    }
}

// MARK: - Premium Lock Badge

/// Sits on locked premium content. Differs from a plain `lock.fill` icon by
/// having a gold gradient and a soft glow — the visual cue that this isn't
/// a feature you can't use, it's a feature you can buy.
struct PremiumBadge: View {
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "crown.fill")
                .font(.system(size: compact ? 9 : 11, weight: .semibold))
            if !compact {
                Text("Premium")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .kerning(0.3)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, compact ? 7 : 9)
        .padding(.vertical, compact ? 4 : 5)
        .background(
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1.00, green: 0.78, blue: 0.30),
                            Color(red: 0.92, green: 0.50, blue: 0.18)
                        ],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .shadow(color: Color(red: 1.0, green: 0.68, blue: 0.20).opacity(0.45),
                        radius: 6, y: 2)
        )
    }
}

// MARK: - Premium Lock Overlay

/// Frosted overlay that locks a card. Shimmer animates so locked cards feel
/// premium-coded rather than disabled.
struct PremiumLockOverlay: View {
    let title: String
    let subtitle: String
    let onTap: () -> Void

    @State private var shimmerPhase: CGFloat = -1

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onTap()
        }) {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)

                LinearGradient(
                    colors: [.clear, .white.opacity(0.18), .clear],
                    startPoint: .leading, endPoint: .trailing
                )
                .mask(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .scaleEffect(x: 2, y: 1, anchor: .leading)
                .offset(x: shimmerPhase * 220)

                VStack(spacing: 12) {
                    PremiumBadge()
                    Text(title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                        .multilineTextAlignment(.center)
                    Text(subtitle)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .padding(.horizontal, 24)
                }
                .padding(.vertical, 24)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(BouncyButtonStyle(scale: 0.985))
        .onAppear {
            withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) {
                shimmerPhase = 1.6
            }
        }
    }
}

// MARK: - Hero Background

/// The signature gradient panel used by the Today Together hero. Tuned to
/// look luxurious on both light and dark themes by mixing the active
/// accent gradient with a soft photo-style glow.
struct TogetherHeroBackground: View {
    var colorway: TogetherColorway = .blossom

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(colorway.gradient)

            // Top-left highlight blob
            Circle()
                .fill(.white.opacity(0.20))
                .frame(width: 220, height: 220)
                .blur(radius: 60)
                .offset(x: -80, y: -90)

            // Bottom-right deepening blob
            Circle()
                .fill(colorway.deep.opacity(0.55))
                .frame(width: 280, height: 280)
                .blur(radius: 70)
                .offset(x: 100, y: 110)

            // Subtle grain to keep it from feeling like a flat asset
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(.white.opacity(0.04))
                .blendMode(.overlay)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: colorway.deep.opacity(0.45), radius: 24, y: 12)
    }
}

// MARK: - Pressable Container

/// A button-style container for cards. Adds soft scale + opacity press state
/// without a `Button` wrapper (avoids stealing inner button taps).
struct PressableContainer<Content: View>: View {
    var onTap: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var isPressed = false

    var body: some View {
        content()
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isPressed)
            .contentShape(Rectangle())
            .onTapGesture {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onTap()
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { _ in isPressed = false }
            )
    }
}

// MARK: - Empty Slot Card

/// The "tap to add" placeholder card. Dashed border, low contrast, just
/// enough affordance to read as interactive without competing with real
/// goals on the page.
struct TogetherEmptySlot: View {
    let title: String
    let subtitle: String
    var icon: String = "plus"
    let onTap: () -> Void

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTap()
        }) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Brand.accentStart.opacity(0.10))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Brand.accentStart)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Brand.textTertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Brand.surfaceLight.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(
                                style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                            )
                            .foregroundStyle(Brand.divider)
                    )
            )
        }
        .buttonStyle(BouncyButtonStyle(scale: 0.98))
    }
}

// MARK: - Inline Avatar Pair

/// Two small overlapping circles representing the couple. Used wherever we
/// want to telegraph "this is a shared thing" without spelling it out.
struct CouplePairAvatar: View {
    var size: CGFloat = 22
    var leading: Color = Color(red: 1.0, green: 0.55, blue: 0.55)
    var trailing: Color = Color(red: 0.55, green: 0.78, blue: 0.85)

    var body: some View {
        HStack(spacing: -6) {
            Circle()
                .fill(leading)
                .frame(width: size, height: size)
                .overlay(Circle().strokeBorder(.white.opacity(0.4), lineWidth: 1))
            Circle()
                .fill(trailing)
                .frame(width: size, height: size)
                .overlay(Circle().strokeBorder(.white.opacity(0.4), lineWidth: 1))
        }
    }
}
