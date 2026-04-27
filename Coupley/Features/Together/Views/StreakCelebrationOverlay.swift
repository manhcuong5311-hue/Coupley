//
//  StreakCelebrationOverlay.swift
//  Coupley
//
//  Full-screen celebration moment fired when a couple crosses a 7-day
//  streak boundary on a challenge. Modeled on TimeTreeView's CrownCelebrationOverlay
//  in spirit — a *feeling*, not a notification — so closing it feels like
//  receiving a small gift rather than dismissing a modal.
//

import SwiftUI

struct StreakCelebrationOverlay: View {
    let challenge: CoupleChallenge
    let onDismiss: () -> Void

    @State private var didAppear = false
    @State private var rotation: Double = -3

    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            // Confetti dots
            ForEach(0..<24, id: \.self) { i in
                ConfettiDot(seed: i, colorway: challenge.colorway)
            }

            VStack(spacing: 18) {
                // Crown / flame medallion
                ZStack {
                    Circle()
                        .fill(challenge.colorway.gradient)
                        .frame(width: 130, height: 130)
                        .shadow(color: challenge.colorway.primary.opacity(0.5),
                                radius: 22, y: 8)

                    Circle()
                        .stroke(.white.opacity(0.25), lineWidth: 6)
                        .frame(width: 130, height: 130)

                    Image(systemName: "flame.fill")
                        .font(.system(size: 56, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
                        .rotationEffect(.degrees(rotation))
                }

                VStack(spacing: 10) {
                    Text("\(challenge.streak.current)-day streak ✨")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(challenge.title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))

                    Text("You did the rare thing — together. Don't let it stop here.")
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.78))
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .padding(.horizontal, 36)
                        .padding(.top, 4)
                }

                Button(action: onDismiss) {
                    Text("Keep going")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 14)
                        .background(
                            Capsule()
                                .fill(challenge.colorway.gradient)
                                .shadow(color: challenge.colorway.primary.opacity(0.45), radius: 14, y: 5)
                        )
                }
                .buttonStyle(BouncyButtonStyle())
                .padding(.top, 6)
            }
            .scaleEffect(didAppear ? 1 : 0.85)
            .opacity(didAppear ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) {
                didAppear = true
            }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                rotation = 3
            }
        }
    }
}

// MARK: - Confetti Dot

private struct ConfettiDot: View {
    let seed: Int
    let colorway: TogetherColorway

    @State private var animate = false

    private var size: CGFloat {
        let base: CGFloat = 6
        let variance = CGFloat((seed * 13) % 7)
        return base + variance
    }

    private var x: CGFloat {
        let bounds = UIScreen.main.bounds.width
        let spread = (CGFloat((seed * 37) % 200) - 100) / 100.0
        return spread * bounds * 0.45
    }

    private var initialY: CGFloat { -350 + CGFloat((seed * 23) % 80) }
    private var endY: CGFloat { 350 + CGFloat((seed * 19) % 100) }

    private var color: Color {
        switch seed % 4 {
        case 0: return colorway.primary
        case 1: return colorway.deep
        case 2: return .white
        default: return colorway.primary.opacity(0.8)
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .offset(x: x, y: animate ? endY : initialY)
            .opacity(animate ? 0 : 1)
            .onAppear {
                let delay = Double(seed % 8) * 0.06
                withAnimation(.easeOut(duration: 1.6).delay(delay)) {
                    animate = true
                }
            }
    }
}
