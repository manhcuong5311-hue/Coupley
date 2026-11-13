//
//  FutureLetterHomeViews.swift
//  Coupley
//
//  What Home shows of future letters, plus the row the letters sheet reuses.
//
//    FutureLetterPinnedRow   One chip between the masthead and the hero: the
//                            most pressing letter, "+N" for the rest, and a
//                            countdown that moves once a minute.
//    FutureLetterHeroCard    The recipient's hero once a letter has reached
//                            its moment. Only built while `heroLetter` exists,
//                            so a sealed, loading or error state never gets
//                            hero tier.
//    FutureLetterRowContent  One letter as a row, in any of the six phases.
//                            Shared by the pinned row and the hub; it draws
//                            no container of its own.
//
//  Nothing here can show what a letter says: the envelope carries no text.
//

import SwiftUI
import UIKit

// MARK: - Style

enum FutureLetterStyle {
    /// Sealing-wax amber: the hero wash and the filled CTA. White on it is
    /// ~3:1, the same as the shipping terracotta CTA. White on capsule gold
    /// would be ~1.5:1, so gold stays an icon colour.
    static let accent = Color(red: 0.85, green: 0.50, blue: 0.15)
    /// Memory Capsule gold, for icons.
    static let gold = Color(red: 1.0, green: 0.78, blue: 0.30)
    static let goldDeep = Color(red: 0.95, green: 0.55, blue: 0.30)
    /// The house "done" green.
    static let opened = Color(red: 0.25, green: 0.75, blue: 0.50)
}

// MARK: - Wax seal strip

/// The Memory Capsule's sealed-envelope strip (MemoryCard's locked body):
/// fourteen bars, alternating gold and deep gold. Decoration only.
struct WaxSealStrip: View {
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<14, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index % 2 == 0
                          ? FutureLetterStyle.gold.opacity(0.65)
                          : FutureLetterStyle.goldDeep.opacity(0.45))
                    .frame(height: 4)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Row content

/// One letter as a row: icon, title over detail, then "+N", a countdown or
/// "Open", and a chevron. Callers wrap it in `BrandCard(tier: .chip)`.
struct FutureLetterRowContent: View {
    let letter: FutureLetter
    /// Decided by the view model's clock, which moves only at boundaries.
    let phase: FutureLetterPhase
    let partnerName: String
    /// The clock the text is written against. The pinned row passes its
    /// TimelineView's date, so the countdown moves every minute without the
    /// view model publishing anything.
    let now: Date
    /// The seal is still a local, unacknowledged write.
    var isPending: Bool = false
    /// Other pinned letters, shown as "+N".
    var extraCount: Int = 0

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(symbolTint)
                .frame(width: 26, height: 26)

            // The shrink is for 375pt screens, where "Opens Sat, Dec 18, 2027
            // at 10:00 AM" beside "400 days" would otherwise lose its time.
            // It must only answer to width: without the vertical fixedSize,
            // the row's height is split between two shrinkable lines and the
            // title scales down on rows with room to spare. The priority
            // gives the text its width before the Spacer takes any.
            VStack(alignment: .leading, spacing: 2) {
                Text(titleText)
                    .font(BrandType.label)
                    .foregroundStyle(Brand.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(detailText)
                    .font(BrandType.meta)
                    .foregroundStyle(Brand.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)

            Spacer(minLength: 0)

            // The trailing items keep their full width: the title and the
            // detail truncate first, never "40…" for "400 days".
            if extraCount > 0 {
                Text(verbatim: "+\(extraCount)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(FutureLetterStyle.accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(FutureLetterStyle.gold.opacity(0.18)))
                    .fixedSize()
            }

            if let countdownText {
                Text(countdownText)
                    .font(BrandType.label)
                    .foregroundStyle(Brand.textSecondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    // A content transition only plays inside an animation;
                    // the TimelineView's minute tick brings none of its own.
                    .animation(.snappy, value: countdownText)
                    .fixedSize()
            } else if phase == .readyForMe {
                Text("Open", comment: "Trailing label on a letter row: the letter can be opened now.")
                    .font(BrandType.label)
                    .foregroundStyle(FutureLetterStyle.accent)
                    .fixedSize()
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Brand.textTertiary)
        }
        // One VoiceOver element, read as sentences:
        // "Sealed letter from Sam. Opens Thu, Dec 25 at 9:00 AM. 12 days."
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityHint(spokenHint)
    }

    // MARK: Phase → copy

    private var symbolName: String {
        switch phase {
        case .sealedForMe, .sealedByMe:       return "lock.fill"
        case .readyForMe, .waitingForPartner: return "envelope.fill"
        case .openedByMe, .openedByPartner:   return "envelope.open.fill"
        }
    }

    private var symbolTint: Color {
        switch phase {
        case .sealedForMe, .sealedByMe, .waitingForPartner: return FutureLetterStyle.gold
        case .readyForMe:                                   return FutureLetterStyle.accent
        case .openedByMe, .openedByPartner:                 return FutureLetterStyle.opened
        }
    }

    private var titleText: String {
        switch phase {
        case .sealedForMe:
            return String(localized: "Sealed letter from \(partnerName)")
        case .readyForMe, .openedByMe:
            return String(localized: "Letter from \(partnerName)")
        case .sealedByMe, .waitingForPartner:
            return String(localized: "Your letter to \(partnerName)")
        case .openedByPartner:
            return String(localized: "\(partnerName) opened your letter")
        }
    }

    private var detailText: String {
        switch phase {
        case .sealedForMe:
            return opensText
        case .sealedByMe:
            // Queued offline, or not yet acknowledged.
            return isPending ? sendingText : opensText
        case .readyForMe:
            return String(localized: "Ready to open", comment: "A letter that has reached its moment.")
        case .waitingForPartner:
            // Due by this phone's clock, but the seal is still queued here:
            // it has not reached the server, so it is not ready for anyone.
            return isPending ? sendingText : String(localized: "Ready — \(partnerName) hasn't opened it yet")
        case .openedByMe, .openedByPartner:
            return openedText
        }
    }

    private var sendingText: String {
        String(localized: "Sending…", comment: "A sealed letter not yet acknowledged by the server.")
    }

    /// "Opens Thu, Dec 25 at 9:00 AM", "Opens today at 9:00 AM".
    private var opensText: String {
        let when = FutureLetterClock.moment(letter.opensAt, now: now)
        return String(localized: "Opens \(when)", comment: "%@ is a moment, such as 'today at 9:00 AM'.")
    }

    /// "Opened today at 9:14 AM". Both opened phases imply `openedAt`; the
    /// bare word only covers a malformed document.
    private var openedText: String {
        guard let openedAt = letter.openedAt else {
            return String(localized: "Opened", comment: "A letter that has been opened.")
        }
        let when = FutureLetterClock.moment(openedAt, now: now)
        return String(localized: "Opened \(when)", comment: "%@ is a moment, such as 'today at 9:14 AM'.")
    }

    /// "12 days", "1 day", "5 hr", "42 min", "1 min" or "Now", for the two
    /// sealed phases only. "Now" shows in the quarter-second between this
    /// row's minute tick and the view model's flip.
    private var countdownText: String? {
        switch phase {
        case .sealedForMe, .sealedByMe:
            return FutureLetterClock.shortCountdown(to: letter.opensAt, now: now)
        case .readyForMe, .openedByMe, .waitingForPartner, .openedByPartner:
            return nil
        }
    }

    // MARK: VoiceOver

    /// Title, detail and countdown as sentences, then the "+N" in words.
    /// "Open" is left out: "Ready to open" already says it.
    private var spokenLabel: String {
        var parts = [titleText, detailText]
        if let countdownText { parts.append(countdownText) }
        if extraCount > 0 {
            parts.append(extraCount == 1
                         ? String(localized: "1 more letter", comment: "VoiceOver: other pinned letters besides this one.")
                         : String(localized: "\(extraCount) more letters", comment: "VoiceOver: other pinned letters besides this one."))
        }
        // Journey's sentence rules: the full stop is localized (。, ।) rather
        // than an English "." glued onto translated text.
        return JourneyTimelineSpeech.sentences(parts)
    }

    private var spokenHint: String {
        extraCount > 0
            ? String(localized: "Shows all your letters.", comment: "VoiceOver hint on the pinned letter row.")
            : String(localized: "Shows the letter.", comment: "VoiceOver hint on a letter row.")
    }
}

// MARK: - Home: pinned row

/// The chip under the masthead. The dashboard only builds it while
/// `pinnedLetters` is non-empty; it renders nothing otherwise.
struct FutureLetterPinnedRow: View {
    @ObservedObject var viewModel: FutureLetterViewModel
    let partnerName: String
    /// True while something else holds Home's hero (both partners here right
    /// now): a letter ready for this user is then pinned first instead.
    var includesReady: Bool = false

    var body: some View {
        let pinned = viewModel.pinnedLetters(includingReady: includesReady)
        if let letter = pinned.first {
            // The minute tick re-renders this row alone. The phase still
            // comes from the view model, whose clock moves at the boundaries
            // (a letter opening, a receipt expiring) and nowhere else.
            TimelineView(.everyMinute) { context in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    openPinned()
                } label: {
                    BrandCard(tier: .chip) {
                        FutureLetterRowContent(
                            letter: letter,
                            phase: viewModel.phase(of: letter),
                            partnerName: partnerName,
                            now: context.date,
                            isPending: viewModel.isPending(letter),
                            extraCount: pinned.count - 1
                        )
                    }
                }
                .buttonStyle(BouncyButtonStyle(scale: 0.96))
            }
        }
    }

    /// One pinned letter opens that letter. Several open the hub, where all
    /// of them are listed.
    private func openPinned() {
        let pinned = viewModel.pinnedLetters(includingReady: includesReady)
        if pinned.count > 1 {
            viewModel.openHub()
        } else if let letter = pinned.first {
            viewModel.show(letter)
        }
    }
}

// MARK: - Home: hero card

/// The recipient's hero: a letter that has reached its moment and is still
/// unopened. The only accent-washed object on Home while it shows.
struct FutureLetterHeroCard: View {
    let letter: FutureLetter
    let partnerName: String
    /// Other letters ready for me besides this one.
    let moreReady: Int
    let now: Date
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Future letter")
                    .font(BrandType.label)
                    .foregroundStyle(Brand.textSecondary)
                Spacer()
                Image(systemName: "envelope.open.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(FutureLetterStyle.gold)
                    .accessibilityHidden(true)
            }

            Text("From \(partnerName)")
                .font(BrandType.hero)
                .foregroundStyle(Brand.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)

            Text("Unsealed \(FutureLetterClock.moment(letter.opensAt, now: now))",
                 comment: "%@ is a moment, such as 'today at 9:00 AM'.")
                .font(BrandType.body)
                .foregroundStyle(Brand.textSecondary)

            WaxSealStrip()

            // The screen's one filled accent. BrandCTA plays its own medium
            // haptic.
            BrandCTA(title: "Open letter",
                     icon: "envelope.open.fill",
                     tier: .hero,
                     accent: FutureLetterStyle.accent,
                     action: onOpen)

            if moreReady > 0 {
                Text(verbatim: "+\(moreReadyText)")
                    .font(BrandType.meta)
                    .foregroundStyle(Brand.textSecondary)
                    .accessibilityLabel(moreReadyText)
            }
        }
        .modifier(TierContainer(tier: .hero, accent: FutureLetterStyle.accent))
    }

    /// "1 more letter is ready", "2 more letters are ready". Shown with a
    /// leading "+", which VoiceOver is spared.
    private var moreReadyText: String {
        moreReady == 1
            ? String(localized: "1 more letter is ready", comment: "Under the Home hero: other letters ready to open.")
            : String(localized: "\(moreReady) more letters are ready", comment: "Under the Home hero: other letters ready to open.")
    }
}

// MARK: - Previews

#if DEBUG

/// Every date is built from calendar components, never `Date()`, so the
/// canvas shows the same copy whichever day it is opened. The viewer is "me"
/// and the partner is Sam.
private enum FutureLetterPreview {

    static let me = "me"
    static let partner = "sam"
    static let partnerName = "Sam"

    /// Friday, Nov 13, 2026 at 10:00 AM, in the canvas's own time zone.
    static let now = date(2026, 11, 13, 10, 0)

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        return Calendar.current.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    /// `now` moved by whole calendar units, so "+1 day" keeps 10:00 AM.
    static func shifted(_ component: Calendar.Component, by value: Int) -> Date {
        Calendar.current.date(byAdding: component, value: value, to: now) ?? now
    }

    static func letter(_ id: String, toMe: Bool, opensAt: Date, sealedAt: Date,
                       openedAt: Date? = nil) -> FutureLetter {
        FutureLetter(firestoreId: nil,
                     id: id,
                     fromUserId: toMe ? partner : me,
                     toUserId: toMe ? me : partner,
                     opensAt: opensAt,
                     sealedAt: sealedAt,
                     openedAt: openedAt)
    }

    struct Row: Identifiable {
        let caption: String
        let letter: FutureLetter
        /// The view model's clock, which decides the phase. The row's text
        /// uses `now`, as the pinned row uses its TimelineView's date; the
        /// two differ only in the quarter-second before a flip.
        var clock: Date = FutureLetterPreview.now
        var isPending = false
        var extraCount = 0

        var id: String { letter.id }
    }

    /// The recipient's side: the pinned states, then the hub's two others.
    static let forMe: [Row] = [
        Row(caption: "sealedForMe · opens in 3 min",
            letter: letter("f1", toMe: true, opensAt: shifted(.minute, by: 3),
                           sealedAt: date(2026, 11, 12, 21, 30))),
        Row(caption: "sealedForMe · opens in 12 days, 2 more pinned",
            letter: letter("f2", toMe: true, opensAt: date(2026, 11, 25, 9, 0),
                           sealedAt: date(2026, 11, 1, 18, 5)),
            extraCount: 2),
        Row(caption: "sealedForMe · the quarter-second before the flip",
            letter: letter("f3", toMe: true, opensAt: now,
                           sealedAt: date(2026, 11, 10, 8, 15)),
            clock: now.addingTimeInterval(-0.25)),
        Row(caption: "readyForMe (hub) · sealed in 2025",
            letter: letter("f4", toMe: true, opensAt: date(2026, 11, 13, 9, 0),
                           sealedAt: date(2025, 11, 13, 20, 41))),
        Row(caption: "openedByMe (hub) · opened in 2025",
            letter: letter("f5", toMe: true, opensAt: date(2025, 12, 25, 9, 0),
                           sealedAt: date(2025, 2, 14, 22, 10),
                           openedAt: date(2025, 12, 25, 9, 14)))
    ]

    /// The sender's side.
    static let fromMe: [Row] = [
        Row(caption: "sealedByMe · opens in 5 h",
            letter: letter("m1", toMe: false, opensAt: shifted(.hour, by: 5),
                           sealedAt: shifted(.minute, by: -20))),
        Row(caption: "sealedByMe · opens in 1 day",
            letter: letter("m2", toMe: false, opensAt: shifted(.day, by: 1),
                           sealedAt: date(2026, 11, 11, 23, 2))),
        Row(caption: "sealedByMe · still sending (offline)",
            letter: letter("m3", toMe: false, opensAt: date(2026, 12, 25, 9, 0),
                           sealedAt: shifted(.minute, by: -1)),
            isPending: true),
        Row(caption: "sealedByMe · opens in 400 days",
            letter: letter("m4", toMe: false, opensAt: shifted(.day, by: 400),
                           sealedAt: date(2026, 11, 2, 19, 0))),
        Row(caption: "waitingForPartner",
            letter: letter("m5", toMe: false, opensAt: date(2026, 11, 12, 9, 0),
                           sealedAt: date(2026, 10, 2, 19, 45))),
        Row(caption: "openedByPartner · opened 2 h ago",
            letter: letter("m6", toMe: false, opensAt: date(2026, 11, 13, 7, 30),
                           sealedAt: date(2026, 9, 1, 12, 0),
                           openedAt: shifted(.hour, by: -2)))
    ]

    /// Each row in the chip the pinned row and the hub put it in.
    static func list(_ rows: [Row]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Brand.Space.sibling) {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(row.caption)
                            .font(BrandType.meta)
                            .foregroundStyle(Brand.textTertiary)
                        BrandCard(tier: .chip) {
                            FutureLetterRowContent(
                                letter: row.letter,
                                phase: row.letter.phase(viewer: me, now: row.clock),
                                partnerName: partnerName,
                                now: now,
                                isPending: row.isPending,
                                extraCount: row.extraCount
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, Brand.Space.gutter)
            .padding(.vertical, 24)
        }
        .background(Brand.bgGradient.ignoresSafeArea())
    }

    /// Ready since 9:00 this morning, sealed a year earlier.
    static let heroLetter = letter("h1", toMe: true, opensAt: date(2026, 11, 13, 9, 0),
                                   sealedAt: date(2025, 11, 13, 20, 41))

    /// More than one card only to compare copy; Home renders one hero.
    static func heroes(moreReady counts: [Int]) -> some View {
        ScrollView {
            VStack(spacing: Brand.Space.zone) {
                ForEach(counts, id: \.self) { more in
                    FutureLetterHeroCard(letter: heroLetter,
                                         partnerName: partnerName,
                                         moreReady: more,
                                         now: now,
                                         onOpen: {})
                }
            }
            .padding(.horizontal, SurfaceTier.hero.gutter)
            .padding(.vertical, 24)
        }
        .background(Brand.bgGradient.ignoresSafeArea())
    }
}

#Preview("Rows · for me") {
    FutureLetterPreview.list(FutureLetterPreview.forMe)
}

#Preview("Rows · from me") {
    FutureLetterPreview.list(FutureLetterPreview.fromMe)
}

#Preview("Hero") {
    FutureLetterPreview.heroes(moreReady: [0])
}

#Preview("Hero · more ready") {
    FutureLetterPreview.heroes(moreReady: [1, 2])
}

#endif
