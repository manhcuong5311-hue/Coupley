//
//  JourneyTimelineRows.swift
//  Coupley
//
//  The Timeline's rows other than memory cards, and the rail beside them.
//
//    JourneyTimelineLetterRow    A letter nobody has opened yet, either
//                                direction: the hub's own chip, row content,
//                                press and haptic.
//    JourneyTimelineCapsuleRow   A Memory Capsule that is still sealed, in
//                                the same chip shape as a letter. It replaces
//                                MemoryCard's locked body, its gold border
//                                and its coloured shadow.
//    JourneyTimelineKeepsakeRow  An opened letter, kept among the memories.
//    JourneyTimelineRailRow      One node on the leading rail, then its row.
//
//  Envelopes only: nothing here can show what a letter says, and a sealed
//  capsule shows its title and its day, never its note or photo.
//

import Foundation
import SwiftUI
import UIKit

// MARK: - Rail

/// The leading rail's metrics and its node styles.
enum JourneyTimelineRail {
    static let width: CGFloat = 14
    static let spacing: CGFloat = 12
    /// Where every row's own content starts. Group labels line up with it.
    static let contentInset: CGFloat = width + spacing
    static let nodeSize: CGFloat = 10

    enum Node: Equatable {
        /// A memory, an opened capsule included.
        case memory
        /// An opened letter.
        case keepsake
        /// A hollow ring: a letter or capsule still sealed, or a letter of
        /// yours that has reached its moment and is still unopened.
        case sealed
        /// A letter that has reached its moment and is waiting for you.
        case readyForMe
    }
}

/// A row with its node on the rail. The rail is decoration only: VoiceOver
/// reads the row, which already says what the node shows.
struct JourneyTimelineRailRow<Content: View>: View {
    let node: JourneyTimelineRail.Node
    /// The node's distance from the row's top. Nil centres it on the row,
    /// level with a chip's icon.
    var nodeTop: CGFloat? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(.leading, JourneyTimelineRail.contentInset)
            // A background is proposed exactly the row's size, so the rail is
            // as tall as the row and never taller. As an HStack sibling it
            // was sized on its own: the line could stop short of a tall card
            // and a short chip's row grew to fit the rail.
            .background(alignment: .leading) {
                rail
                    .frame(width: JourneyTimelineRail.width)
                    .accessibilityHidden(true)
            }
    }

    /// The node, then a hairline down to the row's bottom.
    private var rail: some View {
        VStack(spacing: 0) {
            if let nodeTop {
                Color.clear.frame(height: max(0, nodeTop))
            } else {
                Color.clear.frame(maxHeight: .infinity)
            }
            nodeView
                .frame(width: JourneyTimelineRail.nodeSize, height: JourneyTimelineRail.nodeSize)
            Rectangle()
                .fill(Brand.divider)
                .frame(width: 1)
                .frame(maxHeight: .infinity)
        }
    }

    /// Flat fills and one hollow ring: no white strokes, no coloured glow.
    @ViewBuilder
    private var nodeView: some View {
        switch node {
        case .memory:
            Circle().fill(Brand.accentStart)
        case .keepsake:
            Circle().fill(FutureLetterStyle.opened)
        case .readyForMe:
            Circle().fill(FutureLetterStyle.accent)
        case .sealed:
            Circle().strokeBorder(FutureLetterStyle.gold, lineWidth: 2)
        }
    }
}

// MARK: - Unopened letter

/// A letter that has not been opened yet, in either direction. The same chip
/// as the hub's rows; `FutureLetterRowContent` is already one VoiceOver
/// element ("Sealed letter from Sam. Opens Thu, Dec 25 at 9:00 AM. 12 days.")
/// with "Shows the letter." as its hint.
struct JourneyTimelineLetterRow: View {
    let letter: JourneyLetter
    let partnerName: String
    /// The group's TimelineView date, so the countdown moves every minute.
    let now: Date
    let onTap: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTap()
        } label: {
            BrandCard(tier: .chip) {
                FutureLetterRowContent(letter: letter.envelope,
                                       phase: letter.phase,
                                       partnerName: partnerName,
                                       now: now,
                                       isPending: letter.isPending)
            }
        }
        .buttonStyle(BouncyButtonStyle(scale: 0.96))
    }
}

// MARK: - Sealed capsule

/// A Memory Capsule that has not opened yet: sealed until a day, for both of
/// you. Only its title and its day show; tapping opens its detail sheet.
struct JourneyTimelineCapsuleRow: View {
    let memory: TimeMemory
    /// The group's TimelineView date, so the countdown moves every minute.
    let now: Date
    let onTap: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTap()
        } label: {
            BrandCard(tier: .chip) {
                JourneyTimelineChipContent(
                    symbolName: "lock.fill",
                    tint: FutureLetterStyle.gold,
                    title: title,
                    detail: "Capsule · opens \(FutureLetterClock.shortDate(unlockDate, now: now))",
                    trailing: countdown
                )
            }
        }
        .buttonStyle(BouncyButtonStyle(scale: 0.96))
        // "Memory capsule, Our first trip. Opens January 26, 2027, for both
        // of you. 74 days."
        .accessibilityLabel(spokenLabel)
        .accessibilityHint("Shows the capsule.")
    }

    /// Every capsule the Timeline lists as sealed has an unlock date; `now`
    /// only covers a malformed document.
    private var unlockDate: Date { memory.unlockDate ?? now }

    private var title: String {
        let trimmed = memory.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "A moment for you both" : trimmed
    }

    /// "12 days", "5 hr", "42 min", or "Now" in the minute before the view
    /// model moves the capsule into Memories.
    private var countdown: String {
        FutureLetterClock.shortCountdown(to: unlockDate, now: now)
    }

    private var spokenLabel: String {
        let day = unlockDate.formatted(date: .long, time: .omitted)
        return [
            JourneyTimelineSpeech.sentence("Memory capsule, \(title)"),
            "Opens \(day), for both of you.",
            JourneyTimelineSpeech.sentence(countdown)
        ].joined(separator: " ")
    }
}

// MARK: - Keepsake letter

/// An opened letter, among the memories: "Letter from Sam · Opened Nov 13",
/// or "Your letter to Sam · Sam opened it Nov 13". Tapping opens the reader.
struct JourneyTimelineKeepsakeRow: View {
    let letter: JourneyLetter
    let partnerName: String
    let now: Date
    let onTap: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTap()
        } label: {
            BrandCard(tier: .chip) {
                JourneyTimelineChipContent(
                    symbolName: letter.symbolName,
                    tint: letter.tint,
                    title: letter.title(partnerName: partnerName),
                    detail: letter.status(partnerName: partnerName, now: now)
                )
            }
        }
        .buttonStyle(BouncyButtonStyle(scale: 0.96))
        .accessibilityLabel(letter.spokenLabel(partnerName: partnerName, now: now))
        .accessibilityHint("Shows the letter.")
    }
}

// MARK: - Chip content

/// The capsule and keepsake rows' content, laid out like
/// `FutureLetterRowContent` so the three read as one family: a 26pt glyph,
/// title over detail, an optional countdown, a chevron. Unlike that row it
/// grows with Dynamic Type; at the accessibility sizes the lines wrap and the
/// countdown moves under the detail instead of crowding the title.
struct JourneyTimelineChipContent: View {
    let symbolName: String
    /// Icon only, never text.
    let tint: Color
    let title: String
    let detail: String
    var trailing: String? = nil

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// From xLarge up the text wraps (up to 3 lines) and the countdown moves
    /// under it: on a 375pt phone "Capsule · opens May 13, 2027" no longer
    /// fits one line beside the countdown, even shrunk.
    private var isLarge: Bool { dynamicTypeSize >= .xLarge }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)

            // Same constraints as FutureLetterRowContent: the text only
            // answers to width, and takes it before the Spacer does.
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(JourneyFont.label)
                    .foregroundStyle(Brand.textPrimary)
                    .lineLimit(isLarge ? 3 : 1)
                    .minimumScaleFactor(isLarge ? 1 : 0.85)
                Text(detail)
                    .font(JourneyFont.meta)
                    .foregroundStyle(Brand.textSecondary)
                    .lineLimit(isLarge ? 3 : 1)
                    .minimumScaleFactor(isLarge ? 1 : 0.85)
                if isLarge, let trailing {
                    trailingText(trailing)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)

            Spacer(minLength: 0)

            // Keeps its full width: the title and detail shrink first, never
            // "40…" for "400 days".
            if !isLarge, let trailing {
                trailingText(trailing)
                    .fixedSize()
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Brand.textTertiary)
        }
    }

    private func trailingText(_ text: String) -> some View {
        Text(text)
            .font(JourneyFont.label)
            .foregroundStyle(Brand.textSecondary)
            .monospacedDigit()
            .contentTransition(.numericText())
            // The minute tick brings no animation of its own.
            .animation(reduceMotion ? nil : .snappy, value: text)
    }
}

// MARK: - Speech

enum JourneyTimelineSpeech {
    /// Ends `text` with a full stop unless it already ends a sentence, so a
    /// title like "Our trip!" is not read as "Our trip!.".
    static func sentence(_ text: String) -> String {
        let enders: [String] = [".", "!", "?", "…"]
        return enders.contains(where: { text.hasSuffix($0) }) ? text : text + "."
    }
}
