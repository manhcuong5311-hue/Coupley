//
//  TogetherNowCard.swift
//  Coupley
//
//  Shown only while both partners have the app open at the same time.
//
//  The app already knew this — `CoupleViewModel.partnerIsOnline` has been
//  published all along — but it spent that knowledge on a coloured dot in a
//  status row that looks almost identical whether anyone is there or not.
//  Two people opening the app in the same minute is rare and worth marking.
//
//  Tapping a reaction sends a nudge, which the partner's `NudgeViewModel` is
//  already listening for and renders as a popup. Because they are on screen
//  right now, it lands as something closer to a live gesture than a push.
//

import SwiftUI

struct TogetherNowCard: View {

    let partnerName: String
    /// nil until the user picks one; drives the sent confirmation.
    let sentReaction: ReactionKind?
    let onSend: (ReactionKind) -> Void
    let onTouchTogether: () -> Void
    var tier: SurfaceTier = .card

    private var isHero: Bool { tier == .hero }

    @State private var pulsing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let sentReaction {
                sentState(sentReaction)
            } else {
                reactionRow
            }

            Button(action: onTouchTogether) {
                HStack(spacing: 7) {
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Touch together")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: Brand.buttonCornerRadius)
                        .fill(Brand.accentGradient)
                )
            }
            .buttonStyle(BouncyButtonStyle())
        }
        .modifier(TierContainer(tier: tier, accent: liveGreen))
        .onAppear { pulsing = true }
    }

    private var liveGreen: Color { Color(red: 0.25, green: 0.85, blue: 0.55) }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(liveGreen.opacity(0.25))
                    .frame(width: 26, height: 26)
                    .scaleEffect(pulsing ? 1.35 : 0.9)
                    .opacity(pulsing ? 0 : 0.9)
                    .animation(
                        .easeOut(duration: 1.6).repeatForever(autoreverses: false),
                        value: pulsing
                    )
                Circle()
                    .fill(liveGreen)
                    .frame(width: 10, height: 10)
            }
            .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 1) {
                Text("You're both here")
                    .font(isHero ? BrandType.hero : BrandType.title)
                    .foregroundStyle(Brand.textPrimary)
                Text("\(partnerName) has Coupley open right now")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Reactions

    private var reactionRow: some View {
        HStack(spacing: 10) {
            ForEach(ReactionKind.allCases) { kind in
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onSend(kind)
                } label: {
                    VStack(spacing: 3) {
                        Text(kind.emoji).font(.system(size: 20))
                        Text(kind.shortLabel)
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(Brand.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Brand.backgroundTop)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(Brand.divider, lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(BouncyButtonStyle(scale: 0.93))
            }
        }
    }

    private func sentState(_ kind: ReactionKind) -> some View {
        HStack(spacing: 8) {
            Text(kind.emoji).font(.system(size: 20))
            Text("Sent — \(partnerName) should see it now")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Brand.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14).fill(liveGreen.opacity(0.14))
        )
        .transition(.scale(scale: 0.96).combined(with: .opacity))
    }
}

// MARK: - Short labels

extension ReactionKind {
    /// Two-word-max caption under the emoji. The existing `label` is written
    /// for notification copy and is too long for a four-across row.
    var shortLabel: String {
        switch self {
        case .heart:  return "Love"
        case .hug:    return "Hug"
        case .callMe: return "Call"
        case .coffee: return "Coffee"
        }
    }
}
