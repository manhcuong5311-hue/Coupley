//
//  JourneyLettersSection.swift
//  Coupley
//
//  Journey's "Future letters" section: every letter between the two of you,
//  both directions side by side.
//
//    From <partner>   the letter the partner sealed for you that matters
//                     most right now: the ready one, else the soonest
//                     sealed, else the one you opened last.
//    From you         the same, for the letters you sealed.
//
//  Envelopes only. A tile hands its letter back through `onOpenLetter` and
//  ContentView opens it in the one letters sheet; nothing here can show what
//  a letter says. "All letters" opens the hub and "Write a letter" opens
//  Compose, also through ContentView.
//
//  No container around the section: the tiles are chips and the CTA is
//  outlined, so Journey's + stays the screen's one filled accent.
//

import Foundation
import SwiftUI
import UIKit

struct JourneyLettersSection: View {

    let letters: JourneyLetterFeed
    let onOpenLetter: (FutureLetter) -> Void
    let onOpenAll: () -> Void
    let onWrite: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Brand.Space.sibling) {
            header

            if letters.letters.isEmpty {
                Text(emptyText)
                    .font(JourneyFont.body)
                    .foregroundStyle(Brand.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // One clock for both tiles, so their countdowns move together.
                // Each letter's phase still comes from the feed, whose clock
                // only moves at a boundary, exactly as on Home.
                TimelineView(.everyMinute) { context in
                    tiles(now: context.date)
                }
            }

            // Outlined at card tier; BrandCTA plays its own medium haptic.
            BrandCTA(title: "Write a letter",
                     icon: "square.and.pencil",
                     tier: .card,
                     accent: FutureLetterStyle.accent,
                     action: onWrite)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Future letters")
                .font(JourneyFont.title)
                .foregroundStyle(Brand.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            if !letters.letters.isEmpty {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onOpenAll()
                } label: {
                    Text("All letters")
                        .font(JourneyFont.label)
                        .foregroundStyle(Brand.accentStart)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var emptyText: String {
        let partner = letters.partnerName
        return String(localized: "Seal a letter for \(partner) to open on a day you pick. Letters \(partner) writes you show up here too.",
                      comment: "Journey letters section with no letters yet. Both %@ are the partner's name.")
    }

    // MARK: - Tiles

    @ViewBuilder
    private func tiles(now: Date) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        layout {
            tile(.toMe, now: now)
            tile(.fromMe, now: now)
        }
        // Side by side, both tiles take the taller one's height.
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func tile(_ direction: JourneyLetterDirection, now: Date) -> some View {
        let headline = letters.headline(direction)
        let more = max(0, letters.letters(direction).count - 1)

        if let headline {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onOpenLetter(headline.envelope)
            } label: {
                tileCard(direction, headline: headline, more: more, now: now)
            }
            .buttonStyle(BouncyButtonStyle(scale: 0.96))
            .accessibilityLabel(spokenLabel(direction, headline: headline, more: more, now: now))
            .accessibilityHint("Shows the letter.")
        } else {
            // Nothing to open: not a button.
            tileCard(direction, headline: nil, more: 0, now: now)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spokenLabel(direction, headline: nil, more: 0, now: now))
        }
    }

    private func tileCard(_ direction: JourneyLetterDirection,
                          headline: JourneyLetter?,
                          more: Int,
                          now: Date) -> some View {
        let primary = primaryLine(direction, headline: headline, now: now)

        return BrandCard(tier: .chip) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    // Same glyph and icon tint as the letter's row on Home.
                    Image(systemName: headline?.symbolName ?? "envelope")
                        .font(JourneyFont.label)
                        .foregroundStyle(headline?.tint ?? Brand.textTertiary)
                    Text(directionLabel(direction))
                        .font(JourneyFont.label)
                        .foregroundStyle(Brand.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(primary)
                    .font(JourneyFont.title)
                    .foregroundStyle(headline == nil ? Brand.textTertiary : Brand.textPrimary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    // A content transition only plays inside an animation; the
                    // minute tick brings none of its own.
                    .animation(reduceMotion ? nil : .snappy, value: primary)
                    .fixedSize(horizontal: false, vertical: true)

                // No line limit: "Opens Tue, Jan 26, 2027 at 9:00 AM" needs a
                // third line in the narrow tile at large text sizes. Both
                // tiles still share the taller one's height.
                Text(detailLine(direction, headline: headline, now: now))
                    .font(JourneyFont.meta)
                    .foregroundStyle(Brand.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if more > 0 {
                    Text("+\(more) more", comment: "Letter tile footer: how many other letters go this direction")
                        .font(JourneyFont.meta)
                        .foregroundStyle(Brand.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // MARK: - Copy

    private func directionLabel(_ direction: JourneyLetterDirection) -> String {
        direction == .toMe
            ? String(localized: "From \(letters.partnerName)",
                     comment: "Letter tile label: letters the partner wrote. %@ is the partner's name.")
            : String(localized: "From you", comment: "Letter tile label: letters the user wrote")
    }

    /// "12 days", "Ready to open", "Opened by Sam", "Nothing yet"…
    private func primaryLine(_ direction: JourneyLetterDirection,
                             headline: JourneyLetter?,
                             now: Date) -> String {
        guard let headline else {
            return direction == .toMe
                ? String(localized: "Nothing yet", comment: "Letter tile: the partner has written no letter yet")
                : String(localized: "Nothing sealed", comment: "Letter tile: the user has sealed no letter yet")
        }
        switch headline.stage {
        case .sealed:
            if headline.isPending {
                return String(localized: "Sending…", comment: "Status of a sealed letter still uploading from this phone")
            }
            return headline.countdown(now: now)
                ?? String(localized: "Sealed", comment: "Letter tile: the letter is sealed (adjective)")
        case .ready:
            return direction == .toMe
                ? String(localized: "Ready to open", comment: "Status of a future letter whose moment has come")
                : String(localized: "Ready", comment: "Letter tile: the user's letter can be opened now (adjective)")
        case .opened:
            return direction == .toMe
                ? String(localized: "Opened", comment: "Letter tile: the user has opened this letter (adjective)")
                : String(localized: "Opened by \(letters.partnerName)",
                         comment: "Letter tile: the partner opened the user's letter. %@ is the partner's name.")
        }
    }

    /// "Opens Thu, Dec 25 at 9:00 AM", "Sealed yesterday", "Nov 13"…
    private func detailLine(_ direction: JourneyLetterDirection,
                            headline: JourneyLetter?,
                            now: Date) -> String {
        guard let headline else {
            return direction == .toMe
                ? String(localized: "Letters from \(letters.partnerName) show up here",
                         comment: "Letter tile with no letter from the partner yet. %@ is the partner's name.")
                : String(localized: "Write one below", comment: "Letter tile with no letter from the user yet; the Write button is below")
        }
        switch headline.stage {
        case .sealed:
            return String(localized: "Opens \(FutureLetterClock.moment(headline.opensAt, now: now))",
                          comment: "Status of a sealed future letter. %@ is a moment such as 'today at 9:00 AM' or 'Thu, Dec 25 at 9:00 AM'.")
        case .ready:
            if direction == .toMe {
                return String(localized: "Sealed \(FutureLetterClock.sealedPhrase(headline.sealedAt, now: now))",
                              comment: "When a letter was sealed. %@ is 'today', 'yesterday' or 'on Nov 13'.")
            }
            // Due by this phone's clock, but a seal still queued here has not
            // reached the server, so it is not ready for anyone yet.
            return headline.isPending
                ? String(localized: "Sending…", comment: "Status of a sealed letter still uploading from this phone")
                : String(localized: "\(letters.partnerName) hasn't opened it yet",
                         comment: "Letter tile: the partner has not opened the user's letter. %@ is the partner's name.")
        case .opened:
            return FutureLetterClock.shortDate(headline.openedAt ?? headline.opensAt, now: now)
        }
    }

    /// One sentence per tile: "From Sam. Sealed letter from Sam. Opens Thu,
    /// Dec 25 at 9:00 AM. 12 days. 2 more letters."
    private func spokenLabel(_ direction: JourneyLetterDirection,
                             headline: JourneyLetter?,
                             more: Int,
                             now: Date) -> String {
        var parts = [JourneyTimelineSpeech.sentence(directionLabel(direction))]
        if let headline {
            parts.append(headline.spokenLabel(partnerName: letters.partnerName, now: now))
        } else {
            parts.append(JourneyTimelineSpeech.sentence(primaryLine(direction, headline: nil, now: now)))
            parts.append(JourneyTimelineSpeech.sentence(detailLine(direction, headline: nil, now: now)))
        }
        if more > 0 {
            parts.append(more == 1
                         ? String(localized: "1 more letter.", comment: "VoiceOver: one other letter goes this direction")
                         : String(localized: "\(more) more letters.", comment: "VoiceOver: how many other letters go this direction"))
        }
        return parts.joined(separator: " ")
    }
}

// MARK: - Previews

#if DEBUG

/// Built from calendar components, never `Date()`, so the canvas shows the
/// same copy whichever day it is opened. The viewer is "me", the partner Sam.
private enum JourneyLettersPreview {

    static let me = "me"
    static let partner = "sam"

    /// Friday, Nov 13, 2026 at 10:00 AM, in the canvas's own time zone.
    static let now = date(2026, 11, 13, 10, 0)

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        return Calendar.current.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    static func letter(_ id: String, toMe: Bool, opensAt: Date, sealedAt: Date,
                       openedAt: Date? = nil, isPending: Bool = false) -> JourneyLetter {
        let envelope = FutureLetter(firestoreId: nil,
                                    id: id,
                                    fromUserId: toMe ? partner : me,
                                    toUserId: toMe ? me : partner,
                                    opensAt: opensAt,
                                    sealedAt: sealedAt,
                                    openedAt: openedAt)
        return JourneyLetter(envelope: envelope,
                             phase: envelope.phase(viewer: me, now: now),
                             isPending: isPending)
    }

    static func feed(_ letters: [JourneyLetter]) -> JourneyLetterFeed {
        JourneyLetterFeed(letters: letters.sorted { $0.opensAt < $1.opensAt },
                          partnerName: "Sam",
                          isAvailable: true,
                          hasLoaded: true)
    }

    static let both = feed([
        letter("f1", toMe: true, opensAt: date(2026, 11, 25, 9, 0),
               sealedAt: date(2026, 11, 1, 18, 5)),
        letter("f2", toMe: true, opensAt: date(2025, 12, 25, 9, 0),
               sealedAt: date(2025, 2, 14, 22, 10), openedAt: date(2025, 12, 25, 9, 14)),
        letter("m1", toMe: false, opensAt: date(2026, 11, 12, 9, 0),
               sealedAt: date(2026, 10, 2, 19, 45)),
        letter("m2", toMe: false, opensAt: date(2027, 1, 26, 9, 0),
               sealedAt: date(2026, 11, 10, 21, 0))
    ])

    static let onlyMine = feed([
        letter("m3", toMe: false, opensAt: date(2026, 12, 25, 9, 0),
               sealedAt: date(2026, 11, 13, 9, 59), isPending: true)
    ])

    static let none = feed([])

    static func section(_ feed: JourneyLetterFeed) -> some View {
        ScrollView {
            JourneyLettersSection(letters: feed,
                                  onOpenLetter: { _ in },
                                  onOpenAll: {},
                                  onWrite: {})
                .padding(.horizontal, Brand.Space.gutter)
                .padding(.vertical, 24)
        }
        .background(Brand.bgGradient.ignoresSafeArea())
    }
}

#Preview("Letters · both directions") {
    JourneyLettersPreview.section(JourneyLettersPreview.both)
}

#Preview("Letters · only mine, sending") {
    JourneyLettersPreview.section(JourneyLettersPreview.onlyMine)
}

#Preview("Letters · none yet") {
    JourneyLettersPreview.section(JourneyLettersPreview.none)
}

#endif
