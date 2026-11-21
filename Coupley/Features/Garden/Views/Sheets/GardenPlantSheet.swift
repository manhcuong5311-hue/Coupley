//
//  GardenPlantSheet.swift
//  Coupley
//
//  The plant sheet (B5.1): a new place tree, Our tree's first planting,
//  editing my seed, countering the partner's, suggesting a change or editing
//  my change. `GardenPlantSheet` is the sheet; `GardenPlantForm` is the same
//  content, pushable inside another sheet's NavigationStack.
//
//  Every mode is a transaction, so every mode needs a connection: offline the
//  one filled control is disabled and says why. Nothing is planted or changed
//  here; the partner answers. Place trees grow from the day they are planted
//  (the user's answer, 14 Nov 2026): the moment's day is remembered only.
//

import Foundation
import SwiftUI
import MapKit
import UIKit

// MARK: - Sheet

struct GardenPlantSheet: View {

    @ObservedObject var garden: GardenViewModel
    let mode: GardenDraft.Mode
    /// TimeTreeViewModel.firstDateByKind: the Timeline's day for a preset
    /// ("From your Timeline: 14 Feb 2024").
    let timelineDays: [MemoryKind: Date]

    @Environment(\.dismiss) private var dismiss

    init(garden: GardenViewModel, mode: GardenDraft.Mode, timelineDays: [MemoryKind: Date] = [:]) {
        self.garden = garden
        self.mode = mode
        self.timelineDays = timelineDays
    }

    var body: some View {
        NavigationStack {
            GardenPlantForm(garden: garden, mode: mode, timelineDays: timelineDays) {
                dismiss()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel", comment: "Plant sheet: close without sending")
                    }
                    .foregroundStyle(Brand.textSecondary)
                }
            }
        }
    }
}

// MARK: - Form

struct GardenPlantForm: View {

    @ObservedObject var garden: GardenViewModel
    let mode: GardenDraft.Mode
    let timelineDays: [MemoryKind: Date]
    let onDone: () -> Void

    @ObservedObject private var reachability = GardenReachability.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var draft: GardenDraft
    /// The chosen place's group and country: they suggest the look only.
    @State private var placeGroup: GardenPOIGroup?
    @State private var placeCountry: String?
    @State private var placeIsAddressOrPin: Bool
    /// The couple picked a look themselves: a new place no longer changes it.
    @State private var lookTouched: Bool
    /// "We're not sure of the day".
    @State private var dayUnknown: Bool
    @State private var momentDay: Date
    @State private var showsPicker = false
    @State private var isSending = false
    @State private var showsError = false

    init(garden: GardenViewModel, mode: GardenDraft.Mode, timelineDays: [MemoryKind: Date] = [:],
         onDone: @escaping () -> Void) {
        self.garden = garden
        self.mode = mode
        self.timelineDays = timelineDays
        self.onDone = onDone

        var initial = garden.draft(for: mode)
        let calendar = Calendar.current
        if initial.isOurTree, initial.startDay == nil, mode == .ourTreeFirstPlanting {
            let threeMonthsAgo = calendar.date(byAdding: .month, value: -3, to: Date()) ?? Date()
            initial.startDay = calendar.startOfDay(for: threeMonthsAgo)
        }
        _draft = State(initialValue: initial)
        _placeGroup = State(initialValue: GardenPlaceSearch.group(forStoredCategory: initial.place?.poiCategory))
        _placeIsAddressOrPin = State(initialValue: initial.place.map { $0.poiCategory == nil } ?? false)
        _lookTouched = State(initialValue: !Self.isNewTree(mode))
        _dayUnknown = State(initialValue: initial.momentDay == nil)
        _momentDay = State(initialValue: initial.momentDay ?? calendar.startOfDay(for: Date()))
    }

    private static func isNewTree(_ mode: GardenDraft.Mode) -> Bool {
        mode == .newPlaceTree || mode == .ourTreeFirstPlanting
    }

    // MARK: Mode

    /// The proposal this form edits or answers, if any.
    private var proposal: GardenProposal? {
        switch mode {
        case .editSeed(let id, _), .counter(let id, _), .editChange(let id, _): return garden.proposal(id: id)
        case .newPlaceTree, .ourTreeFirstPlanting, .changeTree: return nil
        }
    }

    /// A change to a planted tree (suggested, edited or answered).
    private var isChange: Bool {
        switch mode {
        case .changeTree, .editChange: return true
        case .counter: return proposal?.kind == .change
        case .newPlaceTree, .ourTreeFirstPlanting, .editSeed: return false
        }
    }

    /// The planted tree a change is about.
    private var changedTree: GardenTree? {
        switch mode {
        case .changeTree(let slot): return garden.tree(slot)
        default: return isChange ? proposal?.targetSlot.flatMap(garden.tree) : nil
        }
    }

    private var isOurTree: Bool { draft.isOurTree }

    private var navigationTitle: Text {
        switch mode {
        case .newPlaceTree:
            return Text("Plant a tree", comment: "Plant sheet title: a new tree for a place")
        case .ourTreeFirstPlanting:
            return Text("Plant your tree", comment: "Plant sheet title: the couple's first tree")
        case .editSeed:
            return Text("Edit seed", comment: "Plant sheet title: editing my own seed")
        case .counter:
            return Text("Your version", comment: "Plant sheet title: answering the partner's seed with my own version")
        case .changeTree:
            return Text("Suggest a change", comment: "Plant sheet title: suggesting a change to a planted tree")
        case .editChange:
            return Text("Edit your suggestion", comment: "Plant sheet title: editing my suggested change")
        }
    }

    private var ctaTitle: String {
        let name = garden.partnerName
        switch mode {
        case .newPlaceTree, .ourTreeFirstPlanting:
            return String(localized: "Send the seed to \(name)",
                          comment: "Plant sheet: the filled button. The placeholder is the partner's name.")
        case .editSeed:
            return String(localized: "Save seed", comment: "Plant sheet: the filled button when editing my seed")
        case .counter:
            return String(localized: "Send your version", comment: "Plant sheet: the filled button when answering with my version")
        case .changeTree:
            return String(localized: "Suggest this to \(name)",
                          comment: "Plant sheet: the filled button of a suggested change. The placeholder is the partner's name.")
        case .editChange:
            return String(localized: "Save suggestion", comment: "Plant sheet: the filled button when editing my suggested change")
        }
    }

    private var footer: String {
        let name = garden.partnerName
        if isChange {
            return String(localized: "It changes when \(name) agrees.",
                          comment: "Plant sheet footer for a suggested change. The placeholder is the partner's name.")
        }
        if case .counter = mode {
            return String(localized: "\(name) sees your version and plants it, or answers with theirs.",
                          comment: "Plant sheet footer when answering the partner's seed. The placeholder is the partner's name.")
        }
        return String(localized: "Nothing is planted until you both say yes.",
                      comment: "Plant sheet footer for a seed")
    }

    // MARK: Validity

    /// Why the filled control is disabled, if it is (other than offline).
    private var disabledHint: String? {
        if isOurTree, !isChange, draft.startDay == nil {
            return String(localized: "Choose the day your story began.",
                          comment: "Plant sheet: hint while Our tree has no start day")
        }
        if !isOurTree, draft.preset == .custom, draft.storedTitle.isEmpty {
            return String(localized: "Give it a name.", comment: "Plant sheet: hint while a custom tree has no title")
        }
        if mode == .newPlaceTree, myOpenSeedCount >= GardenLimits.maxOpenSeedsPerPerson {
            return GardenError.tooManySeeds.message(partnerName: garden.partnerName, now: garden.now)
        }
        return nil
    }

    /// The place seeds of mine that exist (countered ones included), as the
    /// sending transaction counts them.
    private var myOpenSeedCount: Int {
        garden.myOpenPlaceSeedCount
    }

    /// The version this form answers or edits is still the one shown.
    private var versionIsCurrent: Bool {
        switch mode {
        case .editSeed, .counter, .editChange: return proposal?.version != nil
        case .newPlaceTree, .ourTreeFirstPlanting, .changeTree: return true
        }
    }

    private var canSend: Bool {
        reachability.isOnline && disabledHint == nil && versionIsCurrent && !isSending
    }

    // MARK: Body

    var body: some View {
        Form {
            previewSection
            if !isOurTree {
                standsForSection
            }
            if isOurTree, !isChange {
                startDateSection
            }
            placeSection
            if !isOurTree {
                daySection
            }
            lookSection
            noteSection
            Section {
                EmptyView()
            } footer: {
                Text(footer)
                    .font(JourneyFont.meta)
                    .foregroundStyle(Brand.textSecondary)
            }
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(Brand.bgGradient.ignoresSafeArea())
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showsPicker) {
            GardenPlacePicker(garden: garden) { candidate in
                if let candidate { apply(candidate) }
                showsPicker = false
            }
        }
        // The sheet's one filled control, pinned under the content.
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if let line = statusLine {
                    Text(line)
                        .font(JourneyFont.meta)
                        .foregroundStyle(Brand.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                }
                BrandCTA(title: ctaTitle, icon: "leaf.fill", tier: .hero,
                         isEnabled: canSend, isBusy: isSending) {
                    send()
                }
                if !reachability.isOnline {
                    Text(GardenError.offline.message(partnerName: garden.partnerName, now: garden.now))
                        .font(JourneyFont.meta)
                        .foregroundStyle(Brand.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, Brand.Space.gutter)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .background(.bar)
        }
        .onDisappear {
            // The error was read here; Journey's strip need not repeat it.
            if showsError { garden.dismissError() }
        }
    }

    /// The inline error, else the disabled hint.
    private var statusLine: String? {
        if showsError, let message = garden.errorMessage { return message }
        return disabledHint
    }

    // MARK: Preview

    private var previewSection: some View {
        Section {
            GardenStillScene(look: draft.look, place: draft.place, stage: previewStage.stage,
                             daysTogether: previewStage.days,
                             treeKey: changedTree?.key ?? proposal?.key ?? "draft",
                             isOurTree: isOurTree)
                .frame(height: 150)
                .overlay(alignment: .topLeading) {
                    if let place = draft.place {
                        GardenPlaceChipLabel(text: place.name)
                            .padding(10)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Brand.cardCornerRadius, style: Brand.cornerStyle))
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(previewSpokenLabel)
        }
    }

    /// A sapling for a new tree; a planted tree's own stage for a change.
    private var previewStage: (stage: TreeGrowthStage, days: Int) {
        guard let tree = changedTree else { return (.sapling, TreeGrowthStage.sapling.startDay) }
        let start = tree.growthStart(ourStartDate: garden.anchor.startDate)
        let days = start.map { GardenDayCount.days(fromStored: $0, now: garden.now) } ?? 0
        return (TreeGrowthStage.from(daysTogether: days), days)
    }

    private var previewSpokenLabel: String {
        let look = GardenPlaceText.look(draft.look)
        return String(localized: "Preview: \(look)",
                      comment: "VoiceOver: the plant sheet's picture of the chosen look. The placeholder is like 'Seaside · Palm'.")
    }

    // MARK: Stands for

    private var standsForSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(GardenPreset.placePresets, id: \.self) { preset in
                        GardenChip(title: preset.chipTitle, isSelected: draft.preset == preset) {
                            select(preset)
                        }
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 16)
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

            VStack(alignment: .leading, spacing: 4) {
                Text("Name", comment: "Plant sheet: label of the tree's title field")
                    .font(JourneyFont.caption)
                    .foregroundStyle(Brand.textSecondary)
                TextField(text: titleBinding) {
                    Text("Our rainy café", comment: "Plant sheet: placeholder of a tree's own title. An example of a couple's own place name.")
                }
                .font(JourneyFont.title)
                .foregroundStyle(Brand.textPrimary)
                .textInputAutocapitalization(.sentences)
            }
        } header: {
            sectionHeader(LocalizedStringResource("What does it stand for?", comment: "Plant sheet section header: the moment or place a tree stands for"))
        }
    }

    private var titleBinding: Binding<String> {
        Binding(get: { draft.title },
                set: { draft.title = GardenLimits.title.truncate($0) })
    }

    // MARK: Start date (Our tree)

    private var startDateSection: some View {
        Section {
            DatePicker(selection: Binding(get: { draft.startDay ?? Date() },
                                          set: { draft.startDay = Calendar.current.startOfDay(for: $0) }),
                       in: ...Date(), displayedComponents: [.date]) {
                Text("Start date", comment: "Plant sheet: VoiceOver label of the start date calendar")
            }
            .datePickerStyle(.graphical)
            .tint(Brand.accentStart)
            .labelsHidden()
        } header: {
            sectionHeader(LocalizedStringResource("When did your story begin?", comment: "Plant sheet section header: Our tree's start date"))
        }
    }

    // MARK: Place

    private var placeSection: some View {
        Section {
            if let place = draft.place {
                HStack(spacing: 12) {
                    GardenSnapshotImage(place: place, scene: draft.look.scene, size: CGSize(width: 96, height: 64))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: Brand.cornerStyle))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.name)
                            .font(JourneyFont.label)
                            .foregroundStyle(Brand.textPrimary)
                        if let locality = place.locality, locality != place.name {
                            Text(locality)
                                .font(JourneyFont.meta)
                                .foregroundStyle(Brand.textSecondary)
                        }
                        Text(GardenPlaceText.precision(place.precision))
                            .font(JourneyFont.meta)
                            .foregroundStyle(Brand.textTertiary)
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 20) {
                    Button {
                        showsPicker = true
                    } label: {
                        Text("Change", comment: "Plant sheet: choose another place")
                    }
                    Button(role: .destructive) {
                        withAnimation(reduceMotion ? nil : .snappy) { removePlace() }
                    } label: {
                        Text("Remove", comment: "Plant sheet: remove the chosen place")
                    }
                }
                .font(JourneyFont.label)
                .buttonStyle(.borderless)
            } else {
                Button {
                    showsPicker = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(JourneyFont.title)
                            .foregroundStyle(Brand.accentStart)
                            .frame(width: 28)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Add a place", comment: "Plant sheet: open the place picker")
                                .font(JourneyFont.label)
                                .foregroundStyle(Brand.textPrimary)
                            Text("Search or drop a pin. Optional.", comment: "Plant sheet: under 'Add a place'")
                                .font(JourneyFont.meta)
                                .foregroundStyle(Brand.textSecondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.forward")
                            .font(JourneyFont.meta)
                            .foregroundStyle(Brand.textTertiary)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } header: {
            sectionHeader(LocalizedStringResource("Where is it?", comment: "Plant sheet section header: the tree's place"))
        }
    }

    // MARK: Day (place trees)

    private var daySection: some View {
        Section {
            if !dayUnknown {
                DatePicker(selection: Binding(get: { momentDay },
                                              set: { momentDay = Calendar.current.startOfDay(for: $0) }),
                           in: ...Date(), displayedComponents: [.date]) {
                    Text("Day", comment: "Plant sheet: label of the moment's day")
                        .font(JourneyFont.label)
                        .foregroundStyle(Brand.textPrimary)
                }
                .tint(Brand.accentStart)
            }
            Toggle(isOn: $dayUnknown.animation(reduceMotion ? nil : .snappy)) {
                Text("We're not sure of the day", comment: "Plant sheet: the tree's moment has no known day")
                    .font(JourneyFont.label)
                    .foregroundStyle(Brand.textPrimary)
            }
            .tint(Brand.accentStart)
            if let suggested = timelineDay, dayUnknown || !Calendar.current.isDate(suggested, inSameDayAs: momentDay) {
                Button {
                    momentDay = suggested
                    withAnimation(reduceMotion ? nil : .snappy) { dayUnknown = false }
                } label: {
                    Label {
                        Text("From your Timeline: \(GardenDayText.long(local: suggested))",
                             comment: "Plant sheet: tap to use the day of a matching Timeline memory. The placeholder is a date such as '14 February 2024'.")
                    } icon: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .font(JourneyFont.label)
                    .foregroundStyle(Brand.accentStart)
                }
                .buttonStyle(.borderless)
            }
        } header: {
            sectionHeader(LocalizedStringResource("When was it?", comment: "Plant sheet section header: the day of the tree's moment"))
        }
    }

    /// The Timeline's day for the chosen preset, if any (never in the future).
    private var timelineDay: Date? {
        guard let kind = draft.preset.prefillMemoryKind, let stored = timelineDays[kind] else { return nil }
        let day = JourneyCalendarDay.localDay(ofStored: stored)
        return day <= Date() ? day : nil
    }

    // MARK: Look

    private var lookSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(sceneOrder) { scene in
                        sceneCard(scene)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(speciesChoices) { species in
                        GardenChip(title: species.displayName, isSelected: draft.look.species == species) {
                            lookTouched = true
                            draft.look.species = species
                        }
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 16)
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
        } header: {
            sectionHeader(LocalizedStringResource("How should it look?", comment: "Plant sheet section header: the tree's scene and species"))
        }
    }

    /// The suggested scene first, then the rest in catalog order.
    private var sceneOrder: [GardenSceneID] {
        let suggested = suggestedScene
        return [suggested] + GardenSceneID.allCases.filter { $0 != suggested }
    }

    private var speciesChoices: [GardenSpecies] {
        isOurTree ? GardenSpecies.ourTreeChoices : GardenSpecies.allCases
    }

    private func sceneCard(_ scene: GardenSceneID) -> some View {
        let isSelected = draft.look.scene == scene
        return Button {
            lookTouched = true
            draft.look = GardenLook(scene: scene,
                                    species: speciesChoices.contains(draft.look.species)
                                        ? draft.look.species
                                        : GardenLook.suggested(scene: scene, forOurTree: isOurTree).species)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                GardenSceneSwatch(scene: scene, size: CGSize(width: 96, height: 64))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: Brand.cornerStyle))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: Brand.cornerStyle)
                            .strokeBorder(isSelected ? Brand.accentStart : Brand.divider, lineWidth: isSelected ? 2.5 : 1)
                    )
                Text(scene.displayName)
                    .font(JourneyFont.caption)
                    .foregroundStyle(isSelected ? Brand.accentStart : Brand.textPrimary)
                if scene == suggestedScene {
                    Text(suggestionLabel)
                        .font(JourneyFont.meta)
                        .foregroundStyle(Brand.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: 96, alignment: .leading)
        }
        .buttonStyle(BouncyButtonStyle(scale: 0.96))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var suggestedScene: GardenSceneID {
        let group = draft.place == nil || placeIsAddressOrPin ? nil : placeGroup
        return GardenLookSuggestion.scene(group: group, countryCode: placeCountry,
                                          preset: isOurTree ? .ourTree : draft.preset)
    }

    /// "Suggested for a café", "Suggested for this place", or "Suggested".
    private var suggestionLabel: String {
        guard let place = draft.place else {
            return String(localized: "Suggested", comment: "Plant sheet: under the suggested scene when there is no place")
        }
        if place.poiCategory == MKPointOfInterestCategory.cafe.rawValue {
            return String(localized: "Suggested for a café", comment: "Plant sheet: under the scene suggested for a café")
        }
        return String(localized: "Suggested for this place", comment: "Plant sheet: under the scene suggested for the chosen place")
    }

    // MARK: Note

    private var noteSection: some View {
        Section {
            TextField(text: Binding(get: { draft.note ?? "" },
                                    set: { draft.note = GardenLimits.seedNote.truncate($0) }),
                      axis: .vertical) {
                Text("Why this place?", comment: "Plant sheet: placeholder of the note to the partner")
            }
            .font(JourneyFont.body)
            .foregroundStyle(Brand.textPrimary)
            .lineLimit(2...6)
        } header: {
            sectionHeader(LocalizedStringResource("A note for \(garden.partnerName)",
                                                  comment: "Plant sheet section header: an optional note. The placeholder is the partner's name."))
        }
    }

    // MARK: Pieces

    private func sectionHeader(_ text: LocalizedStringResource) -> some View {
        Text(text)
            .font(JourneyFont.caption)
            .foregroundStyle(Brand.textSecondary)
    }

    // MARK: Actions

    private func select(_ preset: GardenPreset) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let previous = draft.preset
        let typed = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let keptDefault = typed.isEmpty || typed == previous.localizedDefaultTitle || typed == previous.storedDefaultTitle
        draft.preset = preset
        if keptDefault { draft.title = preset.localizedDefaultTitle }
        if !lookTouched { applySuggestedLook() }
    }

    private func apply(_ candidate: GardenPlaceCandidate) {
        draft.place = candidate.place
        placeGroup = candidate.group
        placeCountry = candidate.countryCode
        placeIsAddressOrPin = candidate.isAddressOrPin
        if !lookTouched { applySuggestedLook() }
    }

    private func removePlace() {
        draft.place = nil
        placeGroup = nil
        placeCountry = nil
        placeIsAddressOrPin = false
        if !lookTouched { applySuggestedLook() }
    }

    private func applySuggestedLook() {
        draft.look = GardenLook.suggested(scene: suggestedScene, forOurTree: isOurTree)
    }

    private func send() {
        var final = draft
        final.note = GardenLimits.seedNote.clean(draft.note)
        if !isOurTree { final.momentDay = dayUnknown ? nil : momentDay }
        isSending = true
        showsError = false
        Task {
            let succeeded = await garden.propose(final)
            isSending = false
            if succeeded {
                onDone()
            } else {
                showsError = true
            }
        }
    }
}

// MARK: - Still scene

/// A still frame of a look: the scene's cached layers, a tree at `stage`
/// on the knoll, at the place's (or the phone's) time of day. No clock and
/// no motion: the plant sheet's live preview.
struct GardenStillScene: View {

    let look: GardenLook
    let place: GardenPlace?
    let stage: TreeGrowthStage
    let daysTogether: Int
    let treeKey: String
    /// Our tree keeps today's silhouette (seeded from the days together).
    let isOurTree: Bool

    @Environment(\.displayScale) private var displayScale
    @State private var images: [GardenBackdropKey: CGImage] = [:]

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let environment = GardenSceneEnvironment.make(scene: look.scene, place: place,
                                                          treeKey: treeKey, now: Date())
            let info = look.scene.info
            let treeFrame = info.layout.treeFrame(in: size)
            let keys = Self.keys(scene: look.scene, environment: environment, size: size, scale: cacheScale)

            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [environment.sky.top.color, environment.sky.horizon.color],
                               startPoint: .top, endPoint: UnitPoint(x: 0.5, y: info.layout.horizon))
                Rectangle()
                    .fill(info.groundDay.mixed(with: info.groundNight, environment.sky.darkness).color)
                    .frame(width: size.width, height: max(0, size.height * (1 - info.layout.horizon)))
                    .offset(y: size.height * info.layout.horizon)

                layer(.far, keys: keys, size: size, darkness: environment.sky.darkness)
                layer(.near, keys: keys, size: size, darkness: environment.sky.darkness)

                RelationshipTreeCanvas(stage: stage,
                                       season: environment.season.treeSeason,
                                       daysTogether: daysTogether,
                                       memoryCount: 0,
                                       crownActive: false,
                                       style: .scene(species: look.species, sky: environment.sky,
                                                     season: environment.season,
                                                     topologySeed: isOurTree ? nil : environment.seed),
                                       clock: .external(time: 0, pose: .still))
                    .frame(width: treeFrame.width, height: treeFrame.height)
                    .offset(x: treeFrame.minX, y: treeFrame.minY)

                layer(.front, keys: keys, size: size, darkness: environment.sky.darkness)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipped()
            .task(id: keys) {
                // Per key, and never after cancellation: a look switched
                // away from stops loading at once and never overwrites the
                // look switched to (whose keys may all be in memory already).
                let kept = images.filter { keys.contains($0.key) }
                if kept.count != images.count { images = kept }
                for key in keys where images[key] == nil {
                    if Task.isCancelled { return }
                    guard let image = await GardenBackdropCache.shared.image(for: key) else { continue }
                    if Task.isCancelled { return }
                    images[key] = image
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// Landscapes are soft: at most 2× (the cache's own rule).
    private var cacheScale: Int { min(2, max(1, Int(displayScale.rounded(.up)))) }

    @ViewBuilder
    private func layer(_ layer: GardenBackdropLayer, keys: [GardenBackdropKey], size: CGSize, darkness: Double) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(keys.filter { $0.layer == layer }, id: \.self) { key in
                if let image = images[key] {
                    let scale = CGFloat(key.scale)
                    let width = CGFloat(image.width) / scale
                    let height = CGFloat(image.height) / scale
                    Image(decorative: image, scale: scale)
                        .resizable()
                        .frame(width: width, height: height)
                        // Far is wider than the band and centred; front sits on its bottom.
                        .offset(x: layer == .far ? -(width - size.width) / 2 : 0,
                                y: layer == .front ? size.height - height : 0)
                        .opacity(key.style.variant == .night ? darkness : 1)
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    /// The layers this frame needs: day while darkness < 1, night while > 0.
    private static func keys(scene: GardenSceneID, environment: GardenSceneEnvironment,
                             size: CGSize, scale: Int) -> [GardenBackdropKey] {
        guard size.width > 0, size.height > 0 else { return [] }
        var variants: [GardenSkyVariant] = []
        if environment.sky.darkness < 1 { variants.append(.day) }
        if environment.sky.darkness > 0 { variants.append(.night) }
        return variants.flatMap { variant in
            [GardenBackdropLayer.far, .near, .front].map { layer in
                GardenBackdropKey(scene: scene, layer: layer,
                                  style: GardenSceneStyle(variant: variant, season: environment.season),
                                  width: Int(size.width.rounded()), height: Int(size.height.rounded()), scale: scale)
            }
        }
    }
}

// MARK: - Shared pieces

/// A selectable capsule (presets, species).
struct GardenChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(JourneyFont.caption)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? Brand.accentStart.opacity(0.18) : Brand.surfaceMid)
                        .overlay(Capsule().strokeBorder(isSelected ? Brand.accentStart : Brand.divider, lineWidth: 1))
                )
                .foregroundStyle(isSelected ? Brand.accentStart : Brand.textSecondary)
        }
        .buttonStyle(BouncyButtonStyle(scale: 0.94))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The frosted place chip drawn over a scene (never inside a canvas).
struct GardenPlaceChipLabel: View {
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "mappin")
                .accessibilityHidden(true)
            Text(text)
                .lineLimit(1)
        }
        .font(JourneyFont.caption)
        .foregroundStyle(Brand.textPrimary)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(.regularMaterial))
        .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
    }
}

/// Day counts from a stored instant (a calendar day at 10:00 UTC, or any
/// instant), as Journey counts them: whole local days, never negative.
nonisolated enum GardenDayCount {
    static func days(fromStored stored: Date, now: Date, calendar: Calendar = .current) -> Int {
        let start = JourneyCalendarDay.localDay(ofStored: stored, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        return max(0, calendar.dateComponents([.day], from: start, to: today).day ?? 0)
    }
}

/// How the garden's sheets write days and places.
nonisolated enum GardenDayText {
    /// "12 March 2023" (in the reader's locale) for a local day.
    static func long(local day: Date) -> String {
        day.formatted(.dateTime.day().month(.wide).year())
    }

    /// "12 March 2023" for a stored calendar day.
    static func long(stored: Date) -> String {
        long(local: JourneyCalendarDay.localDay(ofStored: stored))
    }

    /// "12 MAR 2023": a postmark's day.
    static func postmark(stored: Date) -> String {
        JourneyCalendarDay.localDay(ofStored: stored)
            .formatted(.dateTime.day().month(.abbreviated).year())
            .uppercased()
    }
}

nonisolated enum GardenPlaceText {
    /// "Exact spot" / "The area".
    static func precision(_ precision: GardenPlacePrecision) -> String {
        switch precision {
        case .exact: return String(localized: "Exact spot", comment: "A garden place keeps its exact position")
        case .area:  return String(localized: "The area", comment: "A garden place keeps only its area (about 1 km)")
        }
    }

    /// "Seaside · Palm".
    static func look(_ look: GardenLook) -> String {
        String(localized: "\(look.scene.displayName) · \(look.species.displayName)",
               comment: "A tree's look: its scene, then its species, as in 'Seaside · Palm'")
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Plant a tree") {
    GardenPlantSheet(garden: GardenPreviewGarden.make(), mode: .newPlaceTree)
}

#Preview("Plant your tree") {
    GardenPlantSheet(garden: GardenPreviewGarden.make(startDay: nil), mode: .ourTreeFirstPlanting)
}

/// A paired view model on the in-memory service, for previews only.
enum GardenPreviewGarden {
    static func make(startDay: Date? = Calendar.current.date(byAdding: .day, value: -300, to: Date())) -> GardenViewModel {
        let session = UserSession(userId: "previewme", coupleId: "previewcouple", partnerId: "labpartner")
        let garden = GardenViewModel(session: session, service: InMemoryGardenService(startDay: startDay))
        garden.start()
        return garden
    }
}
#endif
