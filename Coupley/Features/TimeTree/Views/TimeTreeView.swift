//
//  TimeTreeView.swift
//  Coupley
//
//  The Journey tab. Top to bottom:
//
//   1. Masthead: "Journey", the screen's only tally (memories, letters,
//      sealed capsules) and the one filled +.
//   2. TimeTreeHeader: ONE hero with the tree and the day count, then a
//      quiet countdown block (next anniversary and next crown).
//   3. JourneyLettersSection: the letters between you, both directions.
//   4. MemoryTimelineSection: what is sealed for later (letters both ways
//      and locked capsules), then the memories, with opened capsules and
//      opened letters kept among them by date.
//
//  Letters come in as one `JourneyLetterFeed` value. ContentView owns the
//  letters view model and the letters sheet: tapping a letter anywhere here
//  calls `onOpenLetter`, and writing one calls `onWriteLetter`. Journey
//  presents its own sheets on this NavigationStack, one at a time, and hands
//  anything for the letters sheet to ContentView only from a sheet's
//  onDismiss, never while one of its own sheets is up.
//
//  A tapped capsule or crown reminder arrives through `focus`: a capsule
//  opens its detail sheet once the memories have loaded, a crown replays its
//  celebration.
//
//  Garden mode (GardenFeature.isEnabled, and the garden not switched off
//  remotely): the garden hero replaces TimeTreeHeader's hero, the requests
//  waiting for this user sit under it, and TimeTreeHeader renders only its
//  countdown block. Every garden sheet goes through the one `gardenSheet`
//  route, one at a time like Journey's own; a garden push, reminder or
//  Home's row arrives as `.garden(...)` focus. Otherwise the layout is
//  exactly the pre-garden Journey.
//

import Foundation
import SwiftUI
import UIKit

// MARK: - Tab Root

struct TimeTreeView: View {

    @StateObject private var viewModel: TimeTreeViewModel

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let session: UserSession
    private let letters: JourneyLetterFeed
    /// This user's display name, for the start-date sheet's attribution.
    private let myName: String?
    /// Set by ContentView when a Journey reminder is tapped; handled here and
    /// set back to nil.
    @Binding private var focus: JourneyFocus?
    private let onOpenLetter: (FutureLetter) -> Void
    private let onOpenAllLetters: () -> Void
    private let onWriteLetter: (_ seed: String?, _ opensAt: Date?) -> Void
    /// ContentView's letters sheet is up (it presents the reader, the writer
    /// and the hub over every tab). Garden mode only: it covers the hero.
    private let isLettersSheetPresented: Bool
    /// The couple's garden. ContentView owns it (Home's row and push routing
    /// read it too).
    @ObservedObject private var garden: GardenViewModel
    /// "Reply in Chat": switches to the Chat tab.
    private let onOpenChat: () -> Void

    // Sheets: one at a time, all on this NavigationStack.
    @State private var showMilestonePicker = false
    @State private var stagedKind: MemoryKind?
    @State private var stagedLetter: StagedLetter?
    @State private var pendingNewKind: MemoryKind?
    @State private var selectedMemory: TimeMemory?
    /// The detail sheet's own editor is up (it presents it; this mirrors it
    /// so a capsule reminder waits instead of throwing away its edits).
    @State private var detailEditorUp = false
    @State private var editingMemory: TimeMemory?
    @State private var showAnchorSheet = false
    @State private var showTreeGuide = false
    /// The stage the tree guide opens on when a garden page asked for it
    /// (a place tree has its own); nil shows Our tree's.
    @State private var treeGuideOverride: TreeGuideTarget?

    // Garden sheets: one route, one at a time, like Journey's own.
    @State private var gardenSheet: GardenSheetRoute?
    /// The next garden sheet, shown once the current one is gone.
    @State private var stagedGardenRoute: GardenSheetRoute?
    /// "Plant a tree" picked in the + picker, opened once it is gone.
    @State private var stagedPlantTree = false
    /// The water note being written; kept when its sheet is swiped away.
    /// Journey reads only whether it holds a note, never its text, so
    /// typing re-renders the sheet alone.
    @State private var noteDraft = GardenNoteDraft()
    /// The note chosen in the water-note sheet: watered once it is gone.
    @State private var pendingWaterNote: String?
    /// "Tell Sam": the confirmation before the chat line is sent.
    @State private var showTellPartner = false
    /// Tell Sam asked for from the start-date sheet: confirmed once it is gone.
    @State private var pendingTellPartner = false

    /// The scroll view's visible height, which sets the tree's height.
    @State private var viewportHeight: CGFloat = 0

    init(session: UserSession,
         letters: JourneyLetterFeed = .unavailable(),
         myName: String? = nil,
         focus: Binding<JourneyFocus?> = .constant(nil),
         onOpenLetter: @escaping (FutureLetter) -> Void = { _ in },
         onOpenAllLetters: @escaping () -> Void = {},
         onWriteLetter: @escaping (_ seed: String?, _ opensAt: Date?) -> Void = { _, _ in },
         isLettersSheetPresented: Bool = false,
         garden: GardenViewModel,
         onOpenChat: @escaping () -> Void = {}) {
        self.session = session
        self.letters = letters
        self.myName = myName
        _focus = focus
        self.onOpenLetter = onOpenLetter
        self.onOpenAllLetters = onOpenAllLetters
        self.onWriteLetter = onWriteLetter
        self.isLettersSheetPresented = isLettersSheetPresented
        self.garden = garden
        self.onOpenChat = onOpenChat
        _viewModel = StateObject(wrappedValue: TimeTreeViewModel(session: session))
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        journeyMasthead
                            .padding(.horizontal, Brand.Space.gutter)
                            .padding(.top, 8)

                        // The view model records every failure; a rejected
                        // photo upload or a failed save must not look like
                        // success.
                        if let error = viewModel.errorMessage {
                            errorStrip(error, isRetryable: viewModel.errorIsRetryable) {
                                if viewModel.errorIsRetryable {
                                    viewModel.retryAfterError()
                                } else {
                                    viewModel.dismissError()
                                }
                            }
                            .padding(.horizontal, Brand.Space.gutter)
                            .padding(.top, Brand.Space.sibling)
                        }
                        // Garden actions use the same strip.
                        if isGardenMode, let error = garden.errorMessage {
                            errorStrip(error, isRetryable: false) { garden.dismissError() }
                                .padding(.horizontal, Brand.Space.gutter)
                                .padding(.top, Brand.Space.sibling)
                        }

                        journeyContent

                        // Clears the ad banner and the floating tab bar, which
                        // sit over the scroll view's bottom edge (Home and
                        // Mood leave the same 120pt).
                        Color.clear.frame(height: 120)
                    }
                }
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    viewportHeight = height
                }
                .background(Brand.bgGradient.ignoresSafeArea())

                // Crown celebration overlay
                if let crown = viewModel.pendingCrownCelebration {
                    CrownCelebrationOverlay(
                        milestone: crown,
                        onDismiss: { viewModel.acknowledgeCrown() }
                    )
                    .transition(.opacity)
                    .zIndex(900)
                }

                // The planting ceremony, after any crown.
                if isGardenMode, let ceremony = garden.ceremony, viewModel.pendingCrownCelebration == nil {
                    PlantingCeremonyOverlay(
                        ceremony: ceremony,
                        partnerName: garden.partnerName,
                        myName: myName,
                        onDone: { garden.acknowledgeCeremony() }
                    )
                    .transition(.opacity)
                    .zIndex(901)
                }
            }
            .animation(reduceMotion
                       ? .easeInOut(duration: 0.2)
                       : .spring(response: 0.5, dampingFraction: 0.85),
                       value: viewModel.pendingCrownCelebration?.id)
            .animation(reduceMotion
                       ? .easeInOut(duration: 0.2)
                       : .spring(response: 0.5, dampingFraction: 0.85),
                       value: garden.ceremony?.id)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                viewModel.startListening()
                viewModel.resumeTicking()
            }
            .onDisappear {
                // Only the minute timer stops. The listeners stay, so coming
                // back to the tab never shows "Loading" again.
                viewModel.pauseTicking()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { viewModel.refresh() }
            }
            .onChange(of: focus, initial: true) { _, target in
                handleFocus(target)
            }
            .onChange(of: viewModel.hasReceivedFirstUpdate) { _, _ in
                handleFocus(focus)
            }
            .onChange(of: viewModel.hasReceivedListenerUpdate) { _, _ in
                handleFocus(focus)
            }
            .onChange(of: viewModel.errorMessage) { _, _ in
                handleFocus(focus)
            }
            // A garden focus waits for the garden's first answer.
            .onChange(of: garden.availability) { _, _ in
                handleFocus(focus)
            }
            // A garden failure lands in the strip above the hero, away from
            // VoiceOver's focus (a refused watering leaves it on the water
            // control): say it.
            .onChange(of: garden.errorMessage) { _, message in
                guard isGardenMode, let message else { return }
                AccessibilityNotification.Announcement(message).post()
            }
            // Deleted on the other phone while 'Add photo' is open: close the
            // editor (the view model also refuses to write it back).
            .onChange(of: viewModel.memories.map(\.id)) { _, ids in
                if let editing = editingMemory, !ids.contains(editing.id) {
                    editingMemory = nil
                }
            }
            .sheet(isPresented: $showMilestonePicker, onDismiss: { milestonePickerDidDismiss() }) {
                MilestonePickerSheet(
                    loggedDates: viewModel.firstDateByKind,
                    partnerName: letters.partnerName,
                    onPick: { kind in
                        stagedLetter = nil
                        stagedKind = kind
                    },
                    // Its "write a letter" row, only while letters are
                    // available.
                    onWriteLetter: letters.isAvailable
                        ? {
                            stagedKind = nil
                            stagedPlantTree = false
                            stagedLetter = StagedLetter(seed: nil, opensAt: nil)
                        }
                        : nil,
                    // Its "Plant a tree" row, while the garden can take one.
                    onPlantTree: isGardenMode && garden.canPlantMore
                        ? {
                            stagedKind = nil
                            stagedLetter = nil
                            stagedPlantTree = true
                        }
                        : nil
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $pendingNewKind, onDismiss: { createEditorDidDismiss() }) { kind in
                MemoryEditorSheet(
                    viewModel: viewModel,
                    mode: .create(kind),
                    partnerName: letters.partnerName,
                    // The capsule editor's link to a future letter: the typed
                    // note and the chosen day go to Compose.
                    onWriteLetterInstead: letters.isAvailable
                        ? { seed, opensAt in
                            stagedLetter = StagedLetter(seed: seed, opensAt: opensAt)
                        }
                        : nil
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $selectedMemory, onDismiss: {
                // Gone with its editor, if that was still up.
                detailEditorUp = false
                handleFocus(focus)
            }) { memory in
                // A reminder that waited for the detail's editor resumes once
                // that editor has fully closed, not when its flag flips.
                MemoryDetailSheet(viewModel: viewModel,
                                  memory: memory,
                                  showEditor: $detailEditorUp,
                                  onEditorDismissed: { handleFocus(focus) })
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(item: $editingMemory, onDismiss: { handleFocus(focus) }) { memory in
                MemoryEditorSheet(viewModel: viewModel, mode: .edit(memory))
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showAnchorSheet, onDismiss: { anchorSheetDidDismiss() }) {
                AnchorSetupSheet(
                    viewModel: viewModel,
                    existing: viewModel.anchor,
                    myName: myName,
                    partnerName: letters.partnerName,
                    mode: anchorSheetMode
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showTreeGuide, onDismiss: { treeGuideOverride = nil }) {
                JourneyTreeGuideSheet(
                    stage: treeGuideOverride?.stage ?? viewModel.growthStage,
                    daysTogether: treeGuideOverride?.days ?? viewModel.daysTogether ?? 0,
                    partnerName: letters.partnerName,
                    showsGarden: isGardenMode,
                    growsFromPlanting: treeGuideOverride?.isPlaceTree ?? false
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $gardenSheet, onDismiss: { gardenSheetDidDismiss() }) { route in
                GardenRouteSheet(
                    route: route,
                    garden: garden,
                    noteDraft: noteDraft,
                    timelineDays: viewModel.firstDateByKind,
                    handOver: { next in
                        stagedGardenRoute = next
                        gardenSheet = nil
                    },
                    onWater: { pendingWaterNote = $0 },
                    onClose: { gardenSheet = nil }
                )
            }
            .alert(Text("Send this to \(garden.partnerName) in Chat?",
                        comment: "Garden: confirmation before sending the partner a chat message about updating Coupley. %@ is the partner's name."),
                   isPresented: $showTellPartner) {
                Button {
                    Task { _ = await garden.tellPartnerToUpdate() }
                } label: {
                    Text("Send", comment: "Garden: sends the update message to the partner in Chat")
                }
                Button(role: .cancel) {} label: {
                    Text("Cancel", comment: "Button: close the menu without doing anything")
                }
            } message: {
                Text(GardenCopy.tellPartnerMessage)
            }
        }
    }

    // MARK: - Garden

    /// The garden replaces the pre-garden hero (I5). Off in Release until
    /// the garden ships, and when the garden is switched off remotely.
    private var isGardenMode: Bool {
        GardenFeature.isEnabled && session.isPaired && garden.availability != .disabledRemotely
    }

    /// The tree guide for a garden page's own tree: its stage, its days, and
    /// whether it is a place tree (it grows from its planting day).
    private struct TreeGuideTarget {
        let stage: TreeGrowthStage
        let days: Int
        let isPlaceTree: Bool
    }

    private var gardenHeroJourney: GardenHeroJourney {
        GardenHeroJourney(
            startDate: viewModel.anchor?.startDate,
            daysTogether: viewModel.anchor != nil ? viewModel.daysTogether : nil,
            stage: viewModel.anchor != nil ? viewModel.growthStage : nil,
            memoryCount: viewModel.visibleMemories.count,
            letters: letters,
            isCompact: viewportHeight > 0 && viewportHeight < 700,
            noteDrafted: noteDraft.isDrafted
        )
    }

    /// The garden hero is out of sight under something that fires no
    /// onDisappear: one of Journey's sheets, ContentView's letters sheet, or
    /// a full-screen overlay (the crown celebration, the planting ceremony).
    /// It then stops animating, and the garden holds a partner's replay and
    /// a due ceremony until the hero can be seen again.
    private var isGardenHeroCovered: Bool {
        isJourneySheetPresented || isLettersSheetPresented
            || viewModel.pendingCrownCelebration != nil || garden.ceremony != nil
    }

    private var gardenHeroActions: GardenHeroActions {
        GardenHeroActions(
            onOpenSheet: { openGardenSheet($0) },
            onWater: { waterGarden() },
            onEditStartDate: { showAnchorSheet = true },
            onShowTreeGuide: { stage, days, isPlaceTree in
                treeGuideOverride = TreeGuideTarget(stage: stage, days: days, isPlaceTree: isPlaceTree)
                showTreeGuide = true
            },
            onOpenLetter: onOpenLetter,
            onReplyInChat: onOpenChat,
            onTellPartner: { showTellPartner = true }
        )
    }

    /// One sheet at a time: a garden sheet asked for while another Journey
    /// sheet is up is dropped (the user is in that sheet).
    private func openGardenSheet(_ route: GardenSheetRoute) {
        guard !isJourneySheetPresented else { return }
        gardenSheet = route
    }

    /// The hero's water control: one tap waters every tree, with the note
    /// drafted in the water-note sheet if one waits.
    private func waterGarden() {
        let note = GardenLimits.wateringNote.clean(noteDraft.text)
        noteDraft.text = ""
        garden.water(note: note)
    }

    /// A garden sheet is gone: the next one it handed over, else the
    /// watering its note asked for, else a reminder that waited for it.
    private func gardenSheetDidDismiss() {
        if let next = stagedGardenRoute {
            stagedGardenRoute = nil
            gardenSheet = next
            return
        }
        if let note = pendingWaterNote {
            pendingWaterNote = nil
            noteDraft.text = ""
            garden.water(note: GardenLimits.wateringNote.clean(note))
        }
        handleFocus(focus)
    }

    /// The start date in garden mode is suggested to the partner and
    /// changes when they agree (B5.7); otherwise today's direct save.
    private var anchorSheetMode: AnchorSetupSheet.Mode {
        guard isGardenMode, let anchor = viewModel.anchor else { return .directSave }
        let ourTree = garden.tree(.our)
        let agreedOn = ourTree.flatMap { tree in
            tree.agreementKind == .startDate || tree.agreementKind == .plant ? tree.agreementAt : nil
        }
        return .suggest(currentStored: anchor.startDate,
                        partnerCanAnswer: garden.partner.canGarden,
                        agreedOn: agreedOn,
                        onSuggest: { day, note in
                            if await garden.suggestStartDate(day: day, note: note) { return nil }
                            let reason = garden.errorMessage
                                ?? GardenError.other.message(partnerName: garden.partnerName, now: garden.now)
                            // The open sheet says why, so Journey's strip
                            // behind it does not repeat it (as the plant
                            // sheet); a sheet already swiped away leaves it.
                            if showAnchorSheet { garden.dismissError() }
                            return reason
                        },
                        onTellPartner: {
                            pendingTellPartner = true
                            showAnchorSheet = false
                        })
    }

    private func anchorSheetDidDismiss() {
        if pendingTellPartner {
            pendingTellPartner = false
            showTellPartner = true
        }
        handleFocus(focus)
    }

    // MARK: - Content

    /// First load only: the listeners stay up across tab switches, so this
    /// never comes back once the memories have answered. It does not wait
    /// for the start date: a couple without one would otherwise see nothing
    /// but "Loading" for as long as the phone is offline, hiding cached
    /// memories and letters. The hero holds back "Plant your tree" until the
    /// server has said there is no start date (`isStartDateKnown`).
    private var isFirstLoad: Bool {
        viewModel.isListening && !viewModel.hasReceivedFirstUpdate && viewModel.errorMessage == nil
    }

    /// Whether the hero may treat a missing start date as "none set yet".
    /// Until the server (or a cache) has answered, `setAnchor` refuses a
    /// first start date, so the hero must not offer one.
    private var isStartDateKnown: Bool {
        viewModel.anchor != nil || viewModel.hasResolvedAnchor
    }

    @ViewBuilder
    private var journeyContent: some View {
        if !session.isPaired {
            notPairedCard
                .padding(.horizontal, Brand.Space.gutter)
                .padding(.top, Brand.Space.sibling)
        } else if isFirstLoad {
            loadingState
                .padding(.horizontal, Brand.Space.gutter)
        } else if isGardenMode {
            // The garden hero, what waits for this user, then the countdown
            // block alone (TimeTreeHeader without its hero).
            GardenHero(garden: garden,
                       isCovered: isGardenHeroCovered,
                       journey: gardenHeroJourney,
                       actions: gardenHeroActions)
                .padding(.horizontal, SurfaceTier.hero.gutter)
                .padding(.top, Brand.Space.sibling)

            GardenRequestsSection(garden: garden,
                                  onOpenRequest: { openGardenSheet(.seed(id: $0)) },
                                  onOpenGarden: { openGardenSheet(.garden) },
                                  onChoosePlace: { openGardenSheet(.plant(.changeTree(.our))) },
                                  onTellPartner: { showTellPartner = true })
                .padding(.horizontal, Brand.Space.gutter)

            if viewModel.anchor != nil {
                TimeTreeHeader(
                    anchor: viewModel.anchor,
                    now: viewModel.now,
                    daysTogether: viewModel.daysTogether,
                    stage: viewModel.growthStage,
                    season: viewModel.currentSeason,
                    memoryCount: viewModel.visibleMemories.count,
                    letters: letters,
                    treeHeight: treeHeight,
                    onEditStartDate: { showAnchorSheet = true },
                    onShowTreeGuide: { showTreeGuide = true },
                    onOpenLetter: onOpenLetter,
                    onWriteLetter: { opensAt in onWriteLetter(nil, opensAt) },
                    isStartDateKnown: isStartDateKnown,
                    showsHero: false
                )
                .padding(.top, Brand.Space.sibling)
            }

            journeyLists
        } else {
            // Hero (12pt gutter), then the countdown block (20pt) 14pt
            // under it; the header pads each itself.
            TimeTreeHeader(
                anchor: viewModel.anchor,
                now: viewModel.now,
                daysTogether: viewModel.daysTogether,
                stage: viewModel.growthStage,
                season: viewModel.currentSeason,
                memoryCount: viewModel.visibleMemories.count,
                letters: letters,
                treeHeight: treeHeight,
                onEditStartDate: { showAnchorSheet = true },
                onShowTreeGuide: { showTreeGuide = true },
                onOpenLetter: onOpenLetter,
                onWriteLetter: { opensAt in onWriteLetter(nil, opensAt) },
                isStartDateKnown: isStartDateKnown
            )
            .padding(.top, Brand.Space.sibling)

            journeyLists
        }
    }

    /// The letters and the Timeline, under the hero in both layouts.
    @ViewBuilder
    private var journeyLists: some View {
        if letters.isAvailable && letters.hasLoaded {
            JourneyLettersSection(
                letters: letters,
                onOpenLetter: onOpenLetter,
                onOpenAll: onOpenAllLetters,
                onWrite: { onWriteLetter(nil, nil) }
            )
            .padding(.horizontal, Brand.Space.gutter)
            .padding(.top, 32)
        }

        MemoryTimelineSection(
            memories: viewModel.visibleMemories,
            lockedCapsules: viewModel.lockedCapsules,
            letters: letters,
            now: viewModel.now,
            onSelectMemory: { selectedMemory = $0 },
            onSelectLetter: { onOpenLetter($0.envelope) },
            onAddMemory: { showMilestonePicker = true },
            onAddPhoto: { editingMemory = $0 },
            canAddPhoto: { viewModel.canEdit($0) }
        )
        .padding(.horizontal, Brand.Space.gutter)
        .padding(.top, 32)
    }

    /// 196pt, or 160pt when the visible scroll area is under 700pt tall, so
    /// the countdown block still makes the first screen there.
    private var treeHeight: CGFloat {
        viewportHeight > 0 && viewportHeight < 700 ? 160 : 196
    }

    // MARK: - Masthead

    private var journeyMasthead: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Journey", comment: "Journey tab masthead title")
                    .font(JourneyFont.display)
                    .foregroundStyle(Brand.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                if let subtitle = mastheadSubtitle {
                    Text(subtitle)
                        .font(JourneyFont.body)
                        .foregroundStyle(Brand.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Always there once loaded, so a couple without a start date can
            // still add a memory after the Timeline's empty state is gone.
            if session.isPaired && !isFirstLoad {
                // Garden mode: one filled control per screen (B2); the hero's
                // CTA takes the fill when planting or watering is the job.
                addButton(filled: isGardenMode
                          ? garden.primaryAction.isMastheadPlusFilled
                          : viewModel.anchor != nil)
            }
        }
    }

    /// The only place on Journey that counts anything. Nil while the first
    /// load is in flight, when there is nothing true to say yet.
    private var mastheadSubtitle: String? {
        guard session.isPaired else {
            return String(localized: "Pair up to start your tree", comment: "Journey masthead subtitle before pairing")
        }
        if isFirstLoad { return nil }
        if isGardenMode, let empty = garden.hero.empty {
            return gardenPlantingSubtitle(empty)
        }
        if viewModel.anchor == nil && viewModel.hasResolvedAnchor {
            return String(localized: "Set the day it started", comment: "Journey masthead subtitle: no relationship start date yet")
        }

        let memories = viewModel.visibleMemories.count
        let letterCount = letters.isAvailable ? letters.letters.count : 0
        let capsules = viewModel.lockedCapsules.count
        let trees = isGardenMode ? garden.treeCount : 0

        // A tally: each count is its own whole phrase, separated by " · ".
        var parts: [String] = []
        // Trees lead the tally, from the second tree on.
        if trees > 1 {
            parts.append(String(localized: "\(trees) trees", comment: "Journey masthead tally: trees in the couple's garden (2 or more)"))
        }
        if memories > 0 {
            parts.append(memories == 1
                         ? String(localized: "1 memory", comment: "Journey masthead tally")
                         : String(localized: "\(memories) memories", comment: "Journey masthead tally"))
        }
        if letterCount > 0 {
            parts.append(letterCount == 1
                         ? String(localized: "1 letter", comment: "Journey masthead tally: future letters")
                         : String(localized: "\(letterCount) letters", comment: "Journey masthead tally: future letters"))
        }
        if capsules > 0 {
            parts.append(capsules == 1
                         ? String(localized: "1 sealed capsule", comment: "Journey masthead tally: memory capsules not opened yet")
                         : String(localized: "\(capsules) sealed capsules", comment: "Journey masthead tally: memory capsules not opened yet"))
        }
        // Letters not loaded yet may be all there is: say nothing rather
        // than "Add your first memory" for a moment.
        if parts.isEmpty && letters.isAvailable && !letters.hasLoaded { return nil }
        return parts.isEmpty
            ? String(localized: "Add your first memory", comment: "Journey masthead subtitle: nothing added yet")
            : parts.joined(separator: " · ")
    }

    /// Before the start date in garden mode (B1).
    private func gardenPlantingSubtitle(_ empty: GardenEmptyHero) -> String {
        let partner = garden.partnerName
        switch empty {
        case .plantSeed:     return GardenCopy.plantFirstTreeTitle
        case .mySeedWaiting: return GardenCopy.waitingToPlant(partnerName: partner)
        case .partnersSeed:  return GardenCopy.partnerSentSeed(partnerName: partner)
        }
    }

    /// Opens the picker, which also offers a letter when letters are
    /// available. Filled (the screen's one filled accent) once a start date
    /// exists; outlined while the plant hero's CTA is the one fill.
    private func addButton(filled: Bool) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            showMilestonePicker = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(filled ? Color.white : Brand.accentStart)
                .frame(width: 34, height: 34)
                .background {
                    if filled {
                        Circle()
                            .fill(Brand.accentGradient)
                            .shadow(color: Brand.accentStart.opacity(0.35), radius: 8, y: 3)
                    } else {
                        Circle()
                            .fill(Brand.surfaceLight)
                            .overlay(Circle().strokeBorder(Brand.accentStart.opacity(0.45), lineWidth: 1))
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(BouncyButtonStyle(scale: 0.92))
        // The picker offers a letter while letters are available, and a tree
        // while the garden can take one.
        .accessibilityLabel(addButtonLabel)
    }

    private var addButtonLabel: Text {
        let tree = isGardenMode && garden.canPlantMore
        switch (letters.isAvailable, tree) {
        case (true, true):
            return Text("Add a memory, a letter or a tree", comment: "VoiceOver: Journey's + button when it can add a memory, a letter or a garden tree")
        case (false, true):
            return Text("Add a memory or a tree", comment: "VoiceOver: Journey's + button when it can add a memory or a garden tree")
        case (true, false):
            return Text("Add a memory or a letter")
        case (false, false):
            return Text("Add a memory")
        }
    }

    // MARK: - Error strip

    /// `isRetryable` shows "Try again" (it reloads), else "OK" (it dismisses).
    private func errorStrip(_ message: String, isRetryable: Bool, action: @escaping () -> Void) -> some View {
        BrandCard(tier: .card) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(JourneyFont.label)
                    .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.45))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 8) {
                    Text(message)
                        .font(JourneyFont.body)
                        .foregroundStyle(Brand.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(action: action) {
                        Group {
                            if isRetryable {
                                Text("Try again", comment: "Journey error strip: retry loading")
                            } else {
                                Text("OK", comment: "Journey error strip: dismiss the message")
                            }
                        }
                        .font(JourneyFont.label)
                        .foregroundStyle(Brand.accentStart)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Loading

    private var loadingState: some View {
        VStack(spacing: Brand.Space.sibling) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(Brand.accentStart)
            Text("Loading your Journey…")
                .font(JourneyFont.body)
                .foregroundStyle(Brand.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Not paired

    private var notPairedCard: some View {
        BrandCard(tier: .card) {
            VStack(spacing: 10) {
                Image(systemName: "leaf.fill")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .foregroundStyle(Brand.accentStart)
                    .accessibilityHidden(true)

                Text("Connect with your partner first")
                    .font(JourneyFont.title)
                    .foregroundStyle(Brand.textPrimary)

                Text("Your tree grows together — pair up to plant the seed.")
                    .font(JourneyFont.body)
                    .foregroundStyle(Brand.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Sheets

    /// A letter asked for from inside a Journey sheet. ContentView presents
    /// the letters sheet, and only one sheet can be up, so the request waits
    /// here until that sheet's onDismiss.
    private struct StagedLetter {
        let seed: String?
        let opensAt: Date?
    }

    /// Commit the picker's choice only once it is fully gone: presenting the
    /// next sheet while it is still dismissing renders that sheet blank.
    private func milestonePickerDidDismiss() {
        if let kind = stagedKind {
            stagedKind = nil
            pendingNewKind = kind
        } else if stagedPlantTree {
            stagedPlantTree = false
            gardenSheet = .plant(.newPlaceTree)
        } else {
            handOffStagedLetter()
        }
    }

    private func handOffStagedLetter() {
        guard let staged = stagedLetter else { return }
        stagedLetter = nil
        onWriteLetter(staged.seed, staged.opensAt)
    }

    /// The create editor is gone. A letter the user just asked for from it
    /// wins over a capsule reminder that waited for it to close.
    private func createEditorDidDismiss() {
        if stagedLetter != nil {
            focus = nil
            handOffStagedLetter()
        } else {
            handleFocus(focus)
        }
    }

    /// Something the user is writing is on screen: a new memory, an edit
    /// (from 'Add photo' or from a memory's detail), or the start date.
    /// Closing it would silently throw the typing away.
    private var isEditingSomething: Bool {
        pendingNewKind != nil || editingMemory != nil || showAnchorSheet || detailEditorUp
            || gardenSheet?.isEditing == true
    }

    private var isJourneySheetPresented: Bool {
        showMilestonePicker
            || pendingNewKind != nil
            || selectedMemory != nil
            || editingMemory != nil
            || showAnchorSheet
            || showTreeGuide
            || gardenSheet != nil
    }

    private func closeJourneySheets() {
        // Dropped, not handed off: the reminder decides what opens next.
        stagedKind = nil
        stagedLetter = nil
        showMilestonePicker = false
        pendingNewKind = nil
        selectedMemory = nil
        editingMemory = nil
        showAnchorSheet = false
        showTreeGuide = false
        stagedPlantTree = false
        stagedGardenRoute = nil
        gardenSheet = nil
    }

    // MARK: - Reminder focus

    private func handleFocus(_ target: JourneyFocus?) {
        guard let target else { return }
        // Showing Journey is all an unpaired session can do with a reminder.
        guard session.isPaired else {
            focus = nil
            return
        }

        switch target {
        case .overview:
            focus = nil

        case .crown(let milestoneId):
            viewModel.presentCrown(milestoneId: milestoneId)
            focus = nil

        case .garden(let target):
            handleGardenFocus(target)

        case .capsule(let memoryId):
            // A memory or start date is being written: open the capsule once
            // that sheet has closed (its onDismiss calls back here).
            guard !isEditingSomething else { return }
            if let memory = viewModel.memory(id: memoryId) {
                focus = nil
                openFocusedCapsule(memory)
                return
            }
            // Not found yet. The device cache can predate a capsule the
            // partner sealed while Journey stayed closed (its reminder comes
            // from WidgetSyncService's own listener), so give up only once
            // Journey's listener itself, or a failure, has answered.
            guard viewModel.hasReceivedListenerUpdate || viewModel.errorMessage != nil else { return }
            focus = nil
        }
    }

    /// A garden push, reminder or Home's row (I5): waits for the garden's
    /// first answer and for anything being written, closes Journey's sheets,
    /// then selects the tree (and queues a watering's replay). A request
    /// opens its seed sheet once the closing sheets are gone.
    private func handleGardenFocus(_ target: GardenFocus) {
        guard isGardenMode else {
            focus = nil
            return
        }
        guard garden.availability != .loading else { return }
        guard garden.availability == .ready else {
            // Unavailable: showing Journey is all it can do.
            focus = nil
            return
        }
        guard !isEditingSomething else { return }
        focus = nil
        closeJourneySheets()
        garden.reveal(target)
        guard case .proposal(let id) = target, garden.proposal(id: id) != nil else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            // The user may have opened something else in the meantime.
            guard !isJourneySheetPresented else { return }
            gardenSheet = .seed(id: id)
        }
    }

    /// Opens a capsule's detail from a reminder, closing whatever Journey
    /// sheet is up first (the picker, the tree guide or another memory's
    /// detail: nothing being written, see `isEditingSomething`) and giving it
    /// time to leave.
    private func openFocusedCapsule(_ memory: TimeMemory) {
        let otherSheetUp = showMilestonePicker
            || pendingNewKind != nil
            || editingMemory != nil
            || showAnchorSheet
            || showTreeGuide
            || gardenSheet != nil
        if selectedMemory?.id == memory.id && !otherSheetUp { return }

        closeJourneySheets()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            // The user may have opened something else in the meantime.
            guard !isJourneySheetPresented else { return }
            selectedMemory = viewModel.memory(id: memory.id) ?? memory
        }
    }
}

// MARK: - Preview

// Builds a GardenViewModel, so DEBUG only (spec K7).
#if DEBUG
#Preview {
    TimeTreeView(session: .demo, garden: GardenViewModel(session: .demo))
}
#endif
