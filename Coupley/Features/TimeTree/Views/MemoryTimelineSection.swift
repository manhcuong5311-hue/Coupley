//
//  MemoryTimelineSection.swift
//  Coupley
//
//  Section 3 of the Time Tree screen: the relationship's memory ledger.
//  Capsules float to the top (still-locked memories), then visible
//  memories cascade newest-first.
//
//  A vertical timeline rail runs along the leading edge — small accent
//  nodes anchor each card to it, suggesting the memories are growing
//  off the same trunk as the tree above.
//

import SwiftUI

// MARK: - Timeline Section

struct MemoryTimelineSection: View {

    let lockedCapsules: [TimeMemory]
    let visibleMemories: [TimeMemory]
    let now: Date
    let onAddTapped: () -> Void
    let onSelectMemory: (TimeMemory) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader

            if lockedCapsules.isEmpty && visibleMemories.isEmpty {
                emptyState
            } else {
                timelineList
            }
        }
    }

    // MARK: - Header

    private var sectionHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Memory Timeline")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                Text("The moments your tree was built from.")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
            }

            Spacer()

            Button(action: onAddTapped) {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                    Text("Add")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(Brand.accentGradient)
                )
                .shadow(color: Brand.accentStart.opacity(0.30), radius: 8, y: 3)
            }
            .buttonStyle(BouncyButtonStyle(scale: 0.94))
        }
    }

    // MARK: - Timeline list

    private var timelineList: some View {
        VStack(spacing: 14) {
            // Locked capsules first — they're the most emotionally
            // urgent and we want users to see them immediately.
            ForEach(Array(lockedCapsules.enumerated()), id: \.element.id) { index, memory in
                timelineRow(memory: memory, index: index, isCapsule: true)
            }

            ForEach(Array(visibleMemories.enumerated()), id: \.element.id) { index, memory in
                timelineRow(memory: memory, index: index + lockedCapsules.count, isCapsule: false)
            }
        }
    }

    @ViewBuilder
    private func timelineRow(memory: TimeMemory, index: Int, isCapsule: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Timeline rail node
            VStack(spacing: 0) {
                Circle()
                    .fill(isCapsule
                          ? Color(red: 1.0, green: 0.78, blue: 0.30)
                          : Brand.accentStart)
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle()
                            .strokeBorder(.white.opacity(0.25), lineWidth: 1)
                    )
                    .shadow(
                        color: (isCapsule
                                ? Color(red: 1.0, green: 0.78, blue: 0.30)
                                : Brand.accentStart).opacity(0.35),
                        radius: 5
                    )
                    .padding(.top, 24)
                Rectangle()
                    .fill(Brand.divider)
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 14)

            MemoryCard(
                memory: memory,
                now: now,
                indexInTimeline: index,
                onTap: { onSelectMemory(memory) }
            )
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Brand.accentStart.opacity(0.10))
                    .frame(width: 76, height: 76)
                Image(systemName: "sparkles")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Brand.accentStart.opacity(0.85))
            }

            VStack(spacing: 6) {
                Text("Plant your first memory")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                Text("Every memory you add becomes a star around your tree.\nYour partner sees it instantly.")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            Button(action: onAddTapped) {
                Text("Add a memory")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Brand.accentGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: Brand.accentStart.opacity(0.30), radius: 12, y: 4)
            }
            .buttonStyle(BouncyButtonStyle())
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Brand.surfaceLight)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Brand.divider, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        )
    }
}
