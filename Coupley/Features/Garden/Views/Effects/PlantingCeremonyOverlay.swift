//
//  PlantingCeremonyOverlay.swift
//  Coupley
//
//  P8: the planting ceremony (spec B5.8, C8), with its Reduce Motion and
//  VoiceOver versions. Full screen over Journey, conventions of
//  CrownCelebrationOverlay: a 0.75 black dim, modal for VoiceOver, the
//  escape gesture closes it, `.screenChanged` on appear, and room for the
//  ad banner under the button.
//
//  The band (full width − 32 pt × 300 pt) is the tree's own place: its sky
//  at the place's hour, the scene's cached landscape (a flat ground band
//  while it loads), and an empty mound on the knoll. Two seeds arc in, one
//  from each side (the partner's from the left, yours from the right), the
//  mound puffs, a two-leaf sprout pops, the tree sprouts at its stage (a
//  place tree always starts as a seed; Our tree shows the stage of its
//  start date), shines with its first watering's lushness, a can pours,
//  and the words fade in over a scrim on the band's lower third. Total
//  3.6 s; a tap outside the words skips to the end.
//
//  Reduce Motion: the final pose crossfades in over 0.4 s with one success
//  haptic. VoiceOver: the words are there from the start; on appear the
//  ceremony is announced in one sentence and focus lands on the title.
//  At accessibility text sizes the words move under the band, the band is
//  220 pt, and if they still do not fit, the content scrolls.
//

import SwiftUI
import UIKit

/// The ceremony's clock (C8, seconds from its start), shared with the
/// planting haptic track in GardenHaptics.
nonisolated enum PlantingCeremonyTimeline {
    /// 0–0.5: two seeds arc in and land on the mound.
    static let seedsLand: TimeInterval = 0.5
    /// 0.5–0.9: the mound puffs and throws its crumbs.
    static let puffEnd: TimeInterval = 0.9
    /// 0.9–1.4: the two-leaf sprout pops.
    static let sproutEnd: TimeInterval = 1.4
    /// 1.4–2.0: the tree grows in with a 4% overshoot.
    static let treeGrown: TimeInterval = 2.0
    /// 2.2–2.8: the short can pour and eight glints.
    static let pourStart: TimeInterval = 2.2
    static let pourEnd: TimeInterval = 2.8
    /// The place chip slides down and the words fade in.
    static let wordsStart: TimeInterval = 2.8
    /// The button is up and the band rests.
    static let end: TimeInterval = 3.6
}

struct PlantingCeremonyOverlay: View {
    let ceremony: GardenCeremony
    let partnerName: String
    let myName: String?
    let onDone: () -> Void

    /// What the words show: growing (band only), the words, then the button.
    private enum Step: Int, Comparable {
        case growing, words, done
        static func < (lhs: Step, rhs: Step) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme
    /// The tab's ad banner sits over the bottom of this overlay; the button
    /// keeps clear of it, as in CrownCelebrationOverlay.
    @ObservedObject private var ads = AdsManager.shared
    @AccessibilityFocusState private var titleFocused: Bool

    @State private var step: Step = .growing
    @State private var startTime = Date().timeIntervalSinceReferenceDate
    @State private var hasAppeared = false
    /// The band stops on its final frame: skipped, or the clock ran out.
    @State private var bandSkipped = false
    @State private var bandFinished = false
    @State private var bandSize: CGSize = .zero
    @State private var backdrops: [GardenBackdropKey: CGImage] = [:]

    /// The place's sky and season at the ceremony's start.
    private let environment: GardenSceneEnvironment

    init(ceremony: GardenCeremony, partnerName: String, myName: String?,
         onDone: @escaping () -> Void) {
        self.ceremony = ceremony
        self.partnerName = partnerName
        self.myName = myName
        self.onDone = onDone
        self.environment = GardenSceneEnvironment.make(scene: ceremony.look.scene, place: ceremony.place,
                                                       treeKey: ceremony.key, now: Date())
    }

    var body: some View {
        ZStack {
            // 0.86, darker than the crown overlay's 0.75: the ceremony's words
            // sit right over the hero's own caption and date line, which
            // showed through at 0.75 and read as text over text.
            Color.black.opacity(0.86)
                .ignoresSafeArea()
                .onTapGesture { tapOutsideWords() }
                .opacity(hasAppeared ? 1 : 0)
                .accessibilityHidden(true)

            ViewThatFits(in: .vertical) {
                content(bandHeight: wordsUnderBand ? 220 : 300)

                // Short screens: a shorter band before scrolling.
                content(bandHeight: 220)

                ScrollView {
                    content(bandHeight: 220)
                        .background {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { tapOutsideWords() }
                        }
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { finish() }
        .onAppear(perform: begin)
        .onDisappear { GardenHaptics.shared.stop() }
        .task { await runClock() }
        .task(id: [Int(bandSize.width.rounded()), Int(bandSize.height.rounded()), backdropScale]) {
            await loadBackdrops()
        }
    }

    // MARK: - Layout

    private var wordsUnderBand: Bool { dynamicTypeSize.isAccessibilitySize }

    private func content(bandHeight: CGFloat) -> some View {
        VStack(spacing: 20) {
            Spacer(minLength: 24)

            band(height: bandHeight)

            VStack(spacing: 10) {
                if wordsUnderBand {
                    headline
                }
                details
            }
            // A soft dark bed under the words: nothing behind the dim (the
            // hero's own caption sits right there) reads through them.
            .background {
                Color.black.opacity(0.7)
                    .padding(.horizontal, -24)
                    .padding(.vertical, -12)
                    .blur(radius: 14)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 28)
            .opacity(step >= .words ? 1 : 0)
            .offset(y: step >= .words || reduceMotion ? 0 : 12)

            Spacer(minLength: 16)

            BrandCTA(title: LocalizedStringResource("See it in your garden",
                                                    comment: "Planting ceremony: the button that closes it and shows the new tree in the garden"),
                     tier: .hero) {
                finish()
            }
            .frame(maxWidth: 360)
            .padding(.horizontal, 24)
            .padding(.bottom, 36 + ads.bannerInset)
            .opacity(step == .done ? 1 : 0)
            .allowsHitTesting(step == .done)
        }
        .frame(maxWidth: .infinity)
    }

    private func band(height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            bandScene
                .accessibilityHidden(true)

            if !wordsUnderBand {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    headline
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)
                        .frame(maxWidth: .infinity)
                        .background(alignment: .bottom) {
                            LinearGradient(colors: [.black.opacity(0), .black.opacity(0.4), .black.opacity(0.4)],
                                           startPoint: .top, endPoint: .bottom)
                                .frame(height: height / 3 + 24)
                                .accessibilityHidden(true)
                        }
                        // Taps on the words do not skip.
                        .contentShape(Rectangle())
                        .onTapGesture {}
                        .opacity(step >= .words ? 1 : 0)
                }
            }

            placeChip
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: Brand.heroCornerRadius, style: Brand.cornerStyle))
        .contentShape(Rectangle())
        .onTapGesture { tapOutsideWords() }
        .padding(.horizontal, 16)
        .opacity(reduceMotion && !hasAppeared ? 0 : 1)
        .scaleEffect(hasAppeared || reduceMotion ? 1 : 0.96)
    }

    private var headline: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(JourneyFont.display)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.75)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($titleFocused)
            Text(subtitle)
                .font(JourneyFont.label)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
        }
        .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
    }

    private var details: some View {
        VStack(spacing: 6) {
            if let growthLine {
                Text(growthLine)
                    .font(JourneyFont.body)
                    .foregroundStyle(.white)
            }
            Text(plantedLine)
                .font(JourneyFont.meta)
                .foregroundStyle(.white.opacity(0.85))
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The place's name, top-leading in the band; it slides down with the
    /// words, and with Reduce Motion fades in where it stands (C8, C10).
    @ViewBuilder
    private var placeChip: some View {
        if let name = ceremony.place?.name, !name.isEmpty {
            HStack(spacing: 5) {
                Image(systemName: "mappin")
                    .font(.system(size: 11, weight: .semibold))
                Text(verbatim: name)
                    .font(JourneyFont.caption)
                    .lineLimit(1)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .frame(maxWidth: max(80, bandSize.width * 0.44), alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .offset(y: step >= .words || reduceMotion ? 0 : -56)
            .opacity(step >= .words ? 1 : 0)
            .accessibilityHidden(true)
        }
    }

    // MARK: - The band

    private var bandIsStill: Bool { reduceMotion || bandSkipped || bandFinished }

    private var bandScene: some View {
        GeometryReader { proxy in
            let size = proxy.size
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: bandIsStill)) { timeline in
                let now = timeline.date.timeIntervalSinceReferenceDate
                let t = bandIsStill ? PlantingCeremonyTimeline.end
                                    : min(PlantingCeremonyTimeline.end, max(0, now - startTime))
                scene(size: size, t: t, now: now)
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { bandSize = $0 }
    }

    private func scene(size: CGSize, t: TimeInterval, now: TimeInterval) -> some View {
        let sky = environment.sky
        let info = environment.scene.info
        let painter = environment.scene.painter
        let treeFrame = info.layout.treeFrame(in: size)
        let anchors = RelationshipTreeCanvas.anchors(in: treeFrame.size, stage: stage,
                                                     species: ceremony.look.species)
            .offset(by: treeFrame.origin)
        let pose: TreeMotionPose = reduceMotion ? .still : (bandIsStill ? .frozen : .live)
        let ambient = GardenAmbientState(time: now, pose: pose, sky: sky, season: environment.season,
                                         seed: environment.seed)
        let seed = environment.seed
        let hasLandscape = backdrop(.near, .day, size) != nil || backdrop(.near, .night, size) != nil
        let growth = WateringEffectPainter.easeOutBack(
            WateringEffectPainter.progress(t, PlantingCeremonyTimeline.sproutEnd, PlantingCeremonyTimeline.treeGrown),
            overshoot: 1.04)

        return ZStack(alignment: .topLeading) {
            LinearGradient(colors: [sky.top.color, sky.horizon.color],
                           startPoint: .top, endPoint: UnitPoint(x: 0.5, y: info.layout.horizon))

            Canvas(rendersAsynchronously: true) { context, canvasSize in
                painter.drawAmbient(.sky, in: context, size: canvasSize, state: ambient)
            }

            if hasLandscape {
                landscape(.far, size: size, darkness: sky.darkness)
                Canvas(rendersAsynchronously: true) { context, canvasSize in
                    painter.drawAmbient(.behind, in: context, size: canvasSize, state: ambient)
                }
                landscape(.near, size: size, darkness: sky.darkness)
            } else {
                // The placeholder band while the landscape loads.
                info.groundDay.mixed(with: info.groundNight, sky.darkness).color
                    .frame(height: size.height * (1 - info.layout.horizon))
                    .offset(y: size.height * info.layout.horizon)
            }

            Canvas(rendersAsynchronously: true) { context, _ in
                PlantingCeremonyPainter.drawGround(in: context, anchors: anchors, band: size, time: t, seed: seed)
            }

            if t >= PlantingCeremonyTimeline.sproutEnd {
                RelationshipTreeCanvas(
                    stage: stage,
                    season: environment.season.treeSeason,
                    daysTogether: daysGrowing,
                    memoryCount: 0,
                    crownActive: false,
                    style: .scene(species: ceremony.look.species, sky: sky, season: environment.season,
                                  topologySeed: ceremony.isOurTree ? nil : JourneyTreeOrnament.stableSeed(ceremony.key)),
                    vitality: TreeVitality(thirst: 0,
                                           wetness: WateringEffectPainter.progress(t, PlantingCeremonyTimeline.pourStart + 0.3,
                                                                                   PlantingCeremonyTimeline.pourEnd + 0.2),
                                           dew: 0, soilDryness: 0, lushness: 1),
                    clock: .external(time: now, pose: pose)
                )
                .frame(width: treeFrame.width, height: treeFrame.height)
                .scaleEffect(max(0.001, growth), anchor: UnitPoint(x: 0.5, y: 0.93))
                .offset(x: treeFrame.minX, y: treeFrame.minY)
            }

            if hasLandscape {
                landscape(.front, size: size, darkness: sky.darkness)
            }

            Canvas(rendersAsynchronously: true) { context, canvasSize in
                painter.drawAmbient(.front, in: context, size: canvasSize, state: ambient)
                PlantingCeremonyPainter.drawFirstWater(in: context, anchors: anchors, band: canvasSize, sky: sky,
                                                       time: t, seed: seed)
            }

            sky.warmTint.color.opacity(sky.warmTintAlpha)
                .blendMode(.softLight)
            if colorScheme == .dark {
                // A daytime band is veiled so it is not a bright slab in a dark UI (C1).
                Color.black.opacity(0.18 * (1 - sky.darkness))
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    /// One static layer, its night image over its day image at the sky's darkness.
    private func landscape(_ layer: GardenBackdropLayer, size: CGSize, darkness: Double) -> some View {
        let alignment: Alignment = switch layer {
        case .far:   .top
        case .near:  .topLeading
        case .front: .bottom
        }
        return ZStack(alignment: alignment) {
            if darkness < 1, let day = backdrop(layer, .day, size) {
                Image(decorative: day, scale: CGFloat(backdropScale))
            }
            if darkness > 0, let night = backdrop(layer, .night, size) {
                Image(decorative: night, scale: CGFloat(backdropScale))
                    .opacity(darkness)
            }
        }
        .frame(width: size.width, height: size.height, alignment: alignment)
    }

    // MARK: - Backdrops (P5's cache, shared by scene)

    /// min(displayScale, 2): landscapes are soft (GardenBackdropKey).
    private var backdropScale: Int { max(1, min(2, Int(displayScale.rounded()))) }

    private func backdropKey(_ layer: GardenBackdropLayer, _ variant: GardenSkyVariant,
                             _ size: CGSize) -> GardenBackdropKey {
        GardenBackdropKey(scene: environment.scene, layer: layer,
                          style: GardenSceneStyle(variant: variant, season: environment.season),
                          width: Int(size.width.rounded()), height: Int(size.height.rounded()),
                          scale: backdropScale)
    }

    private func backdrop(_ layer: GardenBackdropLayer, _ variant: GardenSkyVariant, _ size: CGSize) -> CGImage? {
        backdrops[backdropKey(layer, variant, size)]
    }

    /// Brings in the variants this sky needs, far to front; each fades in.
    private func loadBackdrops() async {
        let size = bandSize
        guard size.width >= 1, size.height >= 1 else { return }
        let darkness = environment.sky.darkness
        var variants: [GardenSkyVariant] = []
        if darkness < 1 { variants.append(.day) }
        if darkness > 0 { variants.append(.night) }
        for layer in [GardenBackdropLayer.far, .near, .front] {
            for variant in variants {
                let key = backdropKey(layer, variant, size)
                guard backdrops[key] == nil,
                      let image = await GardenBackdropCache.shared.image(for: key),
                      !Task.isCancelled else { continue }
                withAnimation(.easeOut(duration: 0.2)) { backdrops[key] = image }
            }
        }
    }

    // MARK: - Clock and actions

    private func begin() {
        startTime = Date().timeIntervalSinceReferenceDate
        GardenHaptics.shared.playPlanting()
        let voiceOver = UIAccessibility.isVoiceOverRunning
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.4)) {
                hasAppeared = true
                step = .done
            }
        } else {
            withAnimation(.easeOut(duration: 0.3)) { hasAppeared = true }
            // VoiceOver needs the words from the start; the band still plays.
            if voiceOver { step = .done }
        }
        if voiceOver {
            UIAccessibility.post(notification: .screenChanged, argument: spokenAnnouncement)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                titleFocused = true
            }
        }
    }

    /// Words at 2.8 s, the button and a resting band at 3.6 s.
    private func runClock() async {
        guard !reduceMotion else { return }
        try? await Task.sleep(for: .seconds(PlantingCeremonyTimeline.wordsStart))
        guard !Task.isCancelled else { return }
        if step == .growing {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { step = .words }
        }
        try? await Task.sleep(for: .seconds(PlantingCeremonyTimeline.end - PlantingCeremonyTimeline.wordsStart))
        guard !Task.isCancelled else { return }
        bandFinished = true
        if step == .words {
            withAnimation(.easeOut(duration: 0.3)) { step = .done }
        }
    }

    /// Skips to the end; once there, closes.
    private func tapOutsideWords() {
        if step == .done && bandIsStill {
            finish()
            return
        }
        GardenHaptics.shared.stop()
        bandSkipped = true
        withAnimation(.easeOut(duration: 0.25)) { step = .done }
    }

    private func finish() {
        GardenHaptics.shared.stop()
        onDone()
    }

    // MARK: - Growth

    /// Whole days since the tree's growth start: Our tree from its start
    /// date (a stored calendar day), a place tree from its planting; 0 when
    /// it grows from today.
    private var daysGrowing: Int {
        guard let start = ceremony.growthStart else { return 0 }
        let calendar = Calendar.current
        let startDay = ceremony.isOurTree ? JourneyCalendarDay.localDay(ofStored: start, calendar: calendar)
                                          : calendar.startOfDay(for: start)
        let days = calendar.dateComponents([.day], from: startDay, to: calendar.startOfDay(for: Date())).day ?? 0
        return max(0, days)
    }

    private var stage: TreeGrowthStage { TreeGrowthStage.from(daysTogether: daysGrowing) }

    // MARK: - Copy (B5.8, C8)

    private var title: String {
        ceremony.isOurTree
            ? String(localized: "Your tree is planted",
                     comment: "Planting ceremony title when the couple's first tree (Our tree) has just been planted")
            : String(localized: "Planted together",
                     comment: "Planting ceremony title when a new tree for a place has just been planted by both partners")
    }

    private var placeName: String? {
        guard let name = ceremony.place?.name, !name.isEmpty else { return nil }
        return name
    }

    private var subtitle: String {
        guard let placeName else { return ceremony.title }
        return String(localized: "\(ceremony.title) · \(placeName)",
                      comment: "Planting ceremony subtitle: the tree's title, then its place. Example: Where we first met · Café Giảng")
    }

    private var plantedToday: Bool {
        ceremony.plantedAt.map { Calendar.current.isDateInToday($0) } ?? true
    }

    /// "It grows from 12 March 2023." (Our tree), "Planted 14 Nov 2026 ·
    /// for 12 March 2023" (a place tree for a remembered day), or "It starts
    /// growing today." (a place tree planted today); nil otherwise.
    private var growthLine: String? {
        if ceremony.isOurTree {
            guard let start = ceremony.growthStart else { return nil }
            let day = JourneyCalendarDay.localDay(ofStored: start).formatted(.dateTime.day().month(.wide).year())
            return String(localized: "It grows from \(day).",
                          comment: "Planting ceremony: the day Our tree grows from, the couple's start date. Example: It grows from 12 March 2023.")
        }
        if let moment = ceremony.momentDay {
            let planted = (ceremony.plantedAt ?? Date()).formatted(.dateTime.day().month(.abbreviated).year())
            let day = JourneyCalendarDay.localDay(ofStored: moment).formatted(.dateTime.day().month(.wide).year())
            return String(localized: "Planted \(planted) · for \(day)",
                          comment: "Planting ceremony: the day a tree for a place was planted, then the remembered day it stands for (it never changes growth). Example: Planted 14 Nov 2026 · for 12 March 2023")
        }
        guard plantedToday else { return nil }
        return String(localized: "It starts growing today.",
                      comment: "Planting ceremony: a tree for a place starts as a seed on the day it is planted")
    }

    /// "Planted by Alex and Sam · 14 Nov 2026", "· just now" while the
    /// server time is pending.
    private var plantedLine: String {
        let names = ceremony.plantedByNames.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let first = names.count >= 2 ? names[0] : myName
        let second = names.count >= 2 ? names[1] : partnerName
        guard let plantedAt = ceremony.plantedAt else {
            if let first {
                return String(localized: "Planted by \(first) and \(second) · just now",
                              comment: "Planting ceremony: who planted the tree, while the server time is still on its way. Example: Planted by Alex and Sam · just now")
            }
            return String(localized: "Planted by you and \(second) · just now",
                          comment: "Planting ceremony: who planted the tree, while the server time is on its way; the placeholder is the partner's name")
        }
        let day = plantedAt.formatted(.dateTime.day().month(.abbreviated).year())
        if let first {
            return String(localized: "Planted by \(first) and \(second) · \(day)",
                          comment: "Planting ceremony: who planted the tree and when. Example: Planted by Alex and Sam · 14 Nov 2026")
        }
        return String(localized: "Planted by you and \(second) · \(day)",
                      comment: "Planting ceremony: who planted the tree and when; the first placeholder is the partner's name. Example: Planted by you and Sam · 14 Nov 2026")
    }

    /// One announcement of the whole ceremony (C8), from complete
    /// localized pieces in one format.
    private var spokenAnnouncement: String {
        let tree: String
        if let placeName {
            tree = String(localized: "\(ceremony.title), \(placeName)",
                          comment: "VoiceOver, planting ceremony: the tree's title and its place. Example: Where we first met, Café Giảng")
        } else {
            tree = ceremony.title
        }
        let detail: String
        if ceremony.isOurTree, let start = ceremony.growthStart {
            let day = JourneyCalendarDay.localDay(ofStored: start).formatted(.dateTime.day().month(.wide).year())
            detail = String(localized: "\(stage.displayName), growing since \(day).",
                            comment: "VoiceOver, planting ceremony: the tree's growth stage and the day it grows from. Example: Fruiting, growing since 12 March 2023.")
        } else {
            detail = growthLine ?? plantedLine
        }
        return String(localized: "\(title). \(tree). \(detail)",
                      comment: "VoiceOver announcement when the planting ceremony opens: its title, the tree and its place, then how it grows. Example: Planted together. Where we first met, Café Giảng. It starts growing today.")
    }
}

// MARK: - Ceremony painter

/// The ceremony's own drawing: the mound, the two seeds, the crumbs, the
/// sprout and the first watering. Pure and nonisolated, like the effect
/// painter (safe in an asynchronously rendered Canvas); the tree itself is
/// RelationshipTreeCanvas.
nonisolated enum PlantingCeremonyPainter {
    private typealias Math = WateringEffectPainter
    private typealias Clock = PlantingCeremonyTimeline

    /// The mound (puffing at 0.5–0.9 s), the seeds arcing in (0–0.5 s), the
    /// crumbs it throws, and the sprout (0.9–1.4 s, fading as the tree grows).
    static func drawGround(in context: GraphicsContext, anchors a: TreeCanvasAnchors, band: CGSize,
                           time t: Double, seed: UInt64) {
        let base = a.trunkBase
        let width = max(28, a.unit * 0.34)
        let height = max(7, a.unit * 0.08)
        let puff = 1 + 0.12 * CGFloat(Math.pulse(t, Clock.seedsLand, Clock.puffEnd))

        // The mound: a soft dome of fresh soil.
        var mound = Path()
        mound.move(to: CGPoint(x: base.x - width / 2 * puff, y: base.y + 1))
        mound.addQuadCurve(to: CGPoint(x: base.x + width / 2 * puff, y: base.y + 1),
                           control: CGPoint(x: base.x, y: base.y - 2 * height * puff))
        mound.closeSubpath()
        context.fill(mound, with: .linearGradient(Gradient(colors: [GardenRGB(0xA07E5E).color, GardenRGB(0x6E5038).color]),
                                                  startPoint: CGPoint(x: base.x, y: base.y - height * puff),
                                                  endPoint: CGPoint(x: base.x, y: base.y)))
        var specks = Path()
        for i in 0..<5 {
            let x = base.x + CGFloat(Math.value(seed, i, 200, -0.32, 0.32)) * width
            let y = base.y - CGFloat(Math.value(seed, i, 201, 0.1, 0.5)) * height
            specks.addEllipse(in: CGRect(x: x - 0.9, y: y - 0.9, width: 1.8, height: 1.8))
        }
        context.fill(specks, with: .color(GardenRGB(0x5A3E2B).color.opacity(0.6)))

        let top = CGPoint(x: base.x, y: base.y - height * puff)

        // 0–0.5: two seeds, the partner's from the left edge, yours from the
        // right, peaking 0.25 H above the mound and falling onto it.
        if t < Clock.seedsLand + 0.1 {
            var seeds = Path()
            let p = min(1, t / Clock.seedsLand)
            let peakY = top.y - band.height * 0.25
            let k = (top.y - peakY) / 0.36
            let y = peakY + k * CGFloat((p - 0.4) * (p - 0.4))
            for side in 0..<2 {
                let fromX: CGFloat = side == 0 ? -6 : band.width + 6
                let toX = top.x + (side == 0 ? -4 : 4)
                let x = fromX + (toX - fromX) * CGFloat(p)
                let spin = CGFloat(p) * (side == 0 ? 5 : -5)
                let transform = CGAffineTransform(translationX: x, y: y).rotated(by: spin)
                seeds.addPath(Path(ellipseIn: CGRect(x: -2.5, y: -3.5, width: 5, height: 7)), transform: transform)
            }
            let fade = 1 - Math.progress(t, Clock.seedsLand, Clock.seedsLand + 0.1)
            context.fill(seeds, with: .color(GardenRGB(0x8C5A2B).color.opacity(fade)))
        }

        // 0.5–0.9: eight soil crumbs.
        let crumbAge = t - Clock.seedsLand
        if crumbAge >= 0, crumbAge < 0.5 {
            var crumbs = Path()
            for i in 0..<8 {
                let v = CGVector(dx: CGFloat(Math.value(seed, i, 210, 40, 110)) * (i % 2 == 0 ? -1 : 1),
                                 dy: -CGFloat(Math.value(seed, i, 211, 120, 200)))
                let point = Math.ballistic(top, v, gravity: 900, age: crumbAge)
                guard point.y <= base.y else { continue }
                let r = CGFloat(Math.value(seed, i, 212, 0.9, 1.6))
                crumbs.addEllipse(in: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2))
            }
            context.fill(crumbs, with: .color(GardenRGB(0x7A5A3E).color))
        }

        // 0.9–1.4: the two-leaf sprout pops (0 → 1.1 → 1); it fades as the tree grows.
        let sproutScale = CGFloat(Math.spring(t - Clock.puffEnd, response: 0.35, damping: 0.6))
        let sproutAlpha = 1 - Math.progress(t, Clock.sproutEnd, Clock.sproutEnd + 0.4)
        if sproutScale > 0.01, sproutAlpha > 0 {
            var c = context
            c.opacity = sproutAlpha
            c.translateBy(x: top.x, y: top.y + 1)
            c.scaleBy(x: sproutScale, y: sproutScale)
            var stem = Path()
            stem.move(to: .zero)
            stem.addQuadCurve(to: CGPoint(x: 0, y: -13), control: CGPoint(x: 2, y: -6))
            c.stroke(stem, with: .color(GardenRGB(0x4E9A45).color), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            var leaves = Path()
            for side in [-1.0, 1.0] {
                let transform = CGAffineTransform(translationX: CGFloat(side) * 4.5, y: -14)
                    .rotated(by: CGFloat(side) * 0.5)
                leaves.addPath(Path(ellipseIn: CGRect(x: -4.5, y: -2.4, width: 9, height: 4.8)), transform: transform)
            }
            c.fill(leaves, with: .color(GardenRGB(0x6DBE5A).color))
        }
    }

    /// 2.0–2.4: the first watering's sparkle on the new canopy; 2.2–2.8: the
    /// short can pour and eight glints.
    static func drawFirstWater(in context: GraphicsContext, anchors a: TreeCanvasAnchors, band: CGSize,
                               sky: GardenSkyState, time t: Double, seed: UInt64) {
        let sparkle = Math.pulse(t, Clock.treeGrown - 0.05, Clock.treeGrown + 0.45)
        if sparkle > 0 {
            let r = a.canopyRadius * 1.1
            let center = a.canopyCenter
            context.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                         with: .radialGradient(Gradient(colors: [GardenRGB(0xE8FFD0).color.opacity(0.45 * sparkle),
                                                                 GardenRGB(0xE8FFD0).color.opacity(0)]),
                                               center: center, startRadius: 0, endRadius: r))
            Math.drawCanopyGlints(in: context, anchors: a, seed: seed, count: 5, time: t,
                                  start: Clock.treeGrown, stagger: 0.06, life: 0.3, salt: 220)
        }
        Math.drawShortPour(in: context, anchors: a, band: band, sky: sky,
                           elapsed: t - Clock.pourStart, seed: seed)
        Math.drawCanopyGlints(in: context, anchors: a, seed: seed, count: 8, time: t,
                              start: Clock.pourStart + 0.25, stagger: 0.05, life: 0.3, salt: 230)
    }
}

#Preview("Planting ceremony") {
    ZStack {
        Brand.bgGradient.ignoresSafeArea()
        PlantingCeremonyOverlay(
            ceremony: GardenCeremony(
                slot: .p1, key: "preview-tree", title: "Where we first met",
                place: GardenPlace(name: "Café Giảng", locality: "Hoàn Kiếm, Hà Nội", latitude: 21.0341,
                                   longitude: 105.8549, precision: .exact, timeZoneId: "Asia/Ho_Chi_Minh"),
                look: GardenLook(scene: .cityLights, species: .cherry),
                growthStart: Date(), plantedAt: Date(), plantedByNames: ["Alex", "Sam"], isOurTree: false),
            partnerName: "Sam", myName: "Alex", onDone: {})
    }
}
