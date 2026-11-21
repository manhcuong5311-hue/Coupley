//
//  GardenScenePage.swift
//  Coupley
//
//  One pager page of the garden hero (spec C2): the layer stack (sky
//  gradient, sky life, far/near/front backdrop images from
//  GardenBackdropCache, scene life, the tree with an external clock, the
//  P8 overlays, the watering effect, tint and veil), driven by ONE
//  TimelineView per page and gated by GardenMotionGate.
//
//  Back to front (C2):
//    0 sky gradient · 1 sky life (canvas) · 2 far landscape (cached, day +
//    night, parallax 0.35×) · 3 scene life behind (canvas) · 4 near
//    landscape (cached) · 5 the tree (external clock) or the planting mound
//    · 6 resting cans, rainbow, after-glow · 7 front landscape (cached) ·
//    8 front life (canvas) · 9 watering effect and the scene's accent ·
//    10 warm tint and the dark-appearance veil.
//
//  The static layers are images keyed by scene, never by tree. While a
//  swipe is in flight the page only asks the memory tier
//  (`cachedImage(for:)`); a page whose images are not there yet shows the
//  placeholder band (its sky plus a flat ground in the scene's colours)
//  and fades the images in once they arrive. The cache's memory tier is
//  the only long-lived holder of those images: a page lets go of its own
//  when it leaves the view (and, unless selected, on a memory warning), and
//  draws what is in memory again on its first frame back.
//
//  Nothing here is read by VoiceOver: the hero folds the page into one
//  adjustable element. No text is ever drawn in a canvas.
//

import Foundation
import SwiftUI
import UIKit
import Combine
import CoreGraphics

// MARK: - Inputs

/// The tree a scene page draws, and what tapping its letters does.
struct GardenPageTree {
    let stage: TreeGrowthStage
    /// Our tree: the days together (its silhouette is seeded from them).
    /// A place tree: days since it was planted.
    let daysTogether: Int
    /// Memory stars around the tree (Our tree only).
    let memoryCount: Int
    let crownActive: Bool
    /// Letters on the tree (Our tree only).
    let ornaments: [JourneyTreeOrnament]
    let onSelectOrnament: ((String) -> Void)?

    /// A place tree grows from the day it was planted (spec 0.0 #3) and
    /// never shows stars, letters or the crown ring (C5).
    static func placeTree(growingSince start: Date?, now: Date) -> GardenPageTree {
        let days = start.map { GardenGrowth.days(since: $0, now: now) } ?? 0
        return GardenPageTree(stage: .from(daysTogether: days), daysTogether: days, memoryCount: 0,
                              crownActive: false, ornaments: [], onSelectOrnament: nil)
    }
}

/// What stands on the knoll of the planting hero (B3.2–B3.4), which has
/// no tree yet.
enum GardenMound: Equatable {
    /// No start date, nothing sent: bare soil.
    case bare
    /// My seed waits for the partner: a small wooden stake with a paper tag.
    case stake
    /// The partner's seed waits for me: the seed packet, breathing softly.
    case packet
}

/// What a page draws on its knoll.
enum GardenPageSubject {
    case tree(GardenPageTree)
    case mound(GardenMound)
}

/// Day counts for trees: a stored calendar day (the start date) names that
/// day; any other instant (a planting time) counts from its local day.
nonisolated enum GardenGrowth {
    static func days(since stored: Date, now: Date, calendar: Calendar = .current) -> Int {
        let start = JourneyCalendarDay.localDay(ofStored: stored, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        return max(0, calendar.dateComponents([.day], from: start, to: today).day ?? 0)
    }
}

extension GardenPageModel {
    /// A page in the Meadow at the phone's time, drawn before the garden
    /// has answered: Our tree from Journey's start date (an existing
    /// couple's first paint), or the planting hero's mound. Its title is
    /// display text (VoiceOver reads it), like every page's displayTitle.
    static func meadow(key: String, now: Date) -> GardenPageModel {
        GardenPageModel(slot: .our, key: key, title: GardenPreset.ourTree.localizedDefaultTitle, preset: .ourTree,
                        look: .ourTreeDefault, place: nil,
                        environment: .make(scene: .meadow, place: nil, treeKey: key, now: now),
                        visual: .healthy, growthStart: nil, restingCans: .none, showsRainbow: false,
                        noteTag: nil, placeChip: nil, placeChipIsAction: false, hasPendingWrites: false)
    }
}

// MARK: - Page

struct GardenScenePage: View {

    let page: GardenPageModel
    /// Whether this page may run its clock and play an effect.
    let gate: GardenMotionGate
    /// What this page plays now (the selected page only).
    let playback: GardenEffectPlayback?
    /// The tree (or the planting mound) on the knoll. Nil derives a place
    /// tree from the page alone (its planting day).
    let subject: GardenPageSubject?
    /// A swipe is in flight: only the memory tier is asked for images.
    let isSwiping: Bool
    /// False for the first frame of the one-time reveal (A9): the scene
    /// fades in behind the tree and the sun or moon rises into place.
    let revealed: Bool
    /// When this page was swiped to shortly after a watering played on
    /// another page: its after-glow starts then (C9).
    let afterGlowStart: TimeInterval?
    /// The watering note's tag on the tree was tapped.
    let onSelectNoteTag: (() -> Void)?

    init(page: GardenPageModel, gate: GardenMotionGate, playback: GardenEffectPlayback? = nil,
         subject: GardenPageSubject? = nil, isSwiping: Bool = false, revealed: Bool = true,
         afterGlowStart: TimeInterval? = nil, onSelectNoteTag: (() -> Void)? = nil) {
        self.page = page
        self.gate = gate
        self.playback = playback
        self.subject = subject
        self.isSwiping = isSwiping
        self.revealed = revealed
        self.afterGlowStart = afterGlowStart
        self.onSelectNoteTag = onSelectNoteTag
    }

    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme

    /// The static layers this page holds while it is in view, by key. The
    /// cache's memory tier keeps them across views (C2): this is emptied
    /// when the page leaves the view, so it never holds images beyond the
    /// cache's budget or past a memory warning.
    @State private var images: [GardenBackdropKey: CGImage] = [:]
    /// The playback (by watering id) whose effect has run to its end.
    @State private var finishedPlaybackId: String?
    /// The thirst the tree showed before the current watering: the revival
    /// eases from it to fresh.
    @State private var thirstBeforeWatering: Double = 0

    private var scene: GardenSceneID { page.look.scene }
    private var environment: GardenSceneEnvironment { page.environment }
    private var cacheScale: Int { min(2, max(1, Int(displayScale.rounded()))) }

    /// The playback this page still draws.
    private var activePlayback: GardenEffectPlayback? {
        guard let playback, playback.id != finishedPlaybackId else { return nil }
        return playback
    }

    private var resolvedSubject: GardenPageSubject {
        subject ?? .tree(.placeTree(growingSince: page.growthStart, now: Date()))
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let keys = Self.backdropKeys(scene: scene, environment: environment, band: size, scale: cacheScale)
            layers(size: size, shown: shownImages(keys))
                .task(id: LoadRequest(keys: keys, isSwiping: isSwiping)) {
                    await load(keys, swiping: isSwiping)
                }
        }
        .clipped()
        .accessibilityHidden(true)
        .task(id: playback?.id) { await waitForPlaybackEnd() }
        .onChange(of: page.visual.thirst, initial: true) { _, thirst in
            // Remembered only while nothing plays, so the revival starts from
            // the droop the user saw before tapping.
            if activePlayback == nil { thirstBeforeWatering = thirst }
        }
        // Out of the pager's viewport or off the tab: let go, so the cache's
        // budget and its memory-warning purge bound what is really held.
        .onDisappear { images = [:] }
        // The cache empties itself on a memory warning; a page not selected
        // lets go too, so that memory is actually freed.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            if !gate.isSelectedPage { images = [:] }
        }
    }

    /// What the page draws: the images it holds, else what the memory tier
    /// has now, so a page coming back into view draws its layers on its
    /// first frame, before `load` holds them again.
    private func shownImages(_ keys: [GardenBackdropKey]) -> [GardenBackdropKey: CGImage] {
        let cache = GardenBackdropCache.shared
        var shown: [GardenBackdropKey: CGImage] = [:]
        for key in keys {
            if let image = images[key] ?? cache.cachedImage(for: key) { shown[key] = image }
        }
        return shown
    }

    // MARK: - Layers

    private func layers(size: CGSize, shown: [GardenBackdropKey: CGImage]) -> some View {
        let effectRunning = activePlayback != nil && gate.allowsEffect
        let paused = !gate.isLive && !effectRunning
        return TimelineView(.animation(minimumInterval: effectRunning ? 1.0 / 60.0 : 1.0 / 30.0, paused: paused)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let ambient = GardenAmbientState(time: time, pose: pose, sky: environment.sky,
                                             season: environment.season, seed: environment.seed)
            let treeFrame = scene.info.layout.treeFrame(in: size)
            let anchors = treeAnchors(treeFrame: treeFrame)

            ZStack(alignment: .topLeading) {
                skyGradient(size: size)
                placeholderGround(size: size, shown: shown)

                skyLife(ambient: ambient)
                    .offset(y: revealed || gate.reduceMotion ? 0 : size.height * 0.12)

                staticLayer(.far, size: size, shown: shown)
                // The behind pass draws on the far plane (clock hands on the
                // tower, lanterns and glints over the river), so it trails
                // the page exactly as the far image does.
                ambientCanvas(.behind, ambient: ambient)
                    .visualEffect { [parallax = !gate.reduceMotion, width = size.width] content, geometry in
                        let pageMinX = geometry.frame(in: .scrollView(axis: .horizontal)).minX
                        let margin = width * (GardenSceneLayout.farWidthFactor - 1) / 2
                        return content.offset(x: parallax ? Self.parallaxOffset(pageMinX: pageMinX, margin: margin) : 0)
                    }
                staticLayer(.near, size: size, shown: shown)

                // The 24 h rainbow arcs behind the tree (C9). The together
                // effect fades its own in; the lasting one takes over once it
                // ends. A moonbow at night, as the effect draws it.
                if let anchors, page.showsRainbow, !(activePlayback?.effect == .together && gate.allowsEffect) {
                    GardenRainbowView(anchors: anchors, size: size, opacity: 0.25, darkness: environment.sky.darkness)
                        .allowsHitTesting(false)
                }

                knoll(treeFrame: treeFrame, time: time)

                overlays(anchors: anchors, size: size)

                staticLayer(.front, size: size, shown: shown)
                ambientCanvas(.front, ambient: ambient)

                if effectRunning, let playback = activePlayback {
                    effectCanvas(playback: playback, ambient: ambient, anchors: anchors, time: time)
                }

                tintAndVeil
            }
            .frame(width: size.width, height: size.height)
        }
    }

    private var pose: TreeMotionPose {
        if gate.reduceMotion { return .still }
        return gate.isLive ? .live : .frozen
    }

    // MARK: Sky (layers 0–1)

    private func skyGradient(size: CGSize) -> some View {
        LinearGradient(colors: [environment.sky.top.color, environment.sky.horizon.color],
                       startPoint: .top,
                       endPoint: UnitPoint(x: 0.5, y: scene.info.layout.horizon))
            .frame(width: size.width, height: size.height)
    }

    private func skyLife(ambient: GardenAmbientState) -> some View {
        ambientCanvas(.sky, ambient: ambient)
            .animation(gate.reduceMotion ? nil : .easeOut(duration: 0.8), value: revealed)
    }

    /// The flat ground from the horizon down while the near layer loads.
    private func placeholderGround(size: CGSize, shown: [GardenBackdropKey: CGImage]) -> some View {
        let info = scene.info
        let ground = info.groundDay.mixed(with: info.groundNight, environment.sky.darkness).color
        let top = size.height * info.layout.horizon
        return Rectangle()
            .fill(ground)
            .frame(width: size.width, height: max(0, size.height - top))
            .offset(y: top)
            .opacity(Self.hasImage(.near, in: shown) && revealed ? 0 : 1)
    }

    private func ambientCanvas(_ pass: GardenAmbientPass, ambient: GardenAmbientState) -> some View {
        let painter = scene.painter
        return Canvas(rendersAsynchronously: true) { context, canvasSize in
            painter.drawAmbient(pass, in: context, size: canvasSize, state: ambient)
        }
    }

    // MARK: Static layers (2, 4, 7)

    @ViewBuilder
    private func staticLayer(_ layer: GardenBackdropLayer, size: CGSize, shown: [GardenBackdropKey: CGImage]) -> some View {
        let darkness = environment.sky.darkness
        ZStack(alignment: .topLeading) {
            if darkness < 1 { layerImage(layer, variant: .day, size: size, shown: shown) }
            if darkness > 0 {
                layerImage(layer, variant: .night, size: size, shown: shown)
                    .opacity(darkness)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        // The one-time reveal fades the scene in behind the tree.
        .opacity(revealed || layer == .front ? 1 : 0)
        .animation(.easeOut(duration: 0.8), value: revealed)
        .animation(.easeOut(duration: 0.2), value: Self.hasImage(layer, in: shown))
    }

    @ViewBuilder
    private func layerImage(_ layer: GardenBackdropLayer, variant: GardenSkyVariant, size: CGSize,
                            shown: [GardenBackdropKey: CGImage]) -> some View {
        let key = Self.key(scene: scene, layer: layer, style: GardenSceneStyle(variant: variant, season: environment.season),
                           band: size, scale: cacheScale)
        if let image = shown[key] {
            let scale = CGFloat(cacheScale)
            let width = CGFloat(image.width) / scale
            let height = CGFloat(image.height) / scale
            switch layer {
            case .far:
                // Rendered wider than the band, centred, so the parallax
                // never shows its edge.
                let margin = (width - size.width) / 2
                Image(decorative: image, scale: scale)
                    .resizable()
                    .frame(width: width, height: height)
                    .offset(x: -margin)
                    .visualEffect { [parallax = !gate.reduceMotion] content, geometry in
                        // The layout frame starts at the page's leading edge
                        // (the offset above is not layout).
                        let pageMinX = geometry.frame(in: .scrollView(axis: .horizontal)).minX
                        return content.offset(x: parallax ? Self.parallaxOffset(pageMinX: pageMinX, margin: margin) : 0)
                    }
            case .near:
                Image(decorative: image, scale: scale)
                    .resizable()
                    .frame(width: width, height: height)
            case .front:
                Image(decorative: image, scale: scale)
                    .resizable()
                    .frame(width: width, height: height)
                    .offset(y: size.height - height)
            }
        }
    }

    /// The far landscape trails the page by 0.35× while paging, never
    /// further than its own spare width.
    nonisolated private static func parallaxOffset(pageMinX: CGFloat, margin: CGFloat) -> CGFloat {
        min(margin, max(-margin, -pageMinX * GardenSceneLayout.farParallax))
    }

    private static func hasImage(_ layer: GardenBackdropLayer, in shown: [GardenBackdropKey: CGImage]) -> Bool {
        shown.keys.contains { $0.layer == layer }
    }

    // MARK: The knoll (layer 5)

    @ViewBuilder
    private func knoll(treeFrame: CGRect, time: TimeInterval) -> some View {
        switch resolvedSubject {
        case .tree(let tree):
            treeCanvas(tree, frame: treeFrame, time: time)
        case .mound(let mound):
            moundCanvas(mound, treeFrame: treeFrame, time: time)
        }
    }

    private func treeCanvas(_ tree: GardenPageTree, frame: CGRect, time: TimeInterval) -> some View {
        RelationshipTreeCanvas(
            stage: tree.stage,
            season: environment.season.treeSeason,
            daysTogether: tree.daysTogether,
            memoryCount: tree.memoryCount,
            crownActive: tree.crownActive,
            ornaments: tree.ornaments,
            onSelectOrnament: tree.onSelectOrnament,
            // Our tree keeps today's silhouette (seeded from the days
            // together); a place tree's shape is its own.
            style: .scene(species: page.look.species, sky: environment.sky, season: environment.season,
                          topologySeed: page.slot.isOurTree ? nil : environment.seed),
            vitality: vitality,
            clock: .external(time: time, pose: pose),
            noteTag: page.noteTag,
            onSelectNoteTag: onSelectNoteTag
        )
        .frame(width: frame.width, height: frame.height)
        .offset(x: frame.minX, y: frame.minY)
        // Reduce Motion: the droop crossfades to fresh instead of springing.
        .animation(gate.reduceMotion ? .easeInOut(duration: GardenEffect.reducedMotionDuration) : nil,
                   value: page.visual)
    }

    /// The tree's look, with the revival when a watering plays here.
    private var vitality: TreeVitality {
        var vitality = TreeVitality(page.visual)
        if let playback = activePlayback, gate.allowsEffect {
            let firstDrop = playback.isFirstEver ? WateringEffectPainter.firstDropDuration : 0
            vitality.reviveFrom = thirstBeforeWatering
            vitality.reviveStart = playback.startTime + firstDrop + playback.effect.reviveOffset
        }
        return vitality
    }

    private func moundCanvas(_ mound: GardenMound, treeFrame: CGRect, time: TimeInterval) -> some View {
        let apex = CGPoint(x: treeFrame.midX, y: treeFrame.minY + treeFrame.height * 0.93)
        let unit = treeFrame.height
        let breathing = pose == .live ? 0.5 + 0.5 * sin(time * .pi) : 0.5
        let darkness = environment.sky.darkness
        return Canvas { context, _ in
            GardenMoundPainter.draw(mound, in: context, apex: apex, unit: unit,
                                    darkness: darkness, glow: breathing)
        }
    }

    // MARK: Overlays (layer 6)

    @ViewBuilder
    private func overlays(anchors: TreeCanvasAnchors?, size: CGSize) -> some View {
        if let anchors {
            ZStack(alignment: .topLeading) {
                if page.restingCans != .none {
                    GardenRestingCansView(cans: page.restingCans, anchors: anchors)
                }
                if let afterGlowStart, activePlayback == nil, !gate.reduceMotion {
                    GardenAfterGlowView(anchors: anchors, startTime: afterGlowStart)
                }
                if let playback = activePlayback, gate.reduceMotion, !playback.isReplay {
                    GardenReducedMotionDrop(anchors: anchors)
                        .transition(.opacity)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .allowsHitTesting(false)
        }
    }

    /// The tree's anchors in page coordinates (nil on the planting mound).
    private func treeAnchors(treeFrame: CGRect) -> TreeCanvasAnchors? {
        guard case .tree(let tree) = resolvedSubject else { return nil }
        return RelationshipTreeCanvas.anchors(in: treeFrame.size, stage: tree.stage, species: page.look.species)
            .offset(by: treeFrame.origin)
    }

    // MARK: Effect (layer 9)

    private func effectCanvas(playback: GardenEffectPlayback, ambient: GardenAmbientState,
                              anchors: TreeCanvasAnchors?, time: TimeInterval) -> some View {
        let painter = scene.painter
        let sky = environment.sky
        return Canvas(rendersAsynchronously: true) { context, canvasSize in
            let elapsed = time - playback.startTime
            if let anchors {
                WateringEffectPainter.draw(in: context, frame: GardenEffectFrame(playback: playback, elapsed: elapsed,
                                                                                 anchors: anchors, size: canvasSize,
                                                                                 sky: sky))
            }
            // Every effect ends with the scene's own touch in its last 0.6 s.
            let accentStart = playback.totalDuration - 0.6
            if elapsed >= accentStart, elapsed < playback.totalDuration {
                painter.drawWateringAccent(in: context, size: canvasSize, state: ambient,
                                           progress: (elapsed - accentStart) / 0.6)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: Tint and veil (layer 10)

    private var tintAndVeil: some View {
        let sky = environment.sky
        return ZStack {
            if sky.warmTintAlpha > 0 {
                Rectangle()
                    .fill(sky.warmTint.color.opacity(sky.warmTintAlpha))
                    .blendMode(.softLight)
            }
            // A noon sky is not a bright slab in a dark UI; night is untouched.
            if colorScheme == .dark, sky.darkness < 1 {
                Rectangle().fill(Color.black.opacity(0.18 * (1 - sky.darkness)))
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Loading the static layers

    private struct LoadRequest: Equatable {
        let keys: [GardenBackdropKey]
        let isSwiping: Bool
    }

    /// Memory first (never loads mid-swipe); then, at rest, the disk tier or
    /// a render, each fading in as it arrives. A cancelled load (a swipe
    /// began, the keys changed, the page left) stops at once: it neither
    /// starts another main-actor render nor writes what it no longer wants.
    private func load(_ keys: [GardenBackdropKey], swiping: Bool) async {
        let cache = GardenBackdropCache.shared
        var found: [GardenBackdropKey: CGImage] = [:]
        for key in keys {
            if let image = images[key] ?? cache.cachedImage(for: key) { found[key] = image }
        }
        if Set(found.keys) != Set(images.keys) { images = found }
        guard !swiping else { return }
        for key in keys where found[key] == nil {
            if Task.isCancelled { return }
            guard let image = await cache.image(for: key) else { continue }
            if Task.isCancelled { return }
            images[key] = image
        }
    }

    private func waitForPlaybackEnd() async {
        guard let playback else { return }
        let remaining = playback.startTime + playback.totalDuration - Date().timeIntervalSinceReferenceDate
        if remaining > 0 {
            try? await Task.sleep(for: .seconds(remaining))
        }
        guard !Task.isCancelled else { return }
        finishedPlaybackId = playback.id
        thirstBeforeWatering = page.visual.thirst
    }

    // MARK: - Keys

    /// The static layers a page needs right now: far, near and front, in the
    /// variants its sky needs (day while darkness < 1, night while > 0).
    static func backdropKeys(scene: GardenSceneID, environment: GardenSceneEnvironment,
                             band: CGSize, scale: Int) -> [GardenBackdropKey] {
        guard band.width > 0, band.height > 0 else { return [] }
        var variants: [GardenSkyVariant] = []
        if environment.sky.darkness < 1 { variants.append(.day) }
        if environment.sky.darkness > 0 { variants.append(.night) }
        return variants.flatMap { variant in
            [GardenBackdropLayer.far, .near, .front].map { layer in
                key(scene: scene, layer: layer, style: GardenSceneStyle(variant: variant, season: environment.season),
                    band: band, scale: scale)
            }
        }
    }

    private static func key(scene: GardenSceneID, layer: GardenBackdropLayer, style: GardenSceneStyle,
                            band: CGSize, scale: Int) -> GardenBackdropKey {
        GardenBackdropKey(scene: scene, layer: layer, style: style,
                          width: Int(band.width.rounded()), height: Int(band.height.rounded()), scale: scale)
    }
}

// MARK: - The planting mound

/// The planting hero's knoll (B3.2–B3.4): soil, a stake with a paper tag,
/// or the seed packet. Shapes only, no text.
private enum GardenMoundPainter {
    static func draw(_ mound: GardenMound, in context: GraphicsContext, apex: CGPoint, unit: CGFloat,
                     darkness: Double, glow: Double) {
        let soilDay = GardenRGB(0x8B6A4E), soilNight = GardenRGB(0x3A2C22)
        let soil = soilDay.mixed(with: soilNight, darkness).color
        let width = unit * 0.34, height = unit * 0.09
        var heap = Path()
        heap.move(to: CGPoint(x: apex.x - width / 2, y: apex.y + height * 0.2))
        heap.addQuadCurve(to: CGPoint(x: apex.x + width / 2, y: apex.y + height * 0.2),
                          control: CGPoint(x: apex.x, y: apex.y - height * 1.6))
        heap.closeSubpath()
        context.fill(heap, with: .color(soil))

        switch mound {
        case .bare:
            break
        case .stake:
            let wood = GardenRGB(0xB08A5E).mixed(with: GardenRGB(0x4A3A2C), darkness).color
            let stake = CGRect(x: apex.x + width * 0.12, y: apex.y - unit * 0.2, width: unit * 0.014, height: unit * 0.17)
            context.fill(Path(roundedRect: stake, cornerRadius: unit * 0.004), with: .color(wood))
            let paper = GardenRGB(0xF6EEDC).mixed(with: GardenRGB(0x9A937F), darkness * 0.7).color
            var tag = Path(roundedRect: CGRect(x: stake.maxX + unit * 0.004, y: stake.minY + unit * 0.02,
                                               width: unit * 0.07, height: unit * 0.045),
                           cornerRadius: unit * 0.006)
            tag.addEllipse(in: CGRect(x: stake.maxX + unit * 0.012, y: stake.minY + unit * 0.035,
                                      width: unit * 0.008, height: unit * 0.008))
            context.fill(tag, with: .color(paper))
        case .packet:
            let size = CGSize(width: unit * 0.1, height: unit * 0.128)
            let center = CGPoint(x: apex.x, y: apex.y - unit * 0.07)
            let glowRadius = unit * (0.12 + 0.03 * glow)
            context.fill(Path(ellipseIn: CGRect(x: center.x - glowRadius, y: center.y - glowRadius,
                                                width: glowRadius * 2, height: glowRadius * 2)),
                         with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.9, blue: 0.6).opacity(0.18 + 0.2 * glow),
                                                                 .clear]),
                                               center: center, startRadius: 0, endRadius: glowRadius))
            // Resting on the mound, tilted a little.
            var packet = context
            packet.translateBy(x: center.x, y: center.y)
            packet.rotate(by: .degrees(-8))
            let body = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
            let kraft = GardenRGB(0xD9B98C).mixed(with: GardenRGB(0x6B5A44), darkness * 0.6).color
            let flap = GardenRGB(0xC9A574).mixed(with: GardenRGB(0x5E4E3A), darkness * 0.6).color
            packet.fill(Path(roundedRect: body, cornerRadius: unit * 0.008), with: .color(kraft))
            var flapPath = Path()
            flapPath.move(to: CGPoint(x: body.minX, y: body.minY))
            flapPath.addLine(to: CGPoint(x: body.maxX, y: body.minY))
            flapPath.addLine(to: CGPoint(x: body.midX, y: body.minY + body.height * 0.3))
            flapPath.closeSubpath()
            packet.fill(flapPath, with: .color(flap))
            let label = CGRect(x: body.minX + body.width * 0.18, y: body.minY + body.height * 0.48,
                               width: body.width * 0.64, height: body.height * 0.3)
            packet.fill(Path(roundedRect: label, cornerRadius: unit * 0.004),
                        with: .color(Color(red: 0.98, green: 0.95, blue: 0.88)))
        }
    }
}
