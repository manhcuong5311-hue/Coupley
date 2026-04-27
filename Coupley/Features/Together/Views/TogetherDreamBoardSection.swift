//
//  TogetherDreamBoardSection.swift
//  Coupley
//
//  Section 3 — the Dream Board. The most photo-friendly, visually emotional
//  surface in the app. Two layout modes:
//   • staggered grid (2 columns, varying card heights) — premium
//   • single carousel (one large card visible, others teased) — free
//
//  The premium version is the most "Apple-y" thing in the app: rich color
//  blocks, optional photos, soft motion. The free version intentionally
//  shows just enough to make the user *want* the upgrade.
//

import SwiftUI

// MARK: - Dream Board Section

struct DreamBoardSection: View {

    let dreams: [Dream]
    let isPremium: Bool
    let onSelect: (Dream) -> Void
    let onCreate: () -> Void
    let onShowPaywall: () -> Void

    /// Free users see exactly 1 fully-visible dream. The rest are blurred + locked.
    private let freeFullyVisible = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TogetherSectionTitle(
                "Dream Board",
                subtitle: "The future you're picturing — together."
            ) {
                AnyView(
                    Button(action: handleAdd) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(Brand.accentGradient)
                                    .shadow(color: Brand.accentStart.opacity(0.30), radius: 8, y: 3)
                            )
                    }
                    .buttonStyle(BouncyButtonStyle(scale: 0.92))
                )
            }

            if dreams.isEmpty {
                emptyState
            } else {
                grid
            }
        }
    }

    private func handleAdd() {
        if !isPremium && dreams.count >= freeFullyVisible {
            onShowPaywall()
        } else {
            onCreate()
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        TogetherEmptySlot(
            title: "Start your dream board",
            subtitle: "What do you want your life together to look like?",
            icon: "sparkles",
            onTap: onCreate
        )
    }

    // MARK: - Grid

    private var grid: some View {
        // Two-column staggered grid. Index parity drives the height variance
        // so cards "interlock" rather than line up boringly.
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 12) {
                ForEach(Array(leftColumn.enumerated()), id: \.element.id) { idx, dream in
                    let absoluteIndex = idx * 2
                    DreamCard(
                        dream: dream,
                        height: dreamHeight(at: absoluteIndex),
                        isLocked: !isPremium && absoluteIndex >= freeFullyVisible,
                        onTap: { onSelect(dream) },
                        onLockedTap: onShowPaywall
                    )
                }
            }
            VStack(spacing: 12) {
                ForEach(Array(rightColumn.enumerated()), id: \.element.id) { idx, dream in
                    let absoluteIndex = idx * 2 + 1
                    DreamCard(
                        dream: dream,
                        height: dreamHeight(at: absoluteIndex),
                        isLocked: !isPremium && absoluteIndex >= freeFullyVisible,
                        onTap: { onSelect(dream) },
                        onLockedTap: onShowPaywall
                    )
                }
            }
        }
    }

    private var leftColumn: [Dream] { stride(from: 0, to: dreams.count, by: 2).map { dreams[$0] } }
    private var rightColumn: [Dream] { stride(from: 1, to: dreams.count, by: 2).map { dreams[$0] } }

    /// Heights vary slightly by index so the grid feels designed rather than
    /// generated. Tall cards on left when index%4 in {0, 3}, short otherwise.
    private func dreamHeight(at index: Int) -> CGFloat {
        switch index % 4 {
        case 0: return 220
        case 1: return 180
        case 2: return 180
        default: return 220
        }
    }
}

// MARK: - Dream Card

struct DreamCard: View {

    let dream: Dream
    let height: CGFloat
    let isLocked: Bool
    let onTap: () -> Void
    let onLockedTap: () -> Void

    @State private var didAppear = false

    var body: some View {
        ZStack {
            // Card surface — gradient background or photo when present
            cardSurface

            // Content overlay
            VStack(alignment: .leading, spacing: 0) {
                horizonChip
                    .padding(.top, 14)
                    .padding(.leading, 14)

                Spacer(minLength: 12)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: dream.category.icon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(dream.category.label)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .kerning(0.3)
                    }
                    .foregroundStyle(.white.opacity(0.85))

                    Text(dream.title)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if let inspiration = dream.inspiration {
                        Text(inspiration)
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(2)
                            .padding(.top, 1)
                    }
                }
                .padding(14)
            }

            // Lock layer
            if isLocked {
                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)

                    VStack(spacing: 8) {
                        PremiumBadge(compact: true)
                        Text("Unlock dreams")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Brand.textPrimary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 12)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: dream.colorway.deep.opacity(0.30), radius: 14, y: 6)
        .scaleEffect(didAppear ? 1.0 : 0.95)
        .opacity(didAppear ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) {
                didAppear = true
            }
        }
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            isLocked ? onLockedTap() : onTap()
        }
    }

    // MARK: - Card Surface

    @ViewBuilder
    private var cardSurface: some View {
        ZStack {
            // Always render the gradient as a fallback / base.
            dream.colorway.gradient
                .overlay(
                    // Soft top highlight for depth
                    LinearGradient(
                        colors: [.white.opacity(0.20), .clear],
                        startPoint: .top, endPoint: .center
                    )
                )

            // Photo overlay when present (premium only)
            if let url = dream.photoURL, let parsed = URL(string: url) {
                CachedAsyncImage(url: parsed) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .scaledToFill()
                            .overlay(
                                LinearGradient(
                                    colors: [.black.opacity(0.0), .black.opacity(0.55)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                    }
                }
            }

            // Gradient text legibility wash
            LinearGradient(
                colors: [.clear, .black.opacity(0.40)],
                startPoint: .top, endPoint: .bottom
            )
        }
    }

    // MARK: - Chips

    private var horizonChip: some View {
        Text(dream.horizon.shortLabel)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .kerning(0.4)
            .textCase(.uppercase)
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(.white.opacity(0.20))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.30), lineWidth: 1))
            )
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
