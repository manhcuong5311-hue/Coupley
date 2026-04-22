//
//  NudgePopupView.swift
//  Coupley
//
//  Full-screen dimmed popup shown when a partner sends a Thinking-of-You
//  ping or a mood reaction (Love / Hug / Call me / Coffee).
//  Triggered from ContentView so it appears on every tab.
//

import SwiftUI

struct NudgePopupView: View {

    let nudge: Nudge
    let partnerName: String
    let partnerAvatar: AvatarOption
    let onDismiss: () -> Void

    // Pulse animation for the emoji ring
    @State private var pulse = false

    var body: some View {
        ZStack {
            // Dim background — tap anywhere to dismiss
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            card
                .padding(.horizontal, 32)
        }
    }

    // MARK: - Card

    private var card: some View {
        VStack(spacing: 0) {

            // ── Avatar + emoji ring ──────────────────────────────────
            ZStack {
                Circle()
                    .fill(Brand.accentStart.opacity(pulse ? 0.18 : 0.10))
                    .frame(width: 110, height: 110)
                    .scaleEffect(pulse ? 1.12 : 1.0)
                    .animation(
                        .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                        value: pulse
                    )

                Circle()
                    .fill(Brand.surfaceLight)
                    .frame(width: 90, height: 90)
                    .overlay(
                        partnerAvatar.image()
                            .frame(width: 90, height: 90)
                            .clipShape(Circle())
                    )
                    .overlay(Circle().strokeBorder(Brand.divider, lineWidth: 1.5))

                // Emoji badge at bottom-right of avatar
                Text(nudge.displayEmoji)
                    .font(.system(size: 26))
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(Brand.backgroundTop)
                            .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
                    )
                    .offset(x: 28, y: 28)
            }
            .padding(.top, 36)
            .onAppear { pulse = true }

            // ── Partner name + message ───────────────────────────────
            VStack(spacing: 6) {
                Text(partnerName)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)

                Text(nudge.displayLabel)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 28)
            .padding(.horizontal, 20)

            // ── Dismiss button ───────────────────────────────────────
            Button(action: onDismiss) {
                Text("Got it  \(nudge.displayEmoji)")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Brand.accentGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(BouncyButtonStyle())
            .padding(.top, 28)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(Brand.backgroundTop)
                .shadow(color: .black.opacity(0.28), radius: 32, y: 8)
        )
    }
}
