//
//  GardenLabView.swift
//  Coupley
//
//  DEBUG only (spec K6): the garden lab, reached from the Debug menu. It
//  runs on InMemoryGardenService (never writes Firestore): clock offset,
//  scripted partner, effects, scenes, species, the ceremony, and the
//  Reminders and Backdrop viewers. Absent from Release builds.
//
//  The lab's own garden lives in `GardenLab` for as long as the lab is
//  open: a paired lab session (never `UserSession.demo`, which the garden
//  treats as unavailable) on the in-memory service, driven through the
//  same hero, requests and sheets Journey shows. The Reminders and
//  Backdrop viewers read the REAL system state: the pending and delivered
//  tt.garden.* requests and the live backdrop cache.
//
//  Developer tools, English only: every string is verbatim, so none of it
//  reaches the app's string catalog or its translators.
//

#if DEBUG
import Foundation
import SwiftUI
import UIKit
import Combine
import QuartzCore
import UserNotifications

// MARK: - The lab's garden

/// The in-memory garden and the lab's clock.
@MainActor
final class GardenLab: ObservableObject {

    private(set) var service: InMemoryGardenService
    @Published private(set) var garden: GardenViewModel

    /// Hours added to the in-memory service's clock.
    @Published private(set) var offsetHours: Double = 0
    @Published private(set) var timeScale: Int = 1
    @Published var delayNextCommit = false {
        didSet { service.delayNextCommit = delayNextCommit }
    }
    @Published var partnerIsLegacy = false {
        didSet { service.simulatePartner(.pretendLegacy(partnerIsLegacy)) }
    }

    private var clockTask: Task<Void, Never>?

    /// A paired session that is not the demo one (the garden is unavailable there).
    static let session = UserSession(userId: "labMe", coupleId: "labCouple", partnerId: "labSam")

    init() {
        Self.forgetLabCouple()
        let service = InMemoryGardenService()
        self.service = service
        garden = GardenViewModel(session: Self.session, service: service)
    }

    /// Each lab session starts as fresh as its in-memory garden. The keys
    /// the view model keeps per couple (the offline cache, ceremonies seen,
    /// the selected page...) would otherwise bring the last session's trees
    /// into this one, where the in-memory service no longer has them.
    private static func forgetLabCouple() {
        let defaults = UserDefaults.standard
        let marker = "." + session.coupleId
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix(GardenDefaultsKey.prefix) && key.contains(marker) {
            defaults.removeObject(forKey: key)
        }
    }

    func start() {
        garden.start()
    }

    /// A fresh garden: an existing couple (a start date 300 days ago), or a
    /// new couple without one (the "Plant your first tree together" flow).
    func startOver(withStartDate: Bool) {
        stop()
        Self.forgetLabCouple()
        let startDay = withStartDate ? Calendar.current.date(byAdding: .day, value: -300, to: Date()) : nil
        service = InMemoryGardenService(startDay: startDay)
        garden = GardenViewModel(session: Self.session, service: service)
        offsetHours = 0
        timeScale = 1
        delayNextCommit = false
        partnerIsLegacy = false
        garden.start()
    }

    func stop() {
        clockTask?.cancel()
        clockTask = nil
        garden.stop()
    }

    func setOffset(hours: Double) {
        offsetHours = hours
        service.clockOffset = hours * GardenCadence.hour
        garden.refreshClock()
    }

    /// 60×: a minute of garden time passes every second.
    func setTimeScale(_ scale: Int) {
        timeScale = scale
        clockTask?.cancel()
        guard scale > 1 else { return }
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                self.service.clockOffset += TimeInterval(scale - 1)
                self.offsetHours = self.service.clockOffset / GardenCadence.hour
                self.garden.refreshClock()
            }
        }
    }

    func partner(_ action: GardenLabAction) {
        service.simulatePartner(action)
    }
}

// MARK: - Lab

struct GardenLabView: View {

    /// `opensJourney`: push the in-memory Journey once, on the first
    /// appearance (the `-coupleyOpen gardenJourney` launch argument).
    init(opensJourney: Bool = false) {
        self.opensJourney = opensJourney
    }

    private let opensJourney: Bool
    @State private var showsJourney = false
    @State private var didOpenJourney = false
    @StateObject private var lab = GardenLab()
    @State private var showsHUD = false
    @State private var seedPreset: GardenPreset = .firstDate
    @State private var restSlot: GardenSlot = .p1
    @State private var suggestedDay = Calendar.current.date(byAdding: .month, value: -14, to: Date()) ?? Date()
    @State private var legacyDay = Calendar.current.date(byAdding: .month, value: -15, to: Date()) ?? Date()

    var body: some View {
        List {
            Section {
                NavigationLink {
                    GardenLabJourney(garden: lab.garden)
                } label: {
                    labLabel("Journey (in-memory garden)", "The hero, requests and every sheet")
                }
                labButton("Start over: existing couple") { lab.startOver(withStartDate: true) }
                labButton("Start over: new couple (no start date)") { lab.startOver(withStartDate: false) }
            } header: {
                Text(verbatim: "Garden")
            }

            clockSection
            partnerSection

            Section {
                NavigationLink { GardenLabEffects(garden: lab.garden) } label: {
                    labLabel("Effects", "Each effect, the first drop, a replay, the ripple, Reduce Motion")
                }
                NavigationLink { GardenLabScenes() } label: {
                    labLabel("Scene gallery", "8 scenes × time of day × season × light/dark")
                }
                NavigationLink { GardenLabSpecies() } label: {
                    labLabel("Species gallery", "5 species × 8 stages × thirst, letters on/off")
                }
                NavigationLink { GardenLabCeremonies(garden: lab.garden) } label: {
                    labLabel("Ceremony replay", "The planting ceremony for any tree")
                }
            } header: {
                Text(verbatim: "Looks")
            }

            Section {
                NavigationLink { GardenLabReminders() } label: {
                    labLabel("Reminders", "Pending and delivered tt.garden.* on this device")
                }
                NavigationLink { GardenLabBackdrops() } label: {
                    labLabel("Backdrop", "Memory and disk tiers of the scene cache")
                }
                Toggle(isOn: $showsHUD) {
                    Text(verbatim: "Frame-time HUD")
                }
            } header: {
                Text(verbatim: "System")
            }
        }
        .navigationTitle(Text(verbatim: "Garden Lab"))
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .topTrailing) {
            if showsHUD {
                GardenFrameHUD()
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        // Never stopped on disappear: pushing the Journey, Effects or
        // Ceremony page fires onDisappear here, and those pages run on this
        // same garden. The lab and its garden are released when it closes.
        .onAppear {
            lab.start()
            if opensJourney, !didOpenJourney {
                didOpenJourney = true
                showsJourney = true
            }
        }
        .navigationDestination(isPresented: $showsJourney) {
            GardenLabJourney(garden: lab.garden)
        }
    }

    // MARK: Clock

    private var clockSection: some View {
        Section {
            Picker(selection: Binding(get: { lab.offsetHours }, set: { lab.setOffset(hours: $0) })) {
                ForEach([0.0, 47, 71, 167, 200], id: \.self) { hours in
                    Text(verbatim: hours == 0 ? "Now" : "+\(Int(hours)) h").tag(hours)
                }
            } label: {
                Text(verbatim: "Clock offset")
            }
            .pickerStyle(.segmented)

            Picker(selection: Binding(get: { lab.timeScale }, set: { lab.setTimeScale($0) })) {
                Text(verbatim: "1×").tag(1)
                Text(verbatim: "60×").tag(60)
            } label: {
                Text(verbatim: "Time scale")
            }
            .pickerStyle(.segmented)

            Text(verbatim: String(format: "Offset: %.1f h", lab.offsetHours))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        } header: {
            Text(verbatim: "Clock")
        }
    }

    // MARK: Scripted partner

    private var partnerSection: some View {
        Section {
            labButton("Sam waters") { lab.partner(.water(note: nil)) }
            labButton("Sam waters with a note") { lab.partner(.water(note: "Thinking of our first coffee.")) }

            Picker(selection: $seedPreset) {
                ForEach(GardenPreset.placePresets, id: \.self) { preset in
                    Text(verbatim: preset.rawValue).tag(preset)
                }
            } label: {
                Text(verbatim: "Seed preset")
            }
            labButton("Sam sends a seed") { lab.partner(.sendSeed(seedPreset)) }
            labButton("Sam counters the latest seed") { lab.partner(.counterLatestSeed) }
            labButton("Sam takes the latest seed back and re-sends it (ABA)") { lab.partner(.recreateLatestSeed) }

            Picker(selection: $restSlot) {
                ForEach(GardenSlot.placeSlots) { slot in
                    Text(verbatim: slot.rawValue).tag(slot)
                }
            } label: {
                Text(verbatim: "Tree to rest")
            }
            labButton("Sam asks to let it rest") { lab.partner(.askRest(restSlot)) }

            DatePicker(selection: $suggestedDay, in: ...Date(), displayedComponents: .date) {
                Text(verbatim: "Suggested start date")
            }
            labButton("Sam suggests this start date") {
                lab.partner(.suggestStartDate(JourneyCalendarDay.storedMoment(forLocalDay: suggestedDay)))
            }

            DatePicker(selection: $legacyDay, in: ...Date(), displayedComponents: .date) {
                Text(verbatim: "1.2 start date")
            }
            labButton("Write the start date like 1.2") { lab.partner(.writeStartDateLikeLegacy(legacyDay)) }

            Toggle(isOn: $lab.partnerIsLegacy) {
                Text(verbatim: "Pretend Sam is on 1.2")
            }
            Toggle(isOn: $lab.delayNextCommit) {
                Text(verbatim: "Delay the next commit 3 s")
            }
        } header: {
            Text(verbatim: "Scripted partner")
        }
    }

    private func labButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title)
        }
    }
}

/// A row title and a one-line explanation.
private func labLabel(_ title: String, _ subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        Text(verbatim: title)
        Text(verbatim: subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

/// Every page animates: the lab shows one page at a time.
private func labGate(reduceMotion: Bool = false) -> GardenMotionGate {
    GardenMotionGate(isSelectedPage: true, heroVisible: true, tabShown: true, journeySheetPresented: false,
                     sceneActive: true, lowPower: false, reduceMotion: reduceMotion)
}

// MARK: - Journey on the lab's garden

/// The hero, the requests and every garden sheet, routed exactly as
/// Journey routes them, on the in-memory garden.
private struct GardenLabJourney: View {

    @ObservedObject var garden: GardenViewModel

    @State private var sheet: GardenSheetRoute?
    @State private var staged: GardenSheetRoute?
    @State private var noteDraft = GardenNoteDraft()
    @State private var pendingNote: String?
    @State private var showsStartDate = false
    @State private var startDay = Date()
    @State private var guide: (stage: TreeGrowthStage, days: Int, isPlaceTree: Bool)?

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let error = garden.errorMessage {
                        Button {
                            garden.dismissError()
                        } label: {
                            Text(verbatim: "\(error)  (tap to dismiss)")
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                        .padding(.horizontal, Brand.Space.gutter)
                    }
                    GardenHero(garden: garden,
                               isCovered: sheet != nil || showsStartDate || guide != nil || garden.ceremony != nil,
                               journey: GardenHeroJourney(startDate: nil, daysTogether: nil, stage: nil, memoryCount: 3,
                                                          letters: .unavailable(), isCompact: false,
                                                          noteDrafted: noteDraft.isDrafted),
                               actions: GardenHeroActions(
                                onOpenSheet: { open($0) },
                                onWater: {
                                    let note = GardenLimits.wateringNote.clean(noteDraft.text)
                                    noteDraft.text = ""
                                    garden.water(note: note)
                                },
                                onEditStartDate: { showsStartDate = true },
                                onShowTreeGuide: { guide = ($0, $1, $2) },
                                onReplyInChat: {},
                                onTellPartner: { Task { _ = await garden.tellPartnerToUpdate() } }))
                        .padding(.horizontal, SurfaceTier.hero.gutter)
                        .padding(.top, Brand.Space.sibling)
                    GardenRequestsSection(garden: garden,
                                          onOpenRequest: { open(.seed(id: $0)) },
                                          onOpenGarden: { open(.garden) },
                                          onChoosePlace: { open(.plant(.changeTree(.our))) },
                                          onTellPartner: { Task { _ = await garden.tellPartnerToUpdate() } })
                        .padding(.horizontal, Brand.Space.gutter)
                    Color.clear.frame(height: 40)
                }
            }
            .background(Brand.bgGradient.ignoresSafeArea())

            if let ceremony = garden.ceremony {
                PlantingCeremonyOverlay(ceremony: ceremony, partnerName: garden.partnerName, myName: nil,
                                        onDone: { garden.acknowledgeCeremony() })
                    .transition(.opacity)
                    .zIndex(901)
            }
        }
        .navigationTitle(Text(verbatim: "Lab Journey"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sheet, onDismiss: sheetDidDismiss) { route in
            GardenRouteSheet(route: route, garden: garden, noteDraft: noteDraft,
                             handOver: { next in
                                 staged = next
                                 sheet = nil
                             },
                             onWater: { pendingNote = $0 },
                             onClose: { sheet = nil })
        }
        .sheet(isPresented: $showsStartDate) {
            NavigationStack {
                Form {
                    DatePicker(selection: $startDay, in: ...Date(), displayedComponents: .date) {
                        Text(verbatim: "New start date")
                    }
                    .datePickerStyle(.graphical)
                    Button {
                        Task {
                            if await garden.suggestStartDate(day: startDay, note: nil) { showsStartDate = false }
                        }
                    } label: {
                        Text(verbatim: "Suggest this date")
                    }
                }
                .navigationTitle(Text(verbatim: "Start date (lab)"))
            }
        }
        .sheet(isPresented: Binding(get: { guide != nil }, set: { if !$0 { guide = nil } })) {
            if let guide {
                JourneyTreeGuideSheet(stage: guide.stage, daysTogether: guide.days, partnerName: garden.partnerName,
                                      growsFromPlanting: guide.isPlaceTree)
            }
        }
    }

    private func open(_ route: GardenSheetRoute) {
        guard sheet == nil, !showsStartDate else { return }
        sheet = route
    }

    private func sheetDidDismiss() {
        if let next = staged {
            staged = nil
            sheet = next
        } else if let note = pendingNote {
            pendingNote = nil
            noteDraft.text = ""
            garden.water(note: GardenLimits.wateringNote.clean(note))
        }
    }
}

// MARK: - Effects

/// Each effect on the selected tree, the golden first drop, a replay, the
/// many-trees ripple and the Reduce Motion version.
private struct GardenLabEffects: View {

    @ObservedObject var garden: GardenViewModel

    @State private var playback: GardenEffectPlayback?
    @State private var reduceMotion = false
    @State private var rippleStart: TimeInterval?

    private var page: GardenPageModel {
        garden.hero.pages.first { $0.slot == garden.selectedSlot }
            ?? garden.hero.pages.first
            ?? .meadow(key: "lab-effects", now: garden.now)
    }

    var body: some View {
        List {
            Section {
                GardenScenePage(page: page, gate: labGate(reduceMotion: reduceMotion), playback: playback,
                                subject: .tree(GardenPageTree(stage: .blooming, daysTogether: 200, memoryCount: 3,
                                                              crownActive: false, ornaments: [], onSelectOrnament: nil)))
                    .frame(height: 208)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                Toggle(isOn: $reduceMotion) {
                    Text(verbatim: "Reduce Motion preview")
                }
            }

            Section {
                ForEach(GardenEffect.allCases, id: \.self) { effect in
                    Button {
                        play(effect)
                    } label: {
                        Text(verbatim: "\(effect.rawValue) (\(String(format: "%.1f", effect.duration)) s)")
                    }
                }
                Button { play(.can, firstEver: true) } label: { Text(verbatim: "The golden first drop") }
                Button { play(.rainCloud, replay: true) } label: { Text(verbatim: "A replay (rain cloud)") }
            } header: {
                Text(verbatim: "Play")
            }

            Section {
                HStack(spacing: 6) {
                    ForEach(0..<4, id: \.self) { index in
                        Capsule()
                            .fill(Color.secondary.opacity(index == 0 ? 0.9 : 0.5))
                            .frame(width: index == 0 ? 16 : 6, height: 6)
                    }
                }
                .padding(8)
                .overlay {
                    if let rippleStart { GardenDotRipple(dotCount: 4, startTime: rippleStart) }
                }
                .frame(maxWidth: .infinity)
                Button {
                    rippleStart = Date().timeIntervalSinceReferenceDate
                } label: {
                    Text(verbatim: "Ripple across 4 dots")
                }
            } header: {
                Text(verbatim: "Many trees")
            }
        }
        .navigationTitle(Text(verbatim: "Effects"))
    }

    private func play(_ effect: GardenEffect, firstEver: Bool = false, replay: Bool = false) {
        let next = GardenEffectPlayback(wateringId: UUID().uuidString, effect: effect,
                                        startTime: Date().timeIntervalSinceReferenceDate,
                                        isReplay: replay, isFirstEver: firstEver, byPartner: replay, treeCount: 4)
        playback = next
        GardenHaptics.shared.play(next)
    }
}

// MARK: - Scenes

/// Every scene at any hour, season and appearance.
private struct GardenLabScenes: View {

    @State private var scene: GardenSceneID = .meadow
    @State private var hour: Double = 12
    @State private var season: GardenSceneSeason = .summer
    @State private var dark = false

    var body: some View {
        List {
            Section {
                GardenScenePage(page: page, gate: labGate(),
                                subject: .tree(GardenPageTree(stage: .fruiting, daysTogether: 400, memoryCount: 0,
                                                              crownActive: false, ornaments: [], onSelectOrnament: nil)))
                    .frame(height: 208)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .environment(\.colorScheme, dark ? .dark : .light)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                GardenScenePage(page: page, gate: labGate(),
                                subject: .tree(GardenPageTree(stage: .fruiting, daysTogether: 400, memoryCount: 0,
                                                              crownActive: false, ornaments: [], onSelectOrnament: nil)))
                    .frame(width: 280, height: 168)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .environment(\.colorScheme, dark ? .dark : .light)
                    .frame(maxWidth: .infinity)
            }

            Section {
                Picker(selection: $scene) {
                    ForEach(GardenSceneID.allCases) { Text(verbatim: $0.rawValue).tag($0) }
                } label: {
                    Text(verbatim: "Scene")
                }
                Picker(selection: $season) {
                    ForEach(GardenSceneSeason.allCases, id: \.self) { Text(verbatim: $0.rawValue).tag($0) }
                } label: {
                    Text(verbatim: "Season")
                }
                VStack(alignment: .leading) {
                    Text(verbatim: String(format: "%02d:%02d", Int(hour), Int((hour - floor(hour)) * 60)))
                        .font(.caption.monospacedDigit())
                    Slider(value: $hour, in: 0...23.99)
                }
                Toggle(isOn: $dark) {
                    Text(verbatim: "Dark appearance")
                }
            }
        }
        .navigationTitle(Text(verbatim: "Scenes"))
    }

    private var page: GardenPageModel {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let midnight = calendar.startOfDay(for: Date())
        let date = midnight.addingTimeInterval(hour * GardenCadence.hour)
        var page = GardenPageModel.meadow(key: "lab-scene", now: date)
        page.look = GardenLook(scene: scene, species: scene.info.defaultSpecies)
        page.environment = GardenSceneEnvironment(scene: scene, season: season,
                                                  sky: GardenSky.state(at: date, in: .current),
                                                  seed: JourneyTreeOrnament.stableSeed("lab-scene"))
        return page
    }
}

// MARK: - Species

/// Five species through eight stages, at three levels of thirst. Thirst is
/// passed to the painter directly, so artists can still review the thirsty
/// and resting look the app draws only with
/// `GardenTreeLook.withersWhenThirsty` (off: owner decision 3).
private struct GardenLabSpecies: View {

    @State private var species: GardenSpecies = .oak
    @State private var thirst: Double = 0
    @State private var letters = true

    private static let sampleLetters: [JourneyTreeOrnament] = [
        ("lab-sealed-partner", JourneyTreeOrnament.Kind.sealedEnvelope, JourneyLetterDirection.toMe),
        ("lab-sealed-me", .sealedEnvelope, .fromMe),
        ("lab-ready-partner", .readyEnvelope, .toMe),
        ("lab-opened", .blossom, .toMe)
    ].map { JourneyTreeOrnament(id: $0.0, kind: $0.1, direction: $0.2, seed: JourneyTreeOrnament.stableSeed($0.0)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Picker(selection: $species) {
                    ForEach(GardenSpecies.allCases) { Text(verbatim: $0.rawValue).tag($0) }
                } label: {
                    Text(verbatim: "Species")
                }
                .pickerStyle(.segmented)
                Picker(selection: $thirst) {
                    Text(verbatim: "Fresh").tag(0.0)
                    Text(verbatim: "Thirsty").tag(0.5)
                    Text(verbatim: "Resting").tag(1.0)
                } label: {
                    Text(verbatim: "Thirst")
                }
                .pickerStyle(.segmented)
                if !GardenTreeLook.withersWhenThirsty {
                    Text(verbatim: "The app never draws thirst (GardenTreeLook.withersWhenThirsty is off): an unwatered tree keeps its plain look. Thirsty and Resting show the switched-off look.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Toggle(isOn: $letters) {
                    Text(verbatim: "Letters (Our tree's species only)")
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                    ForEach(TreeGrowthStage.allCases, id: \.self) { stage in
                        VStack(spacing: 4) {
                            RelationshipTreeCanvas(
                                stage: stage,
                                season: .current(),
                                daysTogether: stage.startDay + 20,
                                memoryCount: letters && species.canBeOurTree ? 6 : 0,
                                crownActive: species.canBeOurTree && stage.showsAmbientCrown,
                                ornaments: letters && species.canBeOurTree ? Self.sampleLetters : [],
                                onSelectOrnament: { _ in },
                                style: TreeCanvasStyle(species: species, backdrop: .automatic, drawsGround: true,
                                                       glow: .always, topologySeed: nil),
                                vitality: TreeVitality(thirst: thirst, wetness: 0, dew: 0,
                                                       soilDryness: thirst > 0 ? 1 : 0)
                            )
                            .frame(width: 150, height: 160)
                            .overlay(Rectangle().strokeBorder(Color.secondary.opacity(0.3), lineWidth: 0.5))
                            Text(verbatim: "\(stage)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle(Text(verbatim: "Species"))
    }
}

// MARK: - Ceremony

/// The planting ceremony for any tree of the lab's garden, or a sample.
private struct GardenLabCeremonies: View {

    @ObservedObject var garden: GardenViewModel
    @State private var ceremony: GardenCeremony?

    private var trees: [GardenTree] {
        let planted = garden.docs.trees
        guard planted.isEmpty else { return planted }
        let place = GardenPlace(name: "Café Giảng", locality: "Hoàn Kiếm, Hà Nội", latitude: 21.0337,
                                longitude: 105.8540, precision: .exact, poiCategory: nil,
                                timeZoneId: "Asia/Ho_Chi_Minh")
        var sample = GardenTree.unrecordedOurTree(startDate: Date(timeIntervalSinceNow: -500 * 86_400))
        sample.place = place
        return [sample]
    }

    var body: some View {
        ZStack {
            List {
                ForEach(trees) { tree in
                    Button {
                        ceremony = GardenCeremony(slot: tree.slot, key: tree.key, title: tree.displayTitle,
                                                  place: tree.place, look: tree.look,
                                                  growthStart: tree.growthStart(ourStartDate: tree.agreedStartDay),
                                                  momentDay: tree.isOurTree ? nil : tree.momentDay,
                                                  plantedAt: tree.plantedAt ?? Date(),
                                                  plantedByNames: ["Alex", "Sam"], isOurTree: tree.isOurTree)
                    } label: {
                        Text(verbatim: "\(tree.displayTitle) (\(tree.slot.rawValue))")
                    }
                }
            }
            if let ceremony {
                PlantingCeremonyOverlay(ceremony: ceremony, partnerName: "Sam", myName: "Alex",
                                        onDone: { self.ceremony = nil })
                    .transition(.opacity)
            }
        }
        .navigationTitle(Text(verbatim: "Ceremony"))
    }
}

// MARK: - Reminders viewer

/// The real pending and delivered tt.garden.* requests, the stored
/// watering time, and the push-wake and stale-plan checks (K5.11).
private struct GardenLabReminders: View {

    private struct Row: Identifiable {
        let id: String
        let identifier: String
        let when: Date?
        let wateringId: String?
        let body: String
    }

    @State private var pending: [Row] = []
    @State private var delivered: [Row] = []
    @State private var coupleId: String?
    @State private var storedMs: Int64?
    @State private var pushAgoHours: Double = 0

    var body: some View {
        List {
            Section {
                labeled("Active couple", coupleId ?? "none (not bound)")
                labeled("lastWateringMs", storedMs.map { "\($0)  (\(format(Date(timeIntervalSince1970: TimeInterval($0) / 1000))))" } ?? "none")
            } header: {
                Text(verbatim: "Stored")
            }

            Section {
                if pending.isEmpty { Text(verbatim: "None").foregroundStyle(.secondary) }
                ForEach(pending) { rowView($0) }
            } header: {
                Text(verbatim: "Pending")
            }

            Section {
                if delivered.isEmpty { Text(verbatim: "None").foregroundStyle(.secondary) }
                ForEach(delivered) { rowView($0) }
            } header: {
                Text(verbatim: "Delivered")
            }

            Section {
                Button {
                    Task {
                        WidgetSyncService.shared.gardenRemindersPreferenceChanged()
                        await WidgetSyncService.shared.reminderWorkSettled()
                        await reload()
                    }
                } label: {
                    Text(verbatim: "Re-plan now")
                }
                Picker(selection: $pushAgoHours) {
                    Text(verbatim: "now").tag(0.0)
                    Text(verbatim: "−1 h").tag(1.0)
                    Text(verbatim: "−47 h").tag(47.0)
                } label: {
                    Text(verbatim: "Watered")
                }
                .pickerStyle(.segmented)
                Button {
                    simulatePush(wateredAt: Date(timeIntervalSinceNow: -pushAgoHours * GardenCadence.hour),
                                 wateringId: "lab-\(UUID().uuidString.prefix(8))")
                } label: {
                    Text(verbatim: "Simulate a watering push")
                }
                .disabled(coupleId == nil)
                Button {
                    guard let storedMs else { return }
                    simulatePush(wateredAt: Date(timeIntervalSince1970: TimeInterval(storedMs - 3_600_000) / 1000),
                                 wateringId: "lab-older")
                } label: {
                    Text(verbatim: "Simulate an older snapshot (nothing may change)")
                }
                .disabled(coupleId == nil || storedMs == nil)
            } header: {
                Text(verbatim: "Actions")
            }
        }
        .navigationTitle(Text(verbatim: "Reminders"))
        .refreshable { await reload() }
        .task { await reload() }
    }

    private func simulatePush(wateredAt: Date, wateringId: String) {
        guard let coupleId else { return }
        let ms = Int64((wateredAt.timeIntervalSince1970 * 1000).rounded())
        Task {
            await GardenReminderScheduler.replanFromPush(coupleId: coupleId, wateredAtMs: String(ms),
                                                          wateringId: wateringId)
            await reload()
        }
    }

    private func reload() async {
        let defaults = UserDefaults.standard
        coupleId = defaults.string(forKey: GardenDefaultsKey.activeCoupleId)
        storedMs = coupleId.flatMap { GardenReminderScheduler.storedLastWateringMs(coupleId: $0) }

        let center = UNUserNotificationCenter.current()
        pending = await center.pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix(GardenNotification.reminderPrefix) }
            .map { request in
                Row(id: "p." + request.identifier, identifier: request.identifier,
                    when: (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate(),
                    wateringId: request.content.userInfo[GardenNotification.wateringIdKey] as? String,
                    body: request.content.body)
            }
        delivered = await center.deliveredNotifications()
            .filter { $0.request.identifier.hasPrefix(GardenNotification.reminderPrefix) }
            .map { note in
                Row(id: "d." + note.request.identifier, identifier: note.request.identifier, when: note.date,
                    wateringId: note.request.content.userInfo[GardenNotification.wateringIdKey] as? String,
                    body: note.request.content.body)
            }
    }

    private func rowView(_ row: Row) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: row.identifier).font(.footnote.monospaced())
            Text(verbatim: row.when.map(format) ?? "no date").font(.caption)
            Text(verbatim: "wateringId: \(row.wateringId ?? "none")").font(.caption.monospaced())
            Text(verbatim: row.body).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func labeled(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: label).foregroundStyle(.secondary)
            Spacer()
            Text(verbatim: value).font(.caption.monospaced()).multilineTextAlignment(.trailing)
        }
    }

    private func format(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .standard)
    }
}

// MARK: - Backdrop viewer

/// The scene cache's tiers against their budgets (K5.14).
private struct GardenLabBackdrops: View {

    @Environment(\.displayScale) private var displayScale
    @State private var stats = GardenBackdropCache.shared.stats
    @State private var width: CGFloat = 0

    /// The hero's band on this screen: full width less the hero's gutters.
    private var budget: Int {
        let band = CGSize(width: max(0, width - 2 * SurfaceTier.hero.gutter), height: 208)
        return GardenBackdropBudget.memoryCostLimit(band: band, scale: min(2, max(1, Int(displayScale.rounded()))))
    }

    var body: some View {
        List {
            Section {
                labeled("Memory", "\(bytes(stats.memoryBytes)) of \(bytes(budget))")
                labeled("Disk", "\(bytes(stats.diskBytes)) of \(bytes(GardenBackdropBudget.diskLimitBytes))")
                labeled("Hits", "\(stats.hits)")
                labeled("Misses", "\(stats.misses)")
                labeled("Renders", "\(stats.renders)")
            } header: {
                Text(verbatim: "Since launch")
            }
            Section {
                Button {
                    GardenBackdropCache.shared.removeAll()
                    stats = GardenBackdropCache.shared.stats
                } label: {
                    Text(verbatim: "Clear memory")
                }
                Button(role: .destructive) {
                    GardenBackdropCache.shared.clearDisk()
                    stats = GardenBackdropCache.shared.stats
                } label: {
                    Text(verbatim: "Clear disk")
                }
                Button {
                    stats = GardenBackdropCache.shared.stats
                } label: {
                    Text(verbatim: "Refresh")
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .navigationTitle(Text(verbatim: "Backdrop"))
    }

    private func bytes(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .memory)
    }

    private func labeled(_ label: String, _ value: String) -> some View {
        HStack {
            Text(verbatim: label).foregroundStyle(.secondary)
            Spacer()
            Text(verbatim: value).font(.callout.monospacedDigit())
        }
    }
}

// MARK: - Frame-time HUD

/// Frames per second and the worst frame of the last second, from a
/// CADisplayLink.
@MainActor
private final class GardenFrameMeter: NSObject, ObservableObject {

    @Published private(set) var fps = 0
    @Published private(set) var worstMs = 0.0

    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var windowStart: CFTimeInterval = 0
    private var frames = 0
    private var worst: CFTimeInterval = 0

    func start() {
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
        last = 0
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        if last > 0 {
            worst = max(worst, now - last)
            frames += 1
        } else {
            windowStart = now
        }
        last = now
        if now - windowStart >= 1 {
            fps = frames
            worstMs = worst * 1000
            frames = 0
            worst = 0
            windowStart = now
        }
    }
}

private struct GardenFrameHUD: View {
    @StateObject private var meter = GardenFrameMeter()

    var body: some View {
        Text(verbatim: String(format: "%d fps · worst %.1f ms", meter.fps, meter.worstMs))
            .font(.caption2.monospacedDigit())
            .foregroundStyle(meter.worstMs > 16.7 ? Color.red : Color.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.black.opacity(0.7)))
            .onAppear { meter.start() }
            .onDisappear { meter.stop() }
    }
}
#endif
