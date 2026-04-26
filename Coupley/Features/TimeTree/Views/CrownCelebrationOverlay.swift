//
//  CrownCelebrationOverlay.swift
//  Coupley
//
//  Full-screen one-time celebration overlay that fires when the couple
//  reaches a crown milestone. Plays once per device per milestone (the
//  parent ViewModel calls `acknowledgeCrown` after dismiss).
//
//  Visual: a large rotating crown halo, soft golden particles drifting
//  upward, and the milestone title with its poetic subtitle. Tap to
//  dismiss. Backed by a heavy blur of the underlying UI so the moment
//  feels held-out from the rest of the screen.
//

import SwiftUI

// MARK: - Overlay

struct CrownCelebrationOverlay: View {

    let milestone: CrownMilestone
    let onDismiss: () -> Void

    @State private var hasAppeared = false
    @State private var rotation: Double = 0
    @State private var particles: [Particle] = Particle.seed(count: 22)

    var body: some View {
        ZStack {
            // Dim background
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }
                .opacity(hasAppeared ? 1 : 0)

            // Particle field
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                Canvas { ctx, size in
                    drawParticles(ctx: &ctx, size: size, time: t)
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // Crown + labels
            VStack(spacing: 26) {
                Spacer()

                ZStack {
                    // Outer halo
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
                        .frame(width: 220, height: 220)
                        .opacity(0.45)
                        .rotationEffect(.degrees(rotation))

                    Circle()
                        .strokeBorder(
                            Color(red: 1.0, green: 0.78, blue: 0.30).opacity(0.35),
                            lineWidth: 0.8
                        )
                        .frame(width: 280, height: 280)

                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.85, blue: 0.45).opacity(0.35),
                                    Color(red: 1.0, green: 0.85, blue: 0.45).opacity(0.0)
                                ],
                                center: .center,
                                startRadius: 10,
                                endRadius: 160
                            )
                        )
                        .frame(width: 320, height: 320)
                        .blur(radius: 14)

                    Image(systemName: "crown.fill")
                        .font(.system(size: 90, weight: .semibold))
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
                        .scaleEffect(hasAppeared ? 1.0 : 0.55)
                }

                VStack(spacing: 10) {
                    Text(milestone.displayTitle)
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.30), radius: 12, y: 4)

                    Text("together")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(red: 1.0, green: 0.85, blue: 0.65))
                        .textCase(.uppercase)
                        .tracking(2.0)

                    Text(milestone.celebrationSubtitle)
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.88))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)
                        .lineSpacing(3)
                        .padding(.top, 4)
                }
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 18)

                Spacer()

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onDismiss()
                } label: {
                    Text("Continue Growing")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
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
                .padding(.bottom, 36)
                .opacity(hasAppeared ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.85, dampingFraction: 0.72)) {
                hasAppeared = true
            }
            withAnimation(.linear(duration: 22).repeatForever(autoreverses: false)) {
                rotation = 360
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
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
