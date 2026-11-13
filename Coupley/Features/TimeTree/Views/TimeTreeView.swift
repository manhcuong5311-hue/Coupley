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

    /// The scroll view's visible height, which sets the tree's height.
    @State private var viewportHeight: CGFloat = 0

    init(session: UserSession,
         letters: JourneyLetterFeed = .unavailable(),
         myName: String? = nil,
         focus: Binding<JourneyFocus?> = .constant(nil),
         onOpenLetter: @escaping (FutureLetter) -> Void = { _ in },
         onOpenAllLetters: @escaping () -> Void = {},
         onWriteLetter: @escaping (_ seed: String?, _ opensAt: Date?) -> Void = { _, _ in }) {
        self.session = session
        self.letters = letters
        self.myName = myName
        _focus = focus
        self.onOpenLetter = onOpenLetter
        self.onOpenAllLetters = onOpenAllLetters
        self.onWriteLetter = onWriteLetter
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
                            errorStrip(error)
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
            }
            .animation(reduceMotion
                       ? .easeInOut(duration: 0.2)
                       : .spring(response: 0.5, dampingFraction: 0.85),
                       value: viewModel.pendingCrownCelebration?.id)
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
                            stagedLetter = StagedLetter(seed: nil, opensAt: nil)
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
            .sheet(isPresented: $showAnchorSheet, onDismiss: { handleFocus(focus) }) {
                AnchorSetupSheet(
                    viewModel: viewModel,
                    existing: viewModel.anchor,
                    myName: myName,
                    partnerName: letters.partnerName
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showTreeGuide) {
                JourneyTreeGuideSheet(
                    stage: viewModel.growthStage,
                    daysTogether: viewModel.daysTogether ?? 0,
                    partnerName: letters.partnerName
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
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
                addButton(filled: viewModel.anchor != nil)
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
        if viewModel.anchor == nil && viewModel.hasResolvedAnchor {
            return String(localized: "Set the day it started", comment: "Journey masthead subtitle: no relationship start date yet")
        }

        let memories = viewModel.visibleMemories.count
        let letterCount = letters.isAvailable ? letters.letters.count : 0
        let capsules = viewModel.lockedCapsules.count

        // A tally: each count is its own whole phrase, separated by " · ".
        var parts: [String] = []
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
        // The picker only offers a letter while letters are available.
        .accessibilityLabel(letters.isAvailable ? "Add a memory or a letter" : "Add a memory")
    }

    // MARK: - Error strip

    private func errorStrip(_ message: String) -> some View {
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

                    Button {
                        if viewModel.errorIsRetryable {
                            viewModel.retryAfterError()
                        } else {
                            viewModel.dismissError()
                        }
                    } label: {
                        Group {
                            if viewModel.errorIsRetryable {
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
    }

    private var isJourneySheetPresented: Bool {
        showMilestonePicker
            || pendingNewKind != nil
            || selectedMemory != nil
            || editingMemory != nil
            || showAnchorSheet
            || showTreeGuide
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

#Preview {
    TimeTreeView(session: .demo)
}
