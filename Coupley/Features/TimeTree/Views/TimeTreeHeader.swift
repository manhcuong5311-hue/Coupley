//
//  TimeTreeHeader.swift
//  Coupley
//
//  The top of Journey, under the masthead:
//
//   1. ONE hero: the tree and the day count together. The count, the stage
//      and "Since 26 Jan 2026 · Edit" sit on the leading side; the tree,
//      with the letters hanging from it, on the trailing side. The day count
//      and the stage name appear nowhere else on the screen.
//   2. One quiet countdown block: the next anniversary and the next crown,
//      merged into one row when they fall on the same day, plus the
//      "Letter for that day" line.
//
//  Without a start date the hero is a "Plant your tree" card whose CTA opens
//  the start-date sheet, and there is no countdown block.
//
//  Everything here is a value: TimeTreeView passes the view model's numbers,
//  the letters feed and the callbacks, so this view never observes anything.
//

import Foundation
import SwiftUI
import UIKit

// MARK: - Header View

struct TimeTreeHeader: View {

    let anchor: RelationshipAnchor?
    let now: Date
    /// The view model's count, which reads the start date as a calendar day.
    let daysTogether: Int?
    let stage: TreeGrowthStage
    let season: TreeSeason
    /// Visible memories, one star each around the tree.
    let memoryCount: Int
    let letters: JourneyLetterFeed
    /// 196, or 160 when the scroll viewport is short. Regular layout only.
    let treeHeight: CGFloat
    let onEditStartDate: () -> Void
    let onShowTreeGuide: () -> Void
    /// A letter tapped on the tree. ContentView opens it in the letters sheet.
    let onOpenLetter: (FutureLetter) -> Void
    /// "Letter for that day": Compose, preset to 9:00 on the anniversary.
    let onWriteLetter: (_ opensAt: Date) -> Void
    /// False while there is no start date here and the server hasn't said
    /// whether one exists (offline, or still loading). The view model
    /// refuses a first start date then, so "Plant your tree" isn't offered.
    var isStartDateKnown: Bool = true

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .footnote) private var rowGlyphWidth: CGFloat = 18

    var body: some View {
        VStack(spacing: 14) {
            if let anchor {
                hero(anchor)
                    .padding(.horizontal, SurfaceTier.hero.gutter)
                countdownBlock(anchor)
                    .padding(.horizontal, Brand.Space.gutter)
            } else if isStartDateKnown {
                plantHero
                    .padding(.horizontal, SurfaceTier.hero.gutter)
            } else {
                startDateLoadingHero
                    .padding(.horizontal, SurfaceTier.hero.gutter)
            }
        }
    }

    private var isStacked: Bool { dynamicTypeSize.isAccessibilitySize }

    // MARK: - Hero

    private func hero(_ anchor: RelationshipAnchor) -> some View {
        let days = daysTogether ?? anchor.daysTogether(now: now)
        // No more blossoms than the tree has places for at this stage, so
        // none stack and VoiceOver counts exactly what is drawn.
        let ornaments: [JourneyTreeOrnament] = letters.isAvailable
            ? letters.treeOrnaments(maxEnvelopesPerSide: isStacked ? 3 : 2,
                                    maxBlossoms: min(isStacked ? 8 : 6,
                                                     RelationshipTreeCanvas.blossomCapacity(at: stage)))
            : []

        return BrandCard(tier: .hero) {
            if isStacked {
                // Accessibility sizes: the text needs the full width.
                VStack(alignment: .leading, spacing: 16) {
                    heroText(anchor, days: days)
                    tree(days: days, ornaments: ornaments)
                        .frame(maxWidth: .infinity)
                        .frame(height: 180)
                }
            } else {
                HStack(alignment: .bottom, spacing: 4) {
                    heroText(anchor, days: days)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    tree(days: days, ornaments: ornaments)
                        .containerRelativeFrame(.horizontal) { length, _ in
                            Self.canvasWidth(containerWidth: length)
                        }
                        .frame(height: treeHeight)
                }
                // The column takes the row's height, so its Spacer can push
                // the count to the top and the stage to the bottom.
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// About 55% of the hero's inner width (169pt at 375, 184pt at 402).
    /// The canvas scales its tree from its width, so this is also the
    /// canopy's size.
    private static func canvasWidth(containerWidth: CGFloat) -> CGFloat {
        let inner = containerWidth
            - 2 * SurfaceTier.hero.gutter
            - 2 * SurfaceTier.hero.padding
        return max(120, (inner * 0.55).rounded())
    }

    private func heroText(_ anchor: RelationshipAnchor, days: Int) -> some View {
        let startDay = JourneyCalendarDay.localDay(ofStored: anchor.startDate)
        let since = startDay.formatted(.dateTime.day().month(.abbreviated).year())
        let spokenSince = startDay.formatted(.dateTime.day().month(.wide).year())
        let sinceText = Text("Since \(since)",
                             comment: "Journey hero, under the stage: when the relationship started. %@ is the start date such as '26 Jan 2026'. An 'Edit' link follows it.")
        let editLinkText = Text("Edit", comment: "Journey hero: link to edit the relationship start date")
            .foregroundStyle(Brand.accentStart)

        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(days, format: .number)
                    .font(JourneyFont.number)
                    .foregroundStyle(Brand.textPrimary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                // Agrees with the count above it (Russian: 292 дня, 295 дней).
                Text(verbatim: CountedCaption.removingCount(from: String(
                    localized: "\(days) days together",
                    comment: "Journey hero: caption under the big day count. The number is shown large above it and the app removes it here, so keep %lld and write each plural form to read naturally without the number ('%lld days together' shows as 'days together').")))
                .font(JourneyFont.label)
                .foregroundStyle(Brand.textSecondary)
            }
            // The column reads as one sentence; the caption below is folded
            // into it, and the two buttons stay their own elements.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(heroSummary(days: days))

            Spacer(minLength: 12)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onShowTreeGuide()
            } label: {
                HStack(spacing: 4) {
                    Text(stage.displayName)
                        .font(JourneyFont.label)
                        .foregroundStyle(Brand.textPrimary)
                    Image(systemName: "info.circle")
                        .font(JourneyFont.meta)
                        .foregroundStyle(Brand.textSecondary)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("\(stage.displayName). How your tree grows",
                                     comment: "VoiceOver: the tree stage button, which opens a guide to the stages. %@ is the stage name such as 'Blooming'."))

            Text(stage.poeticCaption)
                .font(JourneyFont.body)
                .foregroundStyle(Brand.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onEditStartDate()
            } label: {
                // "Since 26 Jan 2026 · Edit" on one line when it fits. Long
                // dates in a narrow column next to the tree put the link on
                // its own line instead of leaving "· Edit" stranded.
                ViewThatFits(in: .horizontal) {
                    // One Text, so the spaces around the dot stay on both sides
                    // in right-to-left languages too.
                    (sinceText + Text(verbatim: " · ") + editLinkText)
                        .lineLimit(1)
                    VStack(alignment: .leading, spacing: 2) {
                        sinceText
                            .fixedSize(horizontal: false, vertical: true)
                        editLinkText
                    }
                }
                .font(JourneyFont.meta)
                .foregroundStyle(Brand.textSecondary)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
            .accessibilityLabel(Text("Started \(spokenSince). Edit start date",
                                     comment: "VoiceOver: the start date button. %@ is a date such as '26 January 2026'."))
        }
    }

    /// "291 days together. Blooming. First flowers on the branches."
    private func heroSummary(days: Int) -> String {
        let name = stage.displayName
        let caption = stage.poeticCaption
        return days == 1
            ? String(localized: "1 day together. \(name). \(caption)",
                     comment: "VoiceOver summary of the Journey hero. First %@ is the tree stage name, second its caption (a full sentence).")
            : String(localized: "\(days) days together. \(name). \(caption)",
                     comment: "VoiceOver summary of the Journey hero: day count, then the tree stage name, then its caption (a full sentence).")
    }

    private func tree(days: Int, ornaments: [JourneyTreeOrnament]) -> some View {
        RelationshipTreeCanvas(
            stage: stage,
            season: season,
            daysTogether: days,
            memoryCount: memoryCount,
            crownActive: stage.showsAmbientCrown,
            ornaments: ornaments,
            onSelectOrnament: { id in
                if let letter = letters.letter(id: id) {
                    onOpenLetter(letter.envelope)
                }
            }
        )
        // VoiceOver gets one summary. The ornaments' tap targets are for
        // touch only; the letters section and the timeline list every
        // letter as a proper element.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(treeSummary(ornaments))
        .accessibilityAddTraits(.isImage)
    }

    /// "Your tree. 3 memories shine around it. 1 letter for you is ready to
    /// open. 2 sealed letters wait on it. 1 opened letter is in bloom."
    /// A ready envelope is either the partner's letter for this user or this
    /// user's letter the partner hasn't opened; neither is "sealed". Small
    /// trees rest envelopes on the ground, so nothing says "branches".
    private func treeSummary(_ ornaments: [JourneyTreeOrnament]) -> String {
        let readyForMe = ornaments.filter { $0.kind == .readyEnvelope && $0.direction == .toMe }.count
        let waiting = ornaments.filter { $0.kind == .readyEnvelope && $0.direction == .fromMe }.count
        let sealed = ornaments.filter { $0.kind == .sealedEnvelope }.count
        let blossoms = ornaments.filter { $0.kind == .blossom }.count
        let partner = letters.partnerName
        // Whole sentences, each its own key, read one after another.
        var parts = [String(localized: "Your tree.", comment: "VoiceOver: first sentence describing the Journey tree picture")]
        if memoryCount > 0 {
            parts.append(memoryCount == 1
                         ? String(localized: "1 memory shines around it.",
                                  comment: "VoiceOver, Journey tree: memories are drawn as stars around the tree")
                         : String(localized: "\(memoryCount) memories shine around it.",
                                  comment: "VoiceOver, Journey tree: memories are drawn as stars around the tree"))
        }
        if readyForMe > 0 {
            parts.append(readyForMe == 1
                         ? String(localized: "1 letter for you is ready to open.",
                                  comment: "VoiceOver, Journey tree: letters hang on it as envelopes")
                         : String(localized: "\(readyForMe) letters for you are ready to open.",
                                  comment: "VoiceOver, Journey tree: letters hang on it as envelopes"))
        }
        if waiting > 0 {
            parts.append(waiting == 1
                         ? String(localized: "1 of your letters is waiting for \(partner) to open it.",
                                  comment: "VoiceOver, Journey tree. %@ is the partner's name.")
                         : String(localized: "\(waiting) of your letters are waiting for \(partner) to open them.",
                                  comment: "VoiceOver, Journey tree. The number counts the user's letters; %@ is the partner's name."))
        }
        if sealed > 0 {
            parts.append(sealed == 1
                         ? String(localized: "1 sealed letter waits on it.",
                                  comment: "VoiceOver, Journey tree: a sealed letter hangs on the tree as an envelope")
                         : String(localized: "\(sealed) sealed letters wait on it.",
                                  comment: "VoiceOver, Journey tree: sealed letters hang on the tree as envelopes"))
        }
        if blossoms > 0 {
            parts.append(blossoms == 1
                         ? String(localized: "1 opened letter is in bloom.",
                                  comment: "VoiceOver, Journey tree: opened letters are drawn as blossoms")
                         : String(localized: "\(blossoms) opened letters are in bloom.",
                                  comment: "VoiceOver, Journey tree: opened letters are drawn as blossoms"))
        }
        return parts.joined(separator: " ")
    }

    // MARK: - No start date yet

    private var plantHero: some View {
        BrandCard(tier: .hero) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "leaf.fill")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .foregroundStyle(Brand.accentStart)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Plant your tree")
                        .font(JourneyFont.title)
                        .foregroundStyle(Brand.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text("Set the day your story began. Your tree grows from it, and your partner sees it too.")
                        .font(JourneyFont.body)
                        .foregroundStyle(Brand.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Filled at hero tier. Journey's + is outlined until a start
                // date exists, so this stays the screen's only fill.
                BrandCTA(title: "Set your start date",
                         icon: "calendar",
                         tier: .hero,
                         action: onEditStartDate)
                    .padding(.top, 4)
            }
        }
    }

    /// No start date here yet, and the server hasn't answered whether one
    /// exists: briefly while loading, or for as long as the phone is
    /// offline. True in both cases, and offers nothing it can't save.
    private var startDateLoadingHero: some View {
        BrandCard(tier: .hero) {
            HStack(spacing: 10) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(Brand.accentStart)
                Text("Loading your tree…")
                    .font(JourneyFont.body)
                    .foregroundStyle(Brand.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Countdown block

    private func countdownBlock(_ anchor: RelationshipAnchor) -> some View {
        let next = Countdown(anchor: anchor, now: now)
        let years = next.anniversaryNumber

        return BrandCard(tier: .quiet, showsRule: true) {
            VStack(alignment: .leading, spacing: 12) {
                if let crown = next.crown, next.crownSharesAnniversaryDay {
                    let crownTitle = crown.localizedTitle
                    countdownRow(
                        glyph: "crown.fill",
                        tint: FutureLetterStyle.gold,
                        title: String(localized: "\(years)-year anniversary · \(crownTitle) crown",
                                      comment: "Journey countdown when the next anniversary and the next crown fall on the same day. %lld is how many years together that anniversary marks (1, 2, 3...); %@ is a crown title such as '1000 Days'."),
                        value: Self.countdownValue(next.anniversaryDays),
                        date: next.anniversaryDate,
                        progress: next.crownProgress,
                        spoken: [
                            String(localized: "Next anniversary, \(years) years together, and the \(crownTitle) crown.",
                                   comment: "VoiceOver, Journey countdown. %lld is how many years together the next anniversary marks; %@ is a crown title such as '1000 Days'."),
                            Self.spokenWhen(next.anniversaryDays, date: next.anniversaryDate)
                        ].joined(separator: " ")
                    ) {
                        letterLine(anniversary: next.anniversaryDate)
                    }
                } else {
                    countdownRow(
                        glyph: "calendar",
                        tint: Brand.textSecondary,
                        title: String(localized: "\(years)-year anniversary",
                                      comment: "Journey countdown row: the next yearly anniversary. %lld is how many years together it marks (1, 2, 3...)."),
                        value: Self.countdownValue(next.anniversaryDays),
                        date: next.anniversaryDate,
                        progress: nil,
                        spoken: [
                            String(localized: "Next anniversary, \(years) years together.",
                                   comment: "VoiceOver, Journey countdown. %lld is how many years together the next anniversary marks."),
                            Self.spokenWhen(next.anniversaryDays, date: next.anniversaryDate)
                        ].joined(separator: " ")
                    ) {
                        letterLine(anniversary: next.anniversaryDate)
                    }

                    if let crown = next.crown, let crownDate = next.crownDate {
                        let crownTitle = crown.localizedTitle
                        countdownRow(
                            glyph: "crown.fill",
                            tint: FutureLetterStyle.gold,
                            title: String(localized: "\(crownTitle) crown",
                                          comment: "Journey countdown row: the next crown milestone. %@ is a crown title such as '100 Days' or '1 Year'."),
                            value: Self.countdownValue(next.crownDays),
                            date: crownDate,
                            progress: next.crownProgress,
                            spoken: [
                                String(localized: "Next crown, \(crownTitle).",
                                       comment: "VoiceOver, Journey countdown. %@ is a crown title such as '100 Days' or '1 Year'."),
                                Self.spokenWhen(next.crownDays, date: crownDate)
                            ].joined(separator: " ")
                        ) {
                            EmptyView()
                        }
                    } else {
                        // The couple has cleared the whole ladder.
                        countdownRow(
                            glyph: "crown.fill",
                            tint: FutureLetterStyle.gold,
                            title: String(localized: "Every crown earned · Legendary.",
                                          comment: "Journey countdown row once every crown milestone (up to 10 years) is reached"),
                            value: nil,
                            date: nil,
                            progress: nil,
                            spoken: String(localized: "Every crown earned. Legendary.",
                                           comment: "VoiceOver: every crown milestone (up to 10 years) is reached")
                        ) {
                            EmptyView()
                        }
                    }
                }
            }
        }
    }

    /// Glyph, then title and value on one line (the value drops under the
    /// title at accessibility sizes), the date, an optional progress bar and
    /// an optional footer. Everything but the footer is one VoiceOver
    /// element; the footer's letter button stays its own.
    private func countdownRow<Footer: View>(
        glyph: String,
        tint: Color,
        title: String,
        value: String?,
        date: Date?,
        progress: Double?,
        spoken: String,
        @ViewBuilder footer: () -> Footer
    ) -> some View {
        // "42%" in the user's locale; VoiceOver reads it in their language.
        let percent: String = progress.map { Int(($0 * 100).rounded()).formatted(.percent) } ?? ""

        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: glyph)
                .font(JourneyFont.label)
                .foregroundStyle(tint)
                .frame(width: rowGlyphWidth)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    if isStacked {
                        rowTitle(title)
                        if let value { rowValue(value) }
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            rowTitle(title)
                            Spacer(minLength: 8)
                            // The title wraps before "438 days" truncates.
                            if let value { rowValue(value).fixedSize() }
                        }
                    }

                    if let date {
                        Text(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year()))
                            .font(JourneyFont.meta)
                            .foregroundStyle(Brand.textSecondary)
                    }

                    if let progress {
                        progressBar(progress)
                            .padding(.top, 6)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spoken)
                // Empty for rows without a bar, which VoiceOver skips.
                .accessibilityValue(percent)

                footer()
            }
        }
    }

    private func rowTitle(_ title: String) -> some View {
        Text(title)
            .font(JourneyFont.label)
            .foregroundStyle(Brand.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func rowValue(_ value: String) -> some View {
        Text(value)
            .font(JourneyFont.title)
            .foregroundStyle(Brand.textPrimary)
            .monospacedDigit()
            .contentTransition(.numericText())
    }

    private func progressBar(_ progress: Double) -> some View {
        Capsule()
            .fill(Brand.divider)
            .frame(height: 4)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule()
                        .fill(LinearGradient(colors: [FutureLetterStyle.gold, FutureLetterStyle.goldDeep],
                                             startPoint: .leading,
                                             endPoint: .trailing))
                        .frame(width: max(4, geo.size.width * CGFloat(progress)))
                }
            }
    }

    // MARK: - Letter for that day

    /// The most natural future letter there is: one that opens on the
    /// anniversary. A quiet text button (Journey's + stays the screen's one
    /// fill) opens Compose preset to 9:00 that day. Once a letter is sealed
    /// for that day it becomes a plain line, so a second one isn't written by
    /// accident; the partner's side says a letter is waiting for them.
    @ViewBuilder
    private func letterLine(anniversary: Date) -> some View {
        // Until the letters have answered once, a sealed letter for that day
        // may simply not be here yet; offering to write one would flicker.
        if letters.isAvailable && letters.hasLoaded {
            let calendar = Calendar.current
            let day = calendar.startOfDay(for: anniversary)
            let opensAt = calendar.date(bySettingHour: FutureLetterSchedule.defaultHour,
                                        minute: 0, second: 0, of: day) ?? day
            let forMe = letters.sealedOpeningDays(.toMe).contains(day)
            let mine = letters.sealedOpeningDays(.fromMe).contains(day)
            let canWrite = !mine && FutureLetterSchedule.isValid(opensAt, now: now)

            if forMe || mine || canWrite {
                VStack(alignment: .leading, spacing: 6) {
                    if forMe {
                        letterNote("A letter for you opens that day")
                    }
                    if mine {
                        letterNote("Your letter opens that day")
                    } else if canWrite {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onWriteLetter(opensAt)
                        } label: {
                            Label {
                                Text("Letter for that day",
                                     comment: "Journey countdown: button to write a future letter that opens on the next anniversary")
                            } icon: {
                                Image(systemName: "envelope.fill")
                            }
                            .font(JourneyFont.label)
                            .foregroundStyle(FutureLetterStyle.accent)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Write a future letter that opens on your anniversary")
                    }
                }
            }
        }
    }

    private func letterNote(_ text: LocalizedStringResource) -> some View {
        Label {
            Text(text)
                .foregroundStyle(Brand.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "envelope.fill")
                .foregroundStyle(FutureLetterStyle.gold)
        }
        .font(JourneyFont.meta)
    }

    // MARK: - Copy helpers

    /// "74 days", "1 day", "Today".
    private static func countdownValue(_ days: Int) -> String {
        switch days {
        case ...0: return String(localized: "Today", comment: "Journey countdown value: the anniversary or crown is today")
        case 1:    return String(localized: "1 day", comment: "Journey countdown value: time left")
        default:   return String(localized: "\(days) days", comment: "Journey countdown value: time left")
        }
    }

    /// "In 74 days, Tuesday 26 January 2027."
    private static func spokenWhen(_ days: Int, date: Date) -> String {
        let spokenDate = date.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
        switch days {
        case ...0:
            return String(localized: "Today, \(spokenDate).",
                          comment: "VoiceOver, Journey countdown. %@ is a full date such as 'Tuesday, 26 January 2027'.")
        case 1:
            return String(localized: "In 1 day, \(spokenDate).",
                          comment: "VoiceOver, Journey countdown. %@ is a full date such as 'Tuesday, 26 January 2027'.")
        default:
            return String(localized: "In \(days) days, \(spokenDate).",
                          comment: "VoiceOver, Journey countdown. %@ is a full date such as 'Tuesday, 26 January 2027'.")
        }
    }
}

// MARK: - Countdown values

/// The next anniversary and the next crown, worked out once per render.
private struct Countdown {

    let anniversaryDate: Date
    let anniversaryDays: Int
    /// How many years together the next anniversary marks: 1, 2, 3...
    /// Counted, never an ordinal: NumberFormatter's ordinals read wrongly in
    /// most of the app's languages ("第2記念日", a bare "2" in Russian).
    let anniversaryNumber: Int
    let crown: CrownMilestone?
    let crownDate: Date?
    let crownDays: Int
    /// 0…1 from the previous crown (or the start day) to the next one.
    let crownProgress: Double
    let crownSharesAnniversaryDay: Bool

    init(anchor: RelationshipAnchor, now: Date) {
        let calendar = Calendar.current

        let anniversary = anchor.nextYearlyAnniversary(now: now)
        let daysLeft = anchor.daysUntilNextAnniversary(now: now)
        let years = anchor.yearsCompleted(now: now)
        // On the day itself that year is already complete, so today's
        // anniversary is number `years`; on any other day it is `years + 1`.
        // (The start day is never an anniversary, so this is at least 1.)
        let number = max(1, daysLeft == 0 ? years : years + 1)
        anniversaryDate = anniversary
        anniversaryDays = daysLeft
        anniversaryNumber = number

        let next = CrownMilestone.next(after: anchor.startDate, now: now)
        crown = next
        if let next {
            let date = next.date(anchor: anchor.startDate)
            crownDate = date
            crownDays = next.daysUntil(anchor: anchor.startDate, now: now)
            crownProgress = Self.progress(toward: next, anchor: anchor, now: now, calendar: calendar)
            crownSharesAnniversaryDay = calendar.isDate(date, inSameDayAs: anniversary)
        } else {
            crownDate = nil
            crownDays = 0
            crownProgress = 1
            crownSharesAnniversaryDay = false
        }
    }

    /// Progress from the previous crown's day (or the start day, before the
    /// first crown) to this one. With the ladder in date order, the last
    /// reached crown is the previous one.
    private static func progress(toward milestone: CrownMilestone,
                                 anchor: RelationshipAnchor,
                                 now: Date,
                                 calendar: Calendar) -> Double {
        let target = calendar.startOfDay(for: milestone.date(anchor: anchor.startDate))
        let today = calendar.startOfDay(for: now)
        let previous: Date
        if let last = CrownMilestone.reached(after: anchor.startDate, now: now).last {
            previous = calendar.startOfDay(for: last.date(anchor: anchor.startDate))
        } else {
            previous = JourneyCalendarDay.localDay(ofStored: anchor.startDate, calendar: calendar)
        }
        let total = target.timeIntervalSince(previous)
        guard total > 0 else { return 1 }
        return max(0, min(1, today.timeIntervalSince(previous) / total))
    }
}
