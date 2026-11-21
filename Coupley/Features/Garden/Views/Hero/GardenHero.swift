//
//  GardenHero.swift
//  Coupley
//
//  Journey's garden hero (spec B3, C1): the full-bleed scene band inside the
//  hero card (BrandCard .hero, insetsContent: false), one page per planted
//  tree, the place and garden chips, the page dots, and the caption under
//  the band (day count, stage, status line, the note, the CTA row). Without
//  a start date it is the planting hero (B3.2–B3.4); while loading or
//  unavailable it shows text only, never a CTA (B2).
//
//  Everything garden-level (the status line, the water action and its
//  title, the one filled control) comes from GardenViewModel.hero and never
//  depends on the selected page, so swiping between a just-planted tree and
//  a thirsty Our tree moves no control and no fill (A6). Only the caption's
//  day count, title line and meta follow the page.
//
//  The pager animates only its selected page, and only while the hero is
//  in Journey's viewport, Journey is the shown tab, nothing covers it (a
//  Journey sheet, the letters sheet, the crown or the planting ceremony),
//  the app is active and neither Low Power Mode nor Reduce Motion is on
//  (GardenMotionGate). Effects still play in Low Power Mode. The same "on
//  screen" (without the last two) is what the view model is told
//  (`resumeTicking` / `pauseTicking`): it ticks, replays the partner's
//  watering and starts a due ceremony only while the hero can be seen.
//

import Foundation
import SwiftUI
import UIKit
import Combine

// MARK: - Journey's side of the hero

/// What Journey knows that the garden does not: Our tree's day count and
/// stage (from the start date), its memory stars and its letters.
struct GardenHeroJourney {
    /// The stored start date (config), from Journey's own listener.
    var startDate: Date?
    var daysTogether: Int?
    var stage: TreeGrowthStage?
    var memoryCount: Int
    var letters: JourneyLetterFeed
    /// The scroll viewport is under 700 pt: the band is 176 pt and the
    /// note takes one line.
    var isCompact: Bool
    /// A note waits in the water-note sheet (a dot on the ✎ button).
    var noteDrafted: Bool

    /// The garden alone (the lab): Our tree's count comes from the
    /// garden's own start date.
    static var standalone: GardenHeroJourney {
        GardenHeroJourney(startDate: nil, daysTogether: nil, stage: nil, memoryCount: 0,
                          letters: .unavailable(), isCompact: false, noteDrafted: false)
    }
}

/// What the hero hands back to Journey.
struct GardenHeroActions {
    /// Presents one of Journey's garden sheets.
    var onOpenSheet: (GardenSheetRoute) -> Void = { _ in }
    /// The water control (Journey adds a drafted note, if any).
    var onWater: () -> Void = {}
    /// "Since 26 Jan 2026 · Edit": the start-date sheet in suggest mode.
    var onEditStartDate: () -> Void = {}
    /// The stage button: the tree guide for this page's tree. `days` counts
    /// from its growth start; a place tree (`isPlaceTree`) grows from its
    /// planting day and carries no stars, letters or crowns.
    var onShowTreeGuide: (_ stage: TreeGrowthStage, _ days: Int, _ isPlaceTree: Bool) -> Void = { _, _, _ in }
    /// A letter tapped on Our tree.
    var onOpenLetter: (FutureLetter) -> Void = { _ in }
    /// "Reply in Chat" on the partner's note.
    var onReplyInChat: () -> Void = {}
    /// "Tell Sam": Journey confirms, then sends the chat line.
    var onTellPartner: () -> Void = {}
}

// MARK: - Hero

struct GardenHero: View {

    @ObservedObject var garden: GardenViewModel
    /// Something covers Journey: one of its sheets, ContentView's letters
    /// sheet, or a full-screen overlay (the crown celebration, the planting
    /// ceremony). Presenting any of them fires no onDisappear, so Journey
    /// says it here; it is the motion gate's `journeySheetPresented`.
    let isCovered: Bool
    let journey: GardenHeroJourney
    let actions: GardenHeroActions

    init(garden: GardenViewModel, isCovered: Bool,
         journey: GardenHeroJourney = .standalone, actions: GardenHeroActions = GardenHeroActions()) {
        self.garden = garden
        self.isCovered = isCovered
        self.journey = journey
        self.actions = actions
    }

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.displayScale) private var displayScale

    // Motion gate inputs
    @State private var heroVisible = true
    @State private var tabShown = false
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    // Pager
    @State private var scrolledSlot: GardenSlot?
    @State private var isSwiping = false
    @State private var bandSize: CGSize = .zero

    // Watering
    /// A replay the user tapped away.
    @State private var skippedPlaybackId: String?
    /// The page that played the latest effect (its neighbours show an
    /// after-glow when swiped to within 10 s).
    @State private var playbackSlot: GardenSlot?
    @State private var afterGlowStarts: [GardenSlot: TimeInterval] = [:]

    // Small transient states
    @State private var revealed = true
    @State private var showNoteActions = false
    @State private var confirmTakeBack = false
    @State private var showsEditUnavailable = false
    @State private var editUnavailableTask: Task<Void, Never>?

    private static let revealSeenKey = GardenDefaultsKey.prefix + "heroRevealSeen"

    var body: some View {
        let hero = garden.hero
        let pages = displayedPages(hero)

        // One stable container, so its appear and disappear are the hero's
        // own (switching from loading to the garden is not a disappearance).
        VStack(alignment: .leading, spacing: 0) {
            if let empty = hero.empty {
                plantingHero(empty, hero: hero)
            } else if !pages.isEmpty {
                gardenCard(hero: hero, pages: pages)
            } else {
                loadingHero
            }
        }
        .onAppear {
            tabShown = true
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            syncOnScreen()
            beginRevealIfFirst()
        }
        .onDisappear {
            tabShown = false
            syncOnScreen()
        }
        // Scrolled away, covered or in the background, the hero stops its
        // minute tick and the view model holds back a replay (and a due
        // ceremony) until it is seen.
        .onScrollVisibilityChange(threshold: 0.1) { visible in
            heroVisible = visible
            syncOnScreen()
        }
        .onChange(of: isCovered) { _, _ in
            syncOnScreen()
        }
        .onChange(of: scenePhase) { _, _ in
            syncOnScreen()
        }
        .onChange(of: garden.availability.allowsWrites) { _, allowsWrites in
            if allowsWrites { hideEditUnavailable() }
        }
        .onReceive(NotificationCenter.default
            .publisher(for: .NSProcessInfoPowerStateDidChange)
            .receive(on: DispatchQueue.main)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .onChange(of: garden.playback?.id) { _, _ in
            playbackStarted()
        }
        .onChange(of: garden.afterWateringLine) { _, line in
            if let line { AccessibilityNotification.Announcement(line).post() }
        }
    }

    // MARK: - Pages

    /// The garden's pages, or Our tree drawn from Journey's start date while
    /// the garden has not answered yet (an existing couple's first paint).
    private func displayedPages(_ hero: GardenHeroModel) -> [GardenPageModel] {
        if !hero.pages.isEmpty { return hero.pages }
        guard hero.empty == nil, ourStartDate != nil else { return [] }
        // The same key as the view model's unrecorded Our tree, so the ambient
        // life does not jump when the garden answers.
        return [.meadow(key: GardenTree.unrecordedOurTree(startDate: .distantPast).key, now: garden.now)]
    }

    private func selectedSlot(in pages: [GardenPageModel], hero: GardenHeroModel) -> GardenSlot {
        pages.contains { $0.slot == hero.selectedSlot } ? hero.selectedSlot : (pages.first?.slot ?? .our)
    }

    private var ourStartDate: Date? { journey.startDate ?? garden.anchor.startDate }

    private var ourDays: Int {
        if let days = journey.daysTogether { return days }
        return ourStartDate.map { GardenGrowth.days(since: $0, now: garden.now) } ?? 0
    }

    private var ourStage: TreeGrowthStage { journey.stage ?? .from(daysTogether: ourDays) }

    private var isStacked: Bool { dynamicTypeSize.isAccessibilitySize }

    private var bandHeight: CGFloat {
        if isStacked { return 168 }
        return journey.isCompact ? 176 : 208
    }

    private var cacheScale: Int { min(2, max(1, Int(displayScale.rounded()))) }

    /// What a page draws on its knoll.
    private func tree(for page: GardenPageModel) -> GardenPageTree {
        guard page.slot.isOurTree else {
            return .placeTree(growingSince: page.growthStart ?? garden.tree(page.slot)?.plantedAt, now: garden.now)
        }
        let stage = ourStage
        // No more blossoms than the tree has places for at this stage, so
        // none stack (as TimeTreeHeader does).
        let ornaments: [JourneyTreeOrnament] = journey.letters.isAvailable
            ? journey.letters.treeOrnaments(maxEnvelopesPerSide: isStacked ? 3 : 2,
                                            maxBlossoms: min(isStacked ? 8 : 6,
                                                             RelationshipTreeCanvas.blossomCapacity(at: stage)))
            : []
        let letters = journey.letters
        let onOpenLetter = actions.onOpenLetter
        return GardenPageTree(stage: stage, daysTogether: ourDays, memoryCount: journey.memoryCount,
                              crownActive: stage.showsAmbientCrown, ornaments: ornaments,
                              onSelectOrnament: { id in
                                  if let letter = letters.letter(id: id) { onOpenLetter(letter.envelope) }
                              })
    }

    private func gate(isSelected: Bool) -> GardenMotionGate {
        GardenMotionGate(isSelectedPage: isSelected, heroVisible: heroVisible, tabShown: tabShown,
                         journeySheetPresented: isCovered, sceneActive: scenePhase == .active,
                         lowPower: lowPower, reduceMotion: reduceMotion)
    }

    /// The hero can be seen: in Journey's viewport, Journey shown, nothing
    /// over it, the app active (the motion gate's `isOnScreen` for the
    /// selected page).
    private var isOnScreen: Bool {
        heroVisible && tabShown && !isCovered && scenePhase == .active
    }

    /// Tells the view model whether the hero can be seen, from every input
    /// of `isOnScreen`. It ticks only then, and holds a partner's replay
    /// (its haptics too) and a due ceremony until then, so neither is used
    /// up unseen under a sheet or in the background; `resumeTicking`
    /// reconciles, so what it held starts as soon as the hero is back.
    private func syncOnScreen() {
        if isOnScreen {
            garden.resumeTicking()
        } else {
            garden.pauseTicking()
            // Covered or gone: the next interaction has happened.
            hideEditUnavailable()
        }
    }

    /// The selected page's effect, unless the user tapped a replay away.
    private var visiblePlayback: GardenEffectPlayback? {
        guard let playback = garden.playback, playback.id != skippedPlaybackId else { return nil }
        return playback
    }

    // MARK: - The garden card

    private func gardenCard(hero: GardenHeroModel, pages: [GardenPageModel]) -> some View {
        let selected = selectedSlot(in: pages, hero: hero)
        let page = pages.first { $0.slot == selected } ?? pages[0]

        return BrandCard(tier: .hero, insetsContent: false) {
            VStack(alignment: .leading, spacing: 0) {
                band(hero: hero, pages: pages, selected: selected)
                    .frame(height: bandHeight)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: Brand.heroCornerRadius,
                                                      topTrailingRadius: Brand.heroCornerRadius,
                                                      style: Brand.cornerStyle))

                caption(hero: hero, page: page)
                    .padding(.horizontal, 22)
                    .padding(.top, 16)
                    .padding(.bottom, 22)
                    .animation(.easeInOut(duration: 0.2), value: selected)
            }
        }
        .onAppear {
            if scrolledSlot == nil { scrolledSlot = selected }
        }
        .onChange(of: scrolledSlot) { _, slot in
            if let slot, slot != garden.selectedSlot { garden.select(slot) }
            noteAfterGlow(on: slot)
        }
        .onChange(of: garden.selectedSlot) { _, slot in
            hideEditUnavailable()
            guard scrolledSlot != slot else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { scrolledSlot = slot }
        }
        .task(id: PrewarmRequest(selected: selected, isSwiping: isSwiping, band: bandSize)) {
            // Once the pager has rested 0.3 s, its neighbours' layers load
            // at low priority, so the next swipe finds them in memory.
            guard !isSwiping, bandSize != .zero else { return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            prewarmNeighbours(of: selected, in: pages)
        }
        .confirmationDialog(noteDialogTitle(hero.status?.note), isPresented: $showNoteActions,
                            titleVisibility: .visible) {
            noteActions(hero: hero)
        }
    }

    private struct PrewarmRequest: Equatable {
        let selected: GardenSlot
        let isSwiping: Bool
        let band: CGSize
    }

    private func prewarmNeighbours(of selected: GardenSlot, in pages: [GardenPageModel]) {
        guard let index = pages.firstIndex(where: { $0.slot == selected }) else { return }
        let neighbours = [index - 1, index + 1].filter { pages.indices.contains($0) }.map { pages[$0] }
        let keys = neighbours.flatMap {
            GardenScenePage.backdropKeys(scene: $0.look.scene, environment: $0.environment,
                                         band: bandSize, scale: cacheScale)
        }
        GardenBackdropCache.shared.prewarm(keys)
    }

    // MARK: Band

    private func band(hero: GardenHeroModel, pages: [GardenPageModel], selected: GardenSlot) -> some View {
        let page = pages.first { $0.slot == selected } ?? pages[0]
        return ZStack {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(pages) { item in
                        let isSelected = item.slot == selected
                        GardenScenePage(page: item,
                                        gate: gate(isSelected: isSelected),
                                        playback: isSelected ? visiblePlayback : nil,
                                        subject: .tree(tree(for: item)),
                                        isSwiping: isSwiping && pages.count > 1,
                                        revealed: revealed,
                                        afterGlowStart: afterGlowStarts[item.slot],
                                        onSelectNoteTag: { openNote() })
                            .containerRelativeFrame(.horizontal)
                            .id(item.slot)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $scrolledSlot)
            .scrollDisabled(pages.count < 2)
            .onScrollPhaseChange { _, phase in
                // One page cannot be swiped: a programmatic scroll on a
                // disabled pager may never report idle again.
                isSwiping = phase != .idle && pages.count > 1
                // Nothing renders while a swipe is in flight (C11): the
                // neighbours' pre-warm stops after the key it is on, and
                // is queued again once the pager has rested 0.3 s.
                if isSwiping { GardenBackdropCache.shared.prewarm([]) }
            }
            // A page set that changes under the pager (a tree planted or
            // rested, or a cached tree the server no longer has) can end a
            // scroll with no idle phase: a "swiping" left on would keep every
            // page from loading its layers, leaving the band without them.
            .onChange(of: pages.map(\.slot)) { _, _ in
                isSwiping = false
            }

            bandOverlays(hero: hero, pages: pages, page: page)
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            guard size != bandSize, size.width > 0 else { return }
            bandSize = size
            GardenBackdropCache.shared.configure(band: size, scale: cacheScale)
        }
        // A replay can be tapped away (the view model marks it seen itself).
        .simultaneousGesture(TapGesture().onEnded {
            guard let playback = visiblePlayback, playback.isReplay else { return }
            skippedPlaybackId = playback.id
        })
        // VoiceOver reads the band as the one element drawn over it, so the
        // pager underneath never changes identity for it.
        .accessibilityHidden(true)
        .overlay {
            bandElement(hero: hero, pages: pages, page: page, selected: selected)
        }
    }

    /// The band for VoiceOver (C10): one element with a stable label and the
    /// shown tree as its value, which VoiceOver speaks again after every
    /// adjust. Adjustable only while there is another tree to move to.
    @ViewBuilder
    private func bandElement(hero: GardenHeroModel, pages: [GardenPageModel], page: GardenPageModel,
                             selected: GardenSlot) -> some View {
        let element = Color.clear
            .accessibilityElement()
            .accessibilityLabel(Text(LocalizedStringResource(
                "garden.hero.band", defaultValue: "Your garden",
                comment: "VoiceOver label of the garden picture at the top of Journey, read before the description of the tree it shows")))
            .accessibilityValue(bandSummary(hero: hero, pages: pages, page: page))
            .accessibilityAddTraits(.isImage)
            .accessibilityActions {
                if page.place != nil {
                    Button {
                        actions.onOpenSheet(.postcard(page.slot))
                    } label: {
                        Text("Show the place", comment: "VoiceOver action on the garden picture: opens the tree's postcard")
                    }
                } else if page.placeChipIsAction {
                    Button {
                        actions.onOpenSheet(.plant(.changeTree(page.slot)))
                    } label: {
                        Text(GardenCopy.addAPlace)
                    }
                }
                Button {
                    actions.onOpenSheet(.postcard(page.slot))
                } label: {
                    Text("Change look", comment: "VoiceOver action on the garden picture: opens the tree's card to change its scene and species")
                }
                Button {
                    actions.onOpenSheet(.garden)
                } label: {
                    Text("Show your garden", comment: "VoiceOver action on the garden picture: opens the Garden sheet")
                }
            }
            // Touches go to the pager and the chips underneath.
            .allowsHitTesting(false)

        if pages.count > 1 {
            element
                .accessibilityHint(Text("Swipe up or down to visit your other trees.",
                                        comment: "VoiceOver hint on the garden picture when there are several trees"))
                .accessibilityAdjustableAction { direction in
                    movePager(direction, pages: pages, selected: selected)
                }
        } else {
            element
        }
    }

    private func movePager(_ direction: AccessibilityAdjustmentDirection, pages: [GardenPageModel], selected: GardenSlot) {
        guard let index = pages.firstIndex(where: { $0.slot == selected }) else { return }
        let next: Int
        switch direction {
        case .increment: next = index + 1
        case .decrement: next = index - 1
        @unknown default: return
        }
        guard pages.indices.contains(next) else { return }
        garden.select(pages[next].slot)
    }

    @ViewBuilder
    private func bandOverlays(hero: GardenHeroModel, pages: [GardenPageModel], page: GardenPageModel) -> some View {
        ZStack {
            if !isStacked, let chip = page.placeChip {
                placeChip(chip, page: page)
                    .frame(maxWidth: max(0, bandSize.width * 0.44), alignment: .leading)
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            gardenChip(hero: hero)
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            if pages.count > 1 {
                pageDots(pages: pages, selected: page.slot)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
    }

    // MARK: Chips

    private func placeChip(_ text: String, page: GardenPageModel) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if page.placeChipIsAction {
                actions.onOpenSheet(.plant(.changeTree(page.slot)))
            } else {
                actions.onOpenSheet(.postcard(page.slot))
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "mappin")
                    .font(JourneyFont.meta)
                Text(text)
                    .font(JourneyFont.caption)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            .foregroundStyle(Brand.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(chipBackground(Capsule()))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func gardenChip(hero: GardenHeroModel) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            actions.onOpenSheet(.garden)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "tree.fill")
                    .font(.system(size: 14, weight: .semibold))
                if hero.treeCount > 1 {
                    Text(hero.treeCount, format: .number)
                        .font(JourneyFont.caption)
                        .monospacedDigit()
                }
            }
            .foregroundStyle(Brand.textPrimary)
            .padding(.horizontal, hero.treeCount > 1 ? 10 : 0)
            .frame(minWidth: 36, minHeight: 36)
            .background(chipBackground(Capsule()))
            .overlay(alignment: .topTrailing) {
                if hero.requestWaitingForMe {
                    Circle()
                        .fill(Self.amber)
                        .frame(width: 7, height: 7)
                        .offset(x: -2, y: 2)
                }
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Frosted, with a hairline; solid under Increase Contrast.
    private func chipBackground<S: InsettableShape>(_ shape: S) -> some View {
        ZStack {
            if contrast == .increased {
                shape.fill(Brand.surfaceLight)
            } else {
                shape.fill(.regularMaterial)
                shape.strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
            }
        }
    }

    private static let amber = Color(red: 1.0, green: 0.72, blue: 0.22)

    // MARK: Dots

    private func pageDots(pages: [GardenPageModel], selected: GardenSlot) -> some View {
        let waiting = slotsWithRequestsForMe
        typealias Dot = GardenDotRipple.Metrics
        return HStack(spacing: Dot.spacing) {
            ForEach(pages) { item in
                let isSelected = item.slot == selected
                Capsule()
                    .fill(Color.white.opacity(isSelected ? 0.95 : 0.55))
                    .frame(width: isSelected ? Dot.selectedWidth : Dot.dotSize, height: Dot.dotSize)
                    .overlay {
                        if waiting.contains(item.slot) {
                            Circle()
                                .strokeBorder(Self.amber, lineWidth: 1.5)
                                .frame(width: 11, height: 11)
                        }
                    }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(chipBackground(Capsule()))
        .overlay {
            if let playback = visiblePlayback, !playback.isReplay, !reduceMotion {
                GardenDotRipple(dotCount: pages.count, startTime: playback.startTime,
                                selectedIndex: pages.firstIndex { $0.slot == selected })
                    .allowsHitTesting(false)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: selected)
    }

    /// Trees with a change or rest request waiting for me (a ring on their dot).
    private var slotsWithRequestsForMe: Set<GardenSlot> {
        Set(garden.requests.compactMap { request -> GardenSlot? in
            guard !request.isMine, request.kind == .change || request.kind == .rest else { return nil }
            return garden.proposal(id: request.id)?.targetSlot
        })
    }

    // MARK: - Caption

    @ViewBuilder
    private func caption(hero: GardenHeroModel, page: GardenPageModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if isStacked, let chip = page.placeChip {
                placeChip(chip, page: page)
            }
            dayRow(page: page)
            if let status = hero.status {
                statusWell(status, hero: hero)
            }
            if let line = garden.afterWateringLine {
                Text(line)
                    .font(JourneyFont.body)
                    .foregroundStyle(Brand.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            } else {
                waterRow(hero: hero)
            }
            metaRow(page: page)
        }
        .animation(.easeInOut(duration: 0.2), value: garden.afterWateringLine)
    }

    // MARK: Row 1: the day count and the stage

    @ViewBuilder
    private func dayRow(page: GardenPageModel) -> some View {
        let isOurTree = page.slot.isOurTree
        let tree = self.tree(for: page)
        let days = tree.daysTogether
        // The caption agrees with the count above it (Russian: 292 дня, 295
        // дней): a plural key that carries the count, with the number taken
        // out on screen (as TimeTreeHeader does) and read whole by VoiceOver.
        // Our tree reuses TimeTreeHeader's entry, comment and all.
        let counted = isOurTree
            ? String(localized: "\(days) days together",
                     comment: "Journey hero: caption under the big day count. The number is shown large above it and the app removes it here, so keep %lld and write each plural form to read naturally without the number ('%lld days together' shows as 'days together').")
            : String(localized: "\(days) days since you planted it",
                     comment: "Garden hero on Journey: caption under a place tree's big day count; the tree grows from the day the couple planted it. %lld is the number of days since then. The number is shown large above it and the app removes it here, so keep %lld and write each plural form to read naturally without the number ('%lld days since you planted it' shows as 'days since you planted it'). VoiceOver reads the whole phrase, number included.")

        VStack(alignment: .leading, spacing: 6) {
            if !isOurTree {
                placeTreeTitle(page: page)
            }
            let count = VStack(alignment: .leading, spacing: 2) {
                Text(days, format: .number)
                    .font(JourneyFont.number)
                    .foregroundStyle(Brand.textPrimary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(verbatim: CountedCaption.removingCount(from: counted))
                    .font(JourneyFont.label)
                    .foregroundStyle(Brand.textSecondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(counted)

            if isStacked {
                count
                stageButton(stage: tree.stage, days: days, isPlaceTree: !isOurTree)
            } else {
                HStack(alignment: .lastTextBaseline, spacing: 12) {
                    count
                    Spacer(minLength: 8)
                    stageButton(stage: tree.stage, days: days, isPlaceTree: !isOurTree)
                }
            }
        }
    }

    /// A place tree's title, with the moment's day it remembers (0.0 #3):
    /// "Our first trip · 12 March 2023".
    private func placeTreeTitle(page: GardenPageModel) -> some View {
        let text = garden.tree(page.slot)?.momentDay
            .map { GardenCopy.titleWithMoment(title: page.title, storedMomentDay: $0) } ?? page.title
        return Text(text)
            .font(JourneyFont.label)
            .foregroundStyle(Brand.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private func stageButton(stage: TreeGrowthStage, days: Int, isPlaceTree: Bool) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            actions.onShowTreeGuide(stage, days, isPlaceTree)
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
    }

    // MARK: Row 2: the status well

    private func statusWell(_ status: GardenStatusModel, hero: GardenHeroModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "drop.fill")
                    .font(JourneyFont.meta)
                    .foregroundStyle(Self.water)
                Text(status.line)
                    .font(JourneyFont.label)
                    // Accent-tinted while the partner's watering is news (2 s).
                    .foregroundStyle(status.isNews ? Brand.accentStart : Brand.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let note = status.note {
                Button {
                    openNote()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(note.text)
                            .font(JourneyFont.body)
                            .foregroundStyle(Brand.textPrimary)
                            .lineLimit(journey.isCompact ? 1 : 2)
                        Text(note.attribution)
                            .font(JourneyFont.meta)
                            .foregroundStyle(Brand.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wellBackground(in: .hero)
        .contentShape(Rectangle())
        .onTapGesture {
            openJournal()
        }
        .animation(.easeInOut(duration: 0.3), value: status.isNews)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(statusLabel(status))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text("Opens the garden journal.", comment: "VoiceOver hint on the garden status line"))
        .accessibilityAction {
            openJournal()
        }
        .accessibilityActions {
            if status.note != nil {
                if hero.waterAction == .waterBack {
                    Button {
                        actions.onWater()
                    } label: {
                        Text("Water back", comment: "Garden: water the garden in answer to the partner's watering")
                    }
                }
                Button {
                    actions.onReplyInChat()
                } label: {
                    Text("Reply in Chat", comment: "Garden: switches to the Chat tab to answer the partner's note")
                }
            }
        }
    }

    /// "Sam watered today at 9:14 PM. Note from Sam: Thinking of our first coffee."
    private func statusLabel(_ status: GardenStatusModel) -> String {
        var sentences = [Self.sentence(status.line)]
        if let note = status.note {
            let partner = garden.partnerName
            let text = note.text
            sentences.append(String(localized: "Note from \(partner): \(text)",
                                    comment: "VoiceOver, garden status: the partner's watering note. First %@ is the partner's name, second the note."))
        }
        return sentences.joined(separator: " ")
    }

    private func noteDialogTitle(_ note: GardenNoteModel?) -> Text {
        guard let note else { return Text(verbatim: "") }
        return Text(note.text)
    }

    /// The partner's note was tapped (in the well or on the tree): it is
    /// read, and Water back / Reply in Chat are offered.
    private func openNote() {
        garden.markWateringSeen()
        showNoteActions = true
    }

    /// The status well opens the journal (which reads the partner's note).
    private func openJournal() {
        actions.onOpenSheet(.journal)
    }

    @ViewBuilder
    private func noteActions(hero: GardenHeroModel) -> some View {
        if hero.waterAction.isTheJob || hero.waterAction == .waterOptional {
            Button {
                actions.onWater()
            } label: {
                Text("Water back", comment: "Garden: water the garden in answer to the partner's watering")
            }
        }
        Button {
            actions.onReplyInChat()
        } label: {
            Text("Reply in Chat", comment: "Garden: switches to the Chat tab to answer the partner's note")
        }
        Button(role: .cancel) {} label: {
            Text("Cancel", comment: "Button: close the menu without doing anything")
        }
    }

    // MARK: Row 3: the water control and the note

    @ViewBuilder
    private func waterRow(hero: GardenHeroModel) -> some View {
        switch hero.waterAction {
        case .firstWater, .waterBack, .waterDue:
            waterControls(hero: hero, filled: true)
        case .waterOptional:
            waterControls(hero: hero, filled: false)
        case .locked, .none:
            EmptyView()
        }
    }

    @ViewBuilder
    private func waterControls(hero: GardenHeroModel, filled: Bool) -> some View {
        let title = hero.waterTitle ?? GardenCopy.waterTitle(.waterOptional, treeCount: hero.treeCount) ?? ""
        let cta = BrandCTA(title: title, icon: "drop.fill", tier: filled ? .hero : .card,
                           isBusy: garden.isWatering, action: actions.onWater)
            .contextMenu {
                Button {
                    actions.onOpenSheet(.waterNote)
                } label: {
                    Label {
                        Text("Water with a note", comment: "Garden: water and leave a note for the partner")
                    } icon: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .accessibilityValue(waterValue)
            .accessibilityHint(garden.partner.canGarden == false
                               ? Text("Waters every tree.", comment: "VoiceOver hint on the water control when the partner's app is out of date")
                               : Text("Waters every tree and lets \(garden.partnerName) see it.",
                                      comment: "VoiceOver hint on the water control. %@ is the partner's name."))
            .accessibilityAction(named: Text("Water with a note", comment: "Garden: water and leave a note for the partner")) {
                actions.onOpenSheet(.waterNote)
            }

        if isStacked {
            VStack(spacing: 10) {
                cta
                BrandCTA(title: GardenCopy.addNote, icon: "square.and.pencil", tier: .card) {
                    actions.onOpenSheet(.waterNote)
                }
            }
        } else {
            HStack(spacing: 10) {
                cta
                noteButton(side: filled ? 52 : 44)
            }
        }
    }

    private func noteButton(side: CGFloat) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            actions.onOpenSheet(.waterNote)
        } label: {
            let shape = RoundedRectangle(cornerRadius: Brand.buttonCornerRadius, style: Brand.cornerStyle)
            Image(systemName: "square.and.pencil")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Brand.accentStart)
                .frame(width: side, height: side)
                .background(shape.fill(Brand.surfaceLight))
                .overlay(shape.strokeBorder(Brand.accentStart.opacity(0.45), lineWidth: 1))
                .overlay(alignment: .topTrailing) {
                    if journey.noteDrafted {
                        Circle()
                            .fill(Brand.accentStart)
                            .frame(width: 8, height: 8)
                            .offset(x: -6, y: 6)
                    }
                }
        }
        .buttonStyle(BouncyButtonStyle(scale: 0.94))
        .accessibilityLabel(GardenCopy.addNote)
        .accessibilityValue(journey.noteDrafted
                            ? Text("A note is ready", comment: "VoiceOver value on Add a note when a note has been written but not sent")
                            : Text(verbatim: ""))
    }

    /// "A little thirsty. Last drink Sun at 9:14 PM."
    private var waterValue: String {
        let last = garden.waterings.waterings.compactMap(\.wateredAt).max()
        let state = GardenWaterState.garden(lastWateredAt: last, now: garden.now).spoken
        guard let last else { return state }
        let moment = FutureLetterClock.moment(last, now: garden.now)
        return String(localized: "\(state). Last drink \(moment).",
                      comment: "VoiceOver value of the garden's water control. First %@ is the water state such as 'A little thirsty', second a moment such as 'Sun at 9:14 PM'.")
    }

    // MARK: Row 4: meta

    @ViewBuilder
    private func metaRow(page: GardenPageModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if page.slot.isOurTree {
                if let start = ourStartDate { startDateMeta(start) }
            } else {
                plantedMeta(page: page)
            }
            if showsEditUnavailable {
                Text(GardenCopy.startDateChangeUnavailable)
                    .font(JourneyFont.meta)
                    .foregroundStyle(Brand.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showsEditUnavailable)
    }

    private func startDateMeta(_ start: Date) -> some View {
        let spokenSince = GardenCopy.longDay(stored: start)
        // A suggestion waits, mine or the partner's: there is one at a time
        // (its fixed id), so Edit opens it, to edit mine or answer theirs,
        // instead of a new one that could only be refused.
        let suggested = garden.requests.contains { $0.kind == .startDate }
        let sinceText = Text(GardenCopy.since(storedStartDay: start))
        let link = Text(suggested ? GardenCopy.newDateSuggested : GardenCopy.editStartDate)

        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if suggested {
                actions.onOpenSheet(.seed(id: GardenDocID.startDate))
            } else if garden.availability.allowsWrites {
                actions.onEditStartDate()
            } else {
                showEditUnavailable()
            }
        } label: {
            metaLabel(sinceText, link: link.foregroundStyle(Brand.accentStart))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(suggested
                            ? Text("Started \(spokenSince). A new date is suggested.",
                                   comment: "VoiceOver: the start date while a suggested new date waits, mine or the partner's; it opens the suggestion. %@ is a date such as '26 January 2026'.")
                            : Text("Started \(spokenSince). Edit start date",
                                   comment: "VoiceOver: the start date button. %@ is a date such as '26 January 2026'."))
    }

    @ViewBuilder
    private func plantedMeta(page: GardenPageModel) -> some View {
        if let planted = garden.tree(page.slot)?.plantedAt ?? page.growthStart {
            let spokenDay = planted.formatted(.dateTime.day().month(.wide).year())
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                actions.onOpenSheet(.postcard(page.slot))
            } label: {
                metaLabel(Text(GardenCopy.plantedTogether(at: planted)),
                          link: Text(GardenCopy.details).foregroundStyle(Brand.accentStart))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Planted together on \(spokenDay). Details",
                                     comment: "VoiceOver: a place tree's planting day, which opens its postcard. %@ is a date such as '14 November 2026'."))
        }
    }

    /// "Since 26 Jan 2026 · Edit" on one line when it fits, else the link
    /// on its own line (as TimeTreeHeader does).
    private func metaLabel(_ text: Text, link: Text) -> some View {
        ViewThatFits(in: .horizontal) {
            (text + Text(verbatim: " · ") + link)
                .lineLimit(1)
            VStack(alignment: .leading, spacing: 2) {
                text.fixedSize(horizontal: false, vertical: true)
                link
            }
        }
        .font(JourneyFont.meta)
        .foregroundStyle(Brand.textSecondary)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    /// "Changing the start date isn't available right now." under the meta
    /// row, said aloud too (VoiceOver's focus stays on the button). It goes
    /// after 4 s; with VoiceOver on it stays until the next interaction (the
    /// page moves, something covers the hero, the hero goes, the garden can
    /// take the change again), so it can still be found.
    private func showEditUnavailable() {
        showsEditUnavailable = true
        AccessibilityNotification.Announcement(GardenCopy.startDateChangeUnavailable).post()
        editUnavailableTask?.cancel()
        editUnavailableTask = nil
        guard !UIAccessibility.isVoiceOverRunning else { return }
        editUnavailableTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            showsEditUnavailable = false
        }
    }

    private func hideEditUnavailable() {
        editUnavailableTask?.cancel()
        editUnavailableTask = nil
        if showsEditUnavailable { showsEditUnavailable = false }
    }

    // MARK: - The planting hero (no start date)

    private func plantingHero(_ empty: GardenEmptyHero, hero: GardenHeroModel) -> some View {
        let mound: GardenMound
        switch empty {
        case .plantSeed:      mound = .bare
        case .mySeedWaiting:  mound = .stake
        case .partnersSeed:   mound = .packet
        }
        let page = GardenPageModel.meadow(key: "planting", now: garden.now)

        return BrandCard(tier: .hero, insetsContent: false) {
            VStack(alignment: .leading, spacing: 0) {
                GardenScenePage(page: page, gate: gate(isSelected: true), subject: .mound(mound), revealed: revealed)
                    .frame(height: bandHeight)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: Brand.heroCornerRadius,
                                                      topTrailingRadius: Brand.heroCornerRadius,
                                                      style: Brand.cornerStyle))
                    .accessibilityHidden(true)

                plantingCaption(empty, availability: hero.availability)
                    .padding(.horizontal, 22)
                    .padding(.top, 16)
                    .padding(.bottom, 22)
            }
        }
        .confirmationDialog(Text("Take this seed back?", comment: "Garden: confirmation before withdrawing my seed for our tree"),
                            isPresented: $confirmTakeBack, titleVisibility: .visible) {
            Button(role: .destructive) {
                Task { _ = await garden.takeBack(GardenDocID.seedOurTree) }
            } label: {
                Text(GardenCopy.takeItBack)
            }
            Button(role: .cancel) {} label: {
                Text("Cancel", comment: "Button: close the menu without doing anything")
            }
        }
    }

    @ViewBuilder
    private func plantingCaption(_ empty: GardenEmptyHero, availability: GardenAvailability) -> some View {
        let partner = garden.partnerName
        VStack(alignment: .leading, spacing: 12) {
            if !GardenPrimaryAction.emptyHeroShowsButton(availability: availability) {
                // Loading and unavailable: the title and one line, no button
                // of any kind (B2, B3.5).
                plantingTitle(GardenCopy.plantFirstTreeTitle)
                plantingBody(Self.unavailableLine(availability))
            } else {
                switch empty {
                case .plantSeed(let partnerCanAnswer):
                    plantingTitle(GardenCopy.plantFirstTreeTitle)
                    plantingBody(GardenCopy.plantFirstTreeBody(partnerName: partner))
                    BrandCTA(title: GardenCopy.plantASeed, icon: "leaf.fill", tier: .hero) {
                        actions.onOpenSheet(.plant(.ourTreeFirstPlanting))
                    }
                    .padding(.top, 4)
                    if partnerCanAnswer == false { legacyLine }

                case .mySeedWaiting(let storedStartDay, let partnerCanAnswer):
                    plantingTitle(GardenCopy.waitingFor(partnerName: partner))
                    plantingBody(GardenCopy.myFirstSeedBody(storedStartDay: storedStartDay, partnerName: partner))
                    mySeedButtons
                    if partnerCanAnswer == false { legacyLine }

                case .partnersSeed(let proposalId, let storedStartDay, let note):
                    plantingTitle(GardenCopy.partnerSentSeed(partnerName: partner))
                    plantingBody(GardenCopy.partnerFirstSeedBody(storedStartDay: storedStartDay))
                    if let note {
                        Text(GardenCopy.quoted(note))
                            .font(JourneyFont.body)
                            .foregroundStyle(Brand.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    BrandCTA(title: GardenCopy.seePartnersSeed(partnerName: partner), icon: "leaf.fill", tier: .hero) {
                        actions.onOpenSheet(.seed(id: proposalId))
                    }
                    .padding(.top, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func plantingTitle(_ text: String) -> some View {
        Text(text)
            .font(JourneyFont.title)
            .foregroundStyle(Brand.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private func plantingBody(_ text: String) -> some View {
        Text(text)
            .font(JourneyFont.body)
            .foregroundStyle(Brand.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// "Edit seed · Take it back": text buttons, no fill (B3.3).
    private var mySeedButtons: some View {
        let version = garden.proposal(id: GardenDocID.seedOurTree)?.version
        let busy = garden.busyProposalIds.contains(GardenDocID.seedOurTree)
        return HStack(spacing: 20) {
            Button {
                if let version {
                    actions.onOpenSheet(.plant(.editSeed(id: GardenDocID.seedOurTree, seen: version)))
                }
            } label: {
                Text(GardenCopy.editSeed)
                    .font(JourneyFont.label)
                    .foregroundStyle(Brand.accentStart)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .disabled(version == nil || busy)

            Button {
                confirmTakeBack = true
            } label: {
                Text(GardenCopy.takeItBack)
                    .font(JourneyFont.label)
                    .foregroundStyle(Brand.accentStart)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .disabled(busy)
        }
        .buttonStyle(.plain)
    }

    /// "Sam needs the latest Coupley to plant together." · Tell Sam.
    private var legacyLine: some View {
        let partner = garden.partnerName
        return VStack(alignment: .leading, spacing: 4) {
            Text(GardenCopy.partnerNeedsUpdateToPlant(partnerName: partner))
                .font(JourneyFont.meta)
                .foregroundStyle(Brand.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                actions.onTellPartner()
            } label: {
                Text(GardenCopy.tellPartner(partnerName: partner))
                    .font(JourneyFont.label)
                    .foregroundStyle(Brand.accentStart)
                    .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private static func unavailableLine(_ availability: GardenAvailability) -> String {
        switch availability {
        case .loading:
            return String(localized: "Checking the garden…",
                          comment: "Garden status while the garden is loading")
        case .unavailable(.neverOnline):
            return String(localized: "Connect once to start your garden.",
                          comment: "Garden status on a first launch that has never been online")
        default:
            return GardenCopy.plantingUnavailable
        }
    }

    // MARK: - Loading

    /// The start date is not known yet (B3.1): offers nothing it can't save.
    private var loadingHero: some View {
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

    // MARK: - VoiceOver value of the band

    /// The tree shown, read after the band's label "Your garden" and again
    /// after every adjust: "Our tree. Tree 1 of 4. Blooming, in a meadow
    /// with a windmill, in the evening, in autumn. Café Giảng. Sam watered
    /// today at 9:14 PM. 3 memories shine around it. 2 sealed letters wait
    /// on it."
    private func bandSummary(hero: GardenHeroModel, pages: [GardenPageModel], page: GardenPageModel) -> String {
        let tree = self.tree(for: page)
        var sentences = [Self.sentence(page.title)]
        if pages.count > 1, let index = pages.firstIndex(where: { $0.slot == page.slot }) {
            let position = index + 1, count = pages.count
            sentences.append(String(localized: "Tree \(position) of \(count).",
                                    comment: "VoiceOver, garden picture: which page of the garden is shown"))
        }
        let stage = tree.stage.displayName, setting = page.environment.spokenSetting
        sentences.append(String(localized: "\(stage), \(setting).",
                                comment: "VoiceOver, garden picture: the tree's growth stage, then where and when it stands, as in 'Blooming, in a meadow with a windmill, in the evening, in autumn.'"))
        if let place = page.place {
            sentences.append(Self.sentence(place.name))
        }
        if let status = hero.status {
            sentences.append(Self.sentence(status.line))
        }
        if page.slot.isOurTree {
            sentences += TimeTreeHeader.treeSentences(ornaments: tree.ornaments, memoryCount: tree.memoryCount,
                                                      partnerName: journey.letters.partnerName)
        }
        // The garden chip's amber dot, in words.
        let waiting = garden.requests.filter { !$0.isMine && !$0.isSnoozed }.count
        if waiting > 0 {
            sentences.append(Self.sentence(GardenCopy.gardenChipLabel(treeCount: hero.treeCount, requestsWaiting: waiting)))
        }
        return sentences.joined(separator: " ")
    }

    // MARK: - Watering

    /// A new effect: remember its page (for the neighbours' after-glow)
    /// and play its haptics while the hero is on screen.
    private func playbackStarted() {
        guard let playback = garden.playback else { return }
        playbackSlot = garden.selectedSlot
        afterGlowStarts = [:]
        if isOnScreen {
            GardenHaptics.shared.play(playback)
        }
    }

    /// A page swiped to within 10 s of a watering on another page shows its
    /// after-glow instead of a second show (C9).
    private func noteAfterGlow(on slot: GardenSlot?) {
        guard let slot, let playback = garden.playback, slot != playbackSlot, afterGlowStarts[slot] == nil else { return }
        let now = Date().timeIntervalSinceReferenceDate
        guard now - playback.startTime < GardenCadence.afterGlowWithin else { return }
        afterGlowStarts[slot] = now
    }

    // MARK: - The one-time reveal

    /// The first time this device shows the garden (A9): the scene fades in
    /// behind the tree and the sun or moon rises into place.
    private func beginRevealIfFirst() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.revealSeenKey) else { return }
        defaults.set(true, forKey: Self.revealSeenKey)
        revealed = false
        Task {
            try? await Task.sleep(for: .milliseconds(50))
            withAnimation(.easeOut(duration: 0.8)) { revealed = true }
        }
    }

    // MARK: - Copy helpers

    static let water = Color(red: 0.36, green: 0.66, blue: 0.92)

    /// One line of the hero read as its own sentence by VoiceOver.
    static func sentence(_ text: String) -> String {
        String(localized: "\(text).", comment: "VoiceOver: one line of the garden hero (a title, a place, a status) read as a sentence")
    }
}

// MARK: - Previews

// Build a GardenViewModel on the in-memory service, so DEBUG only (K7).
#if DEBUG
#Preview("Hero · existing couple") {
    let garden = GardenViewModel(session: GardenLab.session, service: InMemoryGardenService())
    ScrollView {
        GardenHero(garden: garden, isCovered: false)
            .padding(.horizontal, SurfaceTier.hero.gutter)
    }
    .background(Brand.bgGradient.ignoresSafeArea())
    .onAppear { garden.start() }
}

#Preview("Hero · no start date") {
    let garden = GardenViewModel(session: GardenLab.session, service: InMemoryGardenService(startDay: nil))
    ScrollView {
        GardenHero(garden: garden, isCovered: false)
            .padding(.horizontal, SurfaceTier.hero.gutter)
    }
    .background(Brand.bgGradient.ignoresSafeArea())
    .onAppear { garden.start() }
}

#Preview("Hero · a seed for Our tree waits for me") {
    let service = InMemoryGardenService(startDay: nil)
    let garden = GardenViewModel(session: GardenLab.session, service: service)
    ScrollView {
        GardenHero(garden: garden, isCovered: false)
            .padding(.horizontal, SurfaceTier.hero.gutter)
    }
    .background(Brand.bgGradient.ignoresSafeArea())
    .onAppear {
        garden.start()
        service.simulatePartner(.sendSeed(.ourTree))
    }
}
#endif
