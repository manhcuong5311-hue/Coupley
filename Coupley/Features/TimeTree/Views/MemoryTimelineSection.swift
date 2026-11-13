//
//  MemoryTimelineSection.swift
//  Coupley
//
//  Journey's Timeline: every moment between the two of you in one list, in
//  two groups.
//
//    Sealed for later   Letters nobody has opened yet, both directions, and
//                       Memory Capsules still sealed. Letters ready for you
//                       first, then yours waiting for your partner, then
//                       everything still sealed by the moment it opens. The
//                       first four, then "Show N more". Only this group sits
//                       in a TimelineView, so only its countdowns tick.
//    Memories           Memories (opened capsules included) and opened
//                       letters as keepsakes, newest first: a memory by its
//                       date, a letter by the moment it was opened.
//
//  A rail runs down the leading edge with one node per row: accent for a
//  memory, green for an opened letter, a hollow gold ring for anything still
//  sealed, amber for a letter waiting for you. VoiceOver skips it and reads
//  the rows.
//
//  The section adds nothing itself: the masthead's + is Journey's one Add,
//  and only the empty state carries a button of its own.
//

import Foundation
import SwiftUI

// MARK: - Timeline Section

struct MemoryTimelineSection: View {

    /// One row of the Timeline. Ids carry the kind, so a capsule that opens
    /// leaves "Sealed for later" and arrives in Memories as a different row.
    enum TimelineItem: Identifiable {
        case capsule(TimeMemory)
        case letter(JourneyLetter)
        case memory(TimeMemory)

        var id: String {
            switch self {
            case .capsule(let memory): return "capsule-\(memory.id)"
            case .letter(let letter):  return "letter-\(letter.id)"
            case .memory(let memory):  return "memory-\(memory.id)"
            }
        }
    }

    /// Opened memories, opened capsules included.
    let memories: [TimeMemory]
    /// Capsules still sealed.
    let lockedCapsules: [TimeMemory]
    let letters: JourneyLetterFeed
    let now: Date
    let onSelectMemory: (TimeMemory) -> Void
    let onSelectLetter: (JourneyLetter) -> Void
    let onAddMemory: () -> Void
    let onAddPhoto: (TimeMemory) -> Void
    /// Whether a memory may be edited right now (`TimeTreeViewModel.canEdit`):
    /// no "Add photo" on a copy the device cache blanked.
    let canAddPhoto: (TimeMemory) -> Bool

    @State private var showsAllSealed = false

    /// Half a memory title's first line, so its rail node sits level with
    /// the title at every text size.
    @ScaledMetric(relativeTo: .headline) private var titleHalfLine: CGFloat = 10.5

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Rows "Sealed for later" shows before "Show N more".
    private static let sealedPreviewCount = 4

    init(memories: [TimeMemory],
         lockedCapsules: [TimeMemory],
         letters: JourneyLetterFeed,
         now: Date,
         onSelectMemory: @escaping (TimeMemory) -> Void,
         onSelectLetter: @escaping (JourneyLetter) -> Void,
         onAddMemory: @escaping () -> Void,
         onAddPhoto: @escaping (TimeMemory) -> Void,
         canAddPhoto: @escaping (TimeMemory) -> Bool = { _ in true }) {
        self.memories = memories
        self.lockedCapsules = lockedCapsules
        self.letters = letters
        self.now = now
        self.onSelectMemory = onSelectMemory
        self.onSelectLetter = onSelectLetter
        self.onAddMemory = onAddMemory
        self.onAddPhoto = onAddPhoto
        self.canAddPhoto = canAddPhoto
    }

    var body: some View {
        let sealed = sealedItems
        let remembered = rememberedItems

        VStack(alignment: .leading, spacing: 14) {
            Text("Timeline")
                .font(JourneyFont.title)
                .foregroundStyle(Brand.textPrimary)
                .accessibilityAddTraits(.isHeader)

            if sealed.isEmpty && remembered.isEmpty {
                // Letters may still be on their way: until they have answered
                // once, "Plant your first memory" could flash over a couple
                // whose only moments so far are letters.
                if !letters.isAvailable || letters.hasLoaded {
                    emptyState
                }
            } else {
                VStack(alignment: .leading, spacing: 24) {
                    if !sealed.isEmpty {
                        sealedGroup(sealed)
                    }
                    if !remembered.isEmpty {
                        memoriesGroup(remembered, isLabelled: !sealed.isEmpty)
                    }
                }
                // A letter that opens, a capsule that unlocks or a memory
                // that arrives slides into place instead of jumping.
                .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.85),
                           value: (sealed + remembered).map { $0.id })
            }
        }
    }

    // MARK: - Items

    /// Ready for me, then waiting for the partner, then letters and capsules
    /// still sealed, soonest first.
    private var sealedItems: [TimelineItem] {
        let unopened: [JourneyLetter] = letters.isAvailable ? letters.unopened : []
        let readyForMe: [TimelineItem] = unopened
            .filter { $0.stage == .ready && $0.direction == .toMe }
            .map { TimelineItem.letter($0) }
        let waitingForPartner: [TimelineItem] = unopened
            .filter { $0.stage == .ready && $0.direction == .fromMe }
            .map { TimelineItem.letter($0) }
        let sealedLetters: [Placed] = unopened
            .filter { $0.stage == .sealed }
            .map { Placed(moment: $0.opensAt, rank: 0, item: .letter($0)) }
        let sealedCapsules: [Placed] = lockedCapsules
            .map { Placed(moment: $0.unlockDate ?? .distantFuture, rank: 1, item: .capsule($0)) }
        let stillSealed: [TimelineItem] = (sealedLetters + sealedCapsules)
            .sorted { Placed.soonestFirst($0, $1) }
            .map { $0.item }
        return readyForMe + waitingForPartner + stillSealed
    }

    /// Memories by their date and opened letters by the moment they were
    /// opened, newest first. A capsule still sealed never gets a card here,
    /// whatever list it arrives in.
    private var rememberedItems: [TimelineItem] {
        let keepsakes: [JourneyLetter] = letters.isAvailable ? letters.keepsakes : []
        let placedMemories: [Placed] = memories
            .filter { !$0.isLocked(at: now) }
            .map { Placed(moment: $0.date, rank: 0, item: .memory($0)) }
        let placedLetters: [Placed] = keepsakes
            .map { Placed(moment: $0.timelineDate, rank: 1, item: .letter($0)) }
        return (placedMemories + placedLetters)
            .sorted { Placed.newestFirst($0, $1) }
            .map { $0.item }
    }

    /// An item with the moment it sorts by. `rank` and then the id break
    /// ties, so the order never depends on the sort's stability.
    private struct Placed {
        let moment: Date
        let rank: Int
        let item: TimelineItem

        static func soonestFirst(_ a: Placed, _ b: Placed) -> Bool {
            if a.moment != b.moment { return a.moment < b.moment }
            if a.rank != b.rank { return a.rank < b.rank }
            return a.item.id < b.item.id
        }

        static func newestFirst(_ a: Placed, _ b: Placed) -> Bool {
            if a.moment != b.moment { return a.moment > b.moment }
            if a.rank != b.rank { return a.rank < b.rank }
            return a.item.id < b.item.id
        }
    }

    // MARK: - Groups

    private func sealedGroup(_ items: [TimelineItem]) -> some View {
        let hiddenCount = items.count - Self.sealedPreviewCount
        let shown = showsAllSealed || hiddenCount <= 0
            ? items
            : Array(items.prefix(Self.sealedPreviewCount))

        // The minute tick re-renders this group alone; Memories below has no
        // countdown to move. Each row's phase still comes from the letters
        // view model, whose clock moves only at boundaries.
        return TimelineView(.everyMinute) { context in
            VStack(alignment: .leading, spacing: 10) {
                groupLabel("Sealed for later")

                ForEach(shown) { item in
                    row(item, now: context.date)
                }

                if hiddenCount > 0 {
                    showMoreButton(hiddenCount: hiddenCount)
                }
            }
        }
    }

    private func memoriesGroup(_ items: [TimelineItem], isLabelled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Only worth a label when "Sealed for later" sits above it.
            if isLabelled {
                groupLabel("Memories")
            }

            VStack(alignment: .leading, spacing: 14) {
                ForEach(items) { item in
                    row(item, now: now)
                }
            }
        }
    }

    /// Not an Eyebrow and not uppercase, like the letters hub's own labels.
    private func groupLabel(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(JourneyFont.label)
            .foregroundStyle(Brand.textTertiary)
            .padding(.leading, JourneyTimelineRail.contentInset + 4)
            .accessibilityAddTraits(.isHeader)
    }

    private func showMoreButton(hiddenCount: Int) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .snappy) {
                showsAllSealed.toggle()
            }
        } label: {
            Group {
                if showsAllSealed {
                    Text("Show less")
                } else {
                    Text("Show \(hiddenCount) more")
                }
            }
            .font(JourneyFont.label)
            .foregroundStyle(Brand.accentStart)
            .padding(.vertical, 6)
            .padding(.trailing, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, JourneyTimelineRail.contentInset + 4)
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(_ item: TimelineItem, now: Date) -> some View {
        switch item {
        case .capsule(let memory):
            JourneyTimelineRailRow(node: .sealed) {
                JourneyTimelineCapsuleRow(memory: memory, now: now) {
                    onSelectMemory(memory)
                }
            }

        case .letter(let letter):
            if letter.stage == .opened {
                JourneyTimelineRailRow(node: .keepsake) {
                    JourneyTimelineKeepsakeRow(letter: letter,
                                               partnerName: letters.partnerName,
                                               now: now) {
                        onSelectLetter(letter)
                    }
                }
            } else {
                JourneyTimelineRailRow(node: letter.phase == .readyForMe ? .readyForMe : .sealed) {
                    JourneyTimelineLetterRow(letter: letter,
                                             partnerName: letters.partnerName,
                                             now: now) {
                        onSelectLetter(letter)
                    }
                }
            }

        case .memory(let memory):
            JourneyTimelineRailRow(node: .memory, nodeTop: memoryNodeTop) {
                MemoryCard(memory: memory,
                           now: now,
                           onTap: { onSelectMemory(memory) },
                           onAddPhoto: canAddPhoto(memory) ? { onAddPhoto(memory) } : nil)
            }
        }
    }

    /// Level with the middle of a memory card's first title line.
    private var memoryNodeTop: CGFloat {
        SurfaceTier.card.padding + titleHalfLine - JourneyTimelineRail.nodeSize / 2
    }

    // MARK: - Empty state

    /// Nothing at all yet: no memory, no capsule, no letter either way.
    /// Outlined, because the masthead's + is the screen's one filled accent.
    private var emptyState: some View {
        BrandCard(tier: .card) {
            VStack(spacing: 16) {
                Image(systemName: "sparkles")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Brand.accentStart)
                    .frame(width: 60, height: 60)
                    .wellBackground(in: .card, radius: 30)
                    .accessibilityHidden(true)

                VStack(spacing: 6) {
                    Text("Plant your first memory")
                        .font(JourneyFont.title)
                        .foregroundStyle(Brand.textPrimary)
                    Text("Every memory you add becomes a star around your tree. Your partner sees it instantly.")
                        .font(JourneyFont.body)
                        .foregroundStyle(Brand.textSecondary)
                        .lineSpacing(2)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)

                BrandCTA(title: "Add a memory",
                         icon: "plus",
                         tier: .card,
                         action: onAddMemory)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Previews

#if DEBUG

/// Every date is built from calendar components, never `Date()`, so the
/// canvas shows the same Timeline whichever day it is opened. The viewer is
/// "me" and the partner is Sam.
private enum MemoryTimelinePreview {

    static let me = "me"
    static let partner = "sam"

    /// Friday, Nov 13, 2026 at 10:00 AM, in the canvas's own time zone.
    static let now = date(2026, 11, 13, 10, 0)

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        return Calendar.current.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    static func letter(_ id: String, toMe: Bool, opensAt: Date, openedAt: Date? = nil) -> JourneyLetter {
        let envelope = FutureLetter(firestoreId: nil,
                                    id: id,
                                    fromUserId: toMe ? partner : me,
                                    toUserId: toMe ? me : partner,
                                    opensAt: opensAt,
                                    sealedAt: date(2026, 10, 1),
                                    openedAt: openedAt)
        return JourneyLetter(envelope: envelope,
                             phase: envelope.phase(viewer: me, now: now),
                             isPending: false)
    }

    static let feed = JourneyLetterFeed(
        letters: [
            letter("opened-mine", toMe: false, opensAt: date(2026, 10, 20, 9), openedAt: date(2026, 10, 20, 21, 4)),
            letter("opened-theirs", toMe: true, opensAt: date(2026, 11, 1, 9), openedAt: date(2026, 11, 1, 9, 30)),
            letter("ready", toMe: true, opensAt: date(2026, 11, 13, 9)),
            letter("sealed-theirs", toMe: true, opensAt: date(2026, 12, 25, 9)),
            letter("sealed-mine", toMe: false, opensAt: date(2027, 1, 26, 9))
        ],
        partnerName: "Sam",
        isAvailable: true,
        hasLoaded: true
    )

    static let capsules = [
        TimeMemory(id: "capsule", kind: .custom, title: "Our first winter",
                   date: date(2026, 11, 1), note: "Hidden until it opens.",
                   unlockDate: date(2026, 12, 1, 9), createdBy: me)
    ]

    static let memories = [
        TimeMemory(id: "kiss", kind: .firstKiss, title: "First Kiss", date: date(2026, 5, 1),
                   note: "Under the bridge, in the rain. Neither of us had an umbrella.",
                   emotions: [.nervous, .joyful, .tender], createdBy: partner),
        TimeMemory(id: "opened", kind: .custom, title: "Letter to us in spring", date: date(2026, 4, 30),
                   note: "We said we'd still be laughing at the same jokes.",
                   emotions: [.hopeful], unlockDate: date(2026, 10, 30, 9), createdBy: me),
        TimeMemory(id: "trip", kind: .firstTrip, title: "First Trip", date: date(2026, 4, 27),
                   emotions: [.loved, .joyful, .adventurous], attribution: "from us both", createdBy: me)
    ]

    static func section(memories: [TimeMemory], capsules: [TimeMemory], feed: JourneyLetterFeed) -> some View {
        ScrollView {
            MemoryTimelineSection(memories: memories,
                                  lockedCapsules: capsules,
                                  letters: feed,
                                  now: now,
                                  onSelectMemory: { _ in },
                                  onSelectLetter: { _ in },
                                  onAddMemory: {},
                                  onAddPhoto: { _ in })
                .padding(.horizontal, Brand.Space.gutter)
                .padding(.vertical, 24)
        }
        .background(Brand.bgGradient.ignoresSafeArea())
    }
}

#Preview("Timeline") {
    MemoryTimelinePreview.section(memories: MemoryTimelinePreview.memories,
                                  capsules: MemoryTimelinePreview.capsules,
                                  feed: MemoryTimelinePreview.feed)
}

#Preview("Timeline · empty") {
    MemoryTimelinePreview.section(memories: [], capsules: [], feed: .unavailable(partnerName: "Sam"))
}

#endif
