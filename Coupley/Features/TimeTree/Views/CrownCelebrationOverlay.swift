//
//  CrownCelebrationOverlay.swift
//  Coupley
//
//  Full-screen one-time celebration overlay that fires when the couple
//  reaches a crown milestone. Plays once per device per milestone (the
//  parent ViewModel calls `acknowledgeCrown` after dismiss).
//
//  Visual: a large crown inside a slowly turning halo, soft golden
//  particles drifting upward, and the milestone title with its poetic
//  subtitle. Tap outside the words, "Continue Growing", or VoiceOver's
//  escape gesture dismisses it. Backed by a dim of the underlying UI so the
//  moment feels held-out from the rest of the screen.
//
//  Reduce Motion: no turning halo, no particles, and everything fades in
//  instead of springing. VoiceOver: the overlay is modal; the crown, halo
//  and particles are decoration; the title reads as one header ("1 Year
//  together"), then the subtitle, then the button. Text uses JourneyFont,
//  so it grows with Dynamic Type: at accessibility sizes the crown shrinks,
//  and if the words still do not fit, the content scrolls.
//

import SwiftUI
import UIKit

// MARK: - Overlay

struct CrownCelebrationOverlay: View {

    let milestone: CrownMilestone
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The tab's ad banner sits over the bottom of this overlay (it is
    /// drawn inside Journey, not above the tab bar), so the button keeps
    /// clear of it the way the rest of the app does.
    @ObservedObject private var ads = AdsManager.shared
    @State private var hasAppeared = false
    @State private var rotation: Double = 0
    @State private var particles: [Particle] = Particle.seed(count: 22)

    /// At accessibility text sizes the crown gives the words its room.
    private var crownScale: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 0.6 : 1
    }

    var body: some View {
        ZStack {
            // Dim background. Dark enough that the timeline under it can't
            // read through the title and subtitle.
            Color.black.opacity(0.75)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }
                .opacity(hasAppeared ? 1 : 0)
                .accessibilityHidden(true)

            // Particle field
            if !reduceMotion {
                TimelineView(.animation) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    Canvas { ctx, size in
                        drawParticles(ctx: &ctx, size: size, time: t)
                    }
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }

            // Crown + labels: laid out to the full height while they fit,
            // scrolling once large text makes them taller than the screen.
            ViewThatFits(in: .vertical) {
                content(crownScale: crownScale)

                // Short screens (iPhone SE): a smaller crown before scrolling,
                // so "Continue Growing" stays on screen.
                content(crownScale: 0.6)

                ScrollView {
                    content(crownScale: 0.6)
                        .background {
                            // Taps between the words still dismiss, as they
                            // do on the dim background when nothing scrolls.
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { onDismiss() }
                        }
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { onDismiss() }
        .onAppear {
            if reduceMotion {
                withAnimation(.easeInOut(duration: 0.35)) {
                    hasAppeared = true
                }
            } else {
                withAnimation(.spring(response: 0.85, dampingFraction: 0.72)) {
                    hasAppeared = true
                }
                withAnimation(.linear(duration: 22).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            // A custom overlay does not move VoiceOver's focus the way a
            // sheet does; announce the new screen so it lands in here.
            if UIAccessibility.isVoiceOverRunning {
                UIAccessibility.post(notification: .screenChanged, argument: nil)
            }
        }
    }

    // MARK: - Content

    private func content(crownScale: CGFloat) -> some View {
        VStack(spacing: 26) {
            Spacer(minLength: 24)

            crown(scale: crownScale)
                .accessibilityHidden(true)

            VStack(spacing: 10) {
                VStack(spacing: 10) {
                    Text(milestone.localizedTitle)
                        .font(JourneyFont.display)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .shadow(color: .black.opacity(0.30), radius: 12, y: 4)

                    Text("together", comment: "Crown celebration: shown in capitals under a crown title such as '1 Year', so the two lines read '1 Year together'")
                        .font(JourneyFont.label)
                        .foregroundStyle(Color(red: 1.0, green: 0.85, blue: 0.65))
                        .multilineTextAlignment(.center)
                        .textCase(.uppercase)
                        .scriptAwareTracking(2.0)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(milestone.localizedTitle) together",
                                         comment: "VoiceOver header of the crown celebration. %@ is a crown title such as '1 Year' or '100 Days'."))
                .accessibilityAddTraits(.isHeader)

                // Full white, like the title: a translucent white loses
                // contrast on the dim, and the smaller size keeps the order.
                Text(milestone.localizedCelebrationSubtitle)
                    .font(JourneyFont.body)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 36)
                    .padding(.top, 4)
            }
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared || reduceMotion ? 0 : 18)

            Spacer(minLength: 24)

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onDismiss()
            } label: {
                Text("Continue Growing")
                    .font(JourneyFont.title)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 1.0, green: 0.85, blue: 0.45),
                                        Color(red: 0.95, green: 0.55, blue: 0.30)
                                    ],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                            .shadow(color: Color(red: 1.0, green: 0.65, blue: 0.30).opacity(0.40), radius: 18, y: 6)
                    )
            }
            .buttonStyle(BouncyButtonStyle())
            .padding(.horizontal, 24)
            .padding(.bottom, 36 + ads.bannerInset)
            .opacity(hasAppeared ? 1 : 0)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Crown

    /// Decoration only: hidden from VoiceOver by the caller.
    private func crown(scale crownScale: CGFloat) -> some View {
        ZStack {
            // Outer halo, turning slowly unless Reduce Motion is on.
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.85, blue: 0.45),
                            Color(red: 0.95, green: 0.55, blue: 0.30)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
                .frame(width: 220 * crownScale, height: 220 * crownScale)
                .opacity(0.45)
                .rotationEffect(.degrees(rotation))

            Circle()
                .strokeBorder(
                    FutureLetterStyle.gold.opacity(0.35),
                    lineWidth: 0.8
                )
                .frame(width: 280 * crownScale, height: 280 * crownScale)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 1.0, green: 0.85, blue: 0.45).opacity(0.35),
                            Color(red: 1.0, green: 0.85, blue: 0.45).opacity(0.0)
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 160 * crownScale
                    )
                )
                .frame(width: 320 * crownScale, height: 320 * crownScale)
                .blur(radius: 14)

            Image(systemName: "crown.fill")
                .font(.system(size: 90 * crownScale, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.92, blue: 0.55),
                            Color(red: 0.95, green: 0.55, blue: 0.30)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: Color(red: 1.0, green: 0.65, blue: 0.30).opacity(0.55), radius: 22, y: 4)
                .scaleEffect(hasAppeared || reduceMotion ? 1.0 : 0.55)
        }
        // Under Reduce Motion the crown fades in rather than growing.
        .opacity(reduceMotion && !hasAppeared ? 0 : 1)
    }

    // MARK: - Particles

    private func drawParticles(ctx: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        for p in particles {
            let dt = time - p.birth
            // Looping vertical drift over a 6s cycle
            let cycle = (dt.truncatingRemainder(dividingBy: 6.0)) / 6.0
            let yOffset = CGFloat(1 - cycle) * size.height * 1.1
            let x = p.x * size.width + sin(dt * p.swayFreq) * 14
            let y = size.height + 20 - yOffset
            let alpha = (1 - cycle) * 0.65

            let dotSize: CGFloat = p.size
            let glowSize = dotSize * 4
            let glow = Path(ellipseIn: CGRect(
                x: x - glowSize / 2, y: y - glowSize / 2,
                width: glowSize, height: glowSize
            ))
            ctx.fill(glow, with: .color(Color(red: 1.0, green: 0.85, blue: 0.45).opacity(alpha * 0.30)))

            let dot = Path(ellipseIn: CGRect(
                x: x - dotSize / 2, y: y - dotSize / 2,
                width: dotSize, height: dotSize
            ))
            ctx.fill(dot, with: .color(Color(red: 1.0, green: 0.92, blue: 0.65).opacity(alpha)))
        }
    }
}

// MARK: - Particle

private struct Particle {
    let x: CGFloat              // 0…1, fraction of width
    let size: CGFloat
    let swayFreq: Double
    let birth: TimeInterval

    static func seed(count: Int) -> [Particle] {
        let now = Date().timeIntervalSinceReferenceDate
        return (0..<count).map { i in
            Particle(
                x: CGFloat.random(in: 0...1),
                size: CGFloat.random(in: 1.6...3.6),
                swayFreq: Double.random(in: 0.6...1.4),
                birth: now - Double(i) * 0.25
            )
        }
    }
}

// MARK: - Preview

#Preview("Crown celebration") {
    ZStack {
        Brand.bgGradient.ignoresSafeArea()
        CrownCelebrationOverlay(milestone: CrownMilestone(kind: .years(1)), onDismiss: {})
    }
}
