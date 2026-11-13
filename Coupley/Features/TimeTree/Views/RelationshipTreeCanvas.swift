//
//  RelationshipTreeCanvas.swift
//  Coupley
//
//  The tree in Journey's hero. A procedurally drawn tree that grows with
//  the relationship: the trunk thickens, branches multiply, leaves fill in,
//  blossoms appear, golden fruits ripen, and a crown ring lights up for
//  long-lived couples. Future letters live on it too. Unopened ones hang
//  from the branches as small wax-sealed envelopes (the partner's on the
//  left, yours on the right) and glow once their moment has come; opened
//  ones bloom as gold blossoms in the canopy.
//
//  Implementation notes:
//   - One `Canvas`, sized by the caller. Every length comes from `unit`,
//     the shorter side of the frame, so the trunk, canopy, crown ring,
//     stars and letters fit any frame from 160×160 up (the hero's 176×196,
//     its 160pt-tall variant, and full width × 180 at accessibility sizes).
//     The trunk stays centred at width / 2.
//   - `TreeCanvasLayout` is the only source of geometry. The drawing and
//     the invisible tap targets both read it, so a target always sits on
//     the envelope or blossom it opens.
//   - `TimelineView(.animation)` drives the sway, flutter, glow and orbits
//     at up to 30 fps. It pauses (still one frame) under Reduce Motion, in
//     Low Power Mode, while the scene is not active, and while the tree is
//     scrolled away or its tab is hidden. Under Reduce Motion that frame
//     is the rest pose, identical every time it is drawn.
//   - Topology is deterministic. Leaves, blossoms and fruits are seeded
//     from the days together. Each memory star is seeded by its index, so
//     a new memory adds one star and moves none. Each letter's place comes
//     from its id's FNV-1a seed, never from its index in the list, so a
//     new letter leaves the others where they are. Only when two letters
//     want the same place does the later one in id order move on to the
//     next free place.
//   - VoiceOver skips the canvas and the tap targets. Journey labels the
//     tree, and every letter is reachable in the Letters section and the
//     Timeline.
//

import Combine
import Foundation
import SwiftUI

// MARK: - Public View

struct RelationshipTreeCanvas: View {

    let stage: TreeGrowthStage
    let season: TreeSeason
    let daysTogether: Int
    /// Memories drive the floating star count.
    let memoryCount: Int
    /// Whether to draw the persistent crown ring above the canopy.
    /// (Per-anniversary celebration crowns are a separate overlay.)
    let crownActive: Bool
    /// Letters on the tree, from `JourneyLetterFeed.treeOrnaments(...)`.
    let ornaments: [JourneyTreeOrnament]
    /// Called with a letter's id when its envelope or blossom is tapped.
    /// Nil leaves the tree purely decorative.
    let onSelectOrnament: ((String) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    /// False while the tree's tab is not on screen (onAppear / onDisappear).
    @State private var isShown = false
    /// False while the tree is scrolled out of view.
    @State private var isScrolledIntoView = true
    @State private var selectionCount = 0

    init(stage: TreeGrowthStage,
         season: TreeSeason,
         daysTogether: Int,
         memoryCount: Int,
         crownActive: Bool,
         ornaments: [JourneyTreeOrnament] = [],
         onSelectOrnament: ((String) -> Void)? = nil) {
        self.stage = stage
        self.season = season
        self.daysTogether = daysTogether
        self.memoryCount = memoryCount
        self.crownActive = crownActive
        self.ornaments = ornaments
        self.onSelectOrnament = onSelectOrnament
    }

    private var pose: TreeCanvasPose {
        if reduceMotion { return .still }
        let paused = isLowPower || !isShown || !isScrolledIntoView || scenePhase != .active
        return paused ? .frozen : .live
    }

    var body: some View {
        let painter = TreeCanvasPainter(
            stage: stage,
            season: season,
            daysTogether: daysTogether,
            memoryCount: memoryCount,
            crownActive: crownActive,
            ornaments: ornaments
        )
        let currentPose = pose
        // A paused TimelineView still renders one frame.
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: currentPose != .live)) { timeline in
            let motion = TreeCanvasMotion(pose: currentPose,
                                          time: timeline.date.timeIntervalSinceReferenceDate)
            Canvas(rendersAsynchronously: true) { context, size in
                painter.draw(in: context, size: size, motion: motion)
            }
        }
        .accessibilityHidden(true)
        .overlay { ornamentTargets }
        .onAppear {
            isShown = true
            isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .onDisappear { isShown = false }
        .onScrollVisibilityChange(threshold: 0.05) { visible in
            isScrolledIntoView = visible
        }
        .onReceive(
            NotificationCenter.default
                .publisher(for: .NSProcessInfoPowerStateDidChange)
                .receive(on: DispatchQueue.main)
        ) { _ in
            isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .sensoryFeedback(.impact(weight: .light), trigger: selectionCount)
    }

    // MARK: - Tap targets

    /// One invisible hit layer over the letters, at the spots where they
    /// rest when nothing sways (the same layout the drawing uses). A tap
    /// within 22pt of a letter opens the letter whose centre is NEAREST the
    /// finger. Letters sit 10-16pt apart, so per-letter squares overlapped,
    /// and the one in front could open (and mark opened) a neighbour.
    /// Hidden from VoiceOver, which reaches letters in the Letters section
    /// and the Timeline instead.
    @ViewBuilder
    private var ornamentTargets: some View {
        if let onSelectOrnament, !ornaments.isEmpty {
            GeometryReader { proxy in
                let placements = TreeCanvasLayout(size: proxy.size, stage: stage).place(ornaments)
                Color.clear
                    .contentShape(Path { path in
                        for placement in placements {
                            path.addEllipse(in: CGRect(x: placement.center.x - 22,
                                                       y: placement.center.y - 22,
                                                       width: 44, height: 44))
                        }
                    })
                    .onTapGesture { location in
                        guard let nearest = placements.min(by: {
                            hypot($0.center.x - location.x, $0.center.y - location.y)
                                < hypot($1.center.x - location.x, $1.center.y - location.y)
                        }) else { return }
                        selectionCount += 1
                        onSelectOrnament(nearest.id)
                    }
            }
            .accessibilityHidden(true)
        }
    }
}

extension RelationshipTreeCanvas {
    /// How many opened letters the tree can show as blossoms at `stage`
    /// without two sharing a place: 5 on a seed or sprout, 4 on a sapling,
    /// 8 on a young tree, 12 after. The same for every frame size.
    static func blossomCapacity(at stage: TreeGrowthStage) -> Int {
        TreeCanvasLayout(size: CGSize(width: 200, height: 200), stage: stage).blossomCapacity
    }
}

// MARK: - Motion

/// How the tree moves right now.
private enum TreeCanvasPose {
    /// Animating, at up to 30 fps.
    case live
    /// Paused while off screen, in the background, or in Low Power Mode:
    /// one frame, held where the motion was. Envelopes hang straight and a
    /// ready letter's glow is steady.
    case frozen
    /// Reduce Motion: one frame in the rest pose, the same every time.
    case still
}

private struct TreeCanvasMotion {
    let pose: TreeCanvasPose
    let time: TimeInterval

    var isLive: Bool { pose == .live }

    /// sin(time × rate + phase), and 0 in the still pose.
    func wave(_ rate: Double, _ phase: Double = 0) -> Double {
        pose == .still ? 0 : sin(time * rate + phase)
    }

    /// 0…1, and ½ in the still pose.
    func pulse(_ rate: Double, _ phase: Double = 0) -> Double {
        (wave(rate, phase) + 1) / 2
    }

    /// An angle that keeps turning (orbits, petals), and 0 in the still pose.
    func turn(_ rate: Double) -> Double {
        pose == .still ? 0 : time * rate
    }
}

// MARK: - Palette

/// Bark and starlight for the colour scheme. On a dark hero the original
/// deep brown bark measured about 1.2–1.5:1 and the trunk all but vanished,
/// so there it is lit a little; cream starlight vanished on a light hero,
/// so there the stars are amber. Everything else reads on both.
private struct TreeCanvasPalette {
    let trunkBase: Color
    let trunkTop: Color
    let limb: Color
    let twig: Color
    let starCore: Color
    let starGlow: Color

    init(_ scheme: ColorScheme) {
        if scheme == .dark {
            trunkBase = Color(red: 0.50, green: 0.36, blue: 0.26)
            trunkTop = Color(red: 0.68, green: 0.51, blue: 0.37)
            limb = Color(red: 0.60, green: 0.44, blue: 0.31)
            twig = Color(red: 0.56, green: 0.41, blue: 0.29)
            starCore = Color(red: 1.0, green: 0.97, blue: 0.85)
            starGlow = Color(red: 1.0, green: 0.92, blue: 0.78)
        } else {
            trunkBase = Color(red: 0.32, green: 0.22, blue: 0.16)
            trunkTop = Color(red: 0.48, green: 0.34, blue: 0.24)
            limb = Color(red: 0.40, green: 0.28, blue: 0.20)
            twig = Color(red: 0.36, green: 0.25, blue: 0.18)
            starCore = Color(red: 0.82, green: 0.52, blue: 0.16)
            starGlow = Color(red: 1.0, green: 0.74, blue: 0.38)
        }
    }
}

// MARK: - Layout

/// The tree's geometry for one frame size and stage. Everything is
/// measured in `unit` inside a unit × unit box that sits on the bottom edge,
/// centred horizontally.
private struct TreeCanvasLayout {

    struct Branch {
        let index: Int
        let isLeft: Bool
        let start: CGPoint
        let control1: CGPoint
        let control2: CGPoint
        let end: CGPoint
        let reach: CGFloat
        let width: CGFloat

        /// The point at `t` (0 at the trunk, 1 at the tip), with the tip
        /// moved by `tipOffset` while the limb sways.
        func point(at t: CGFloat, tipOffset: CGSize = .zero) -> CGPoint {
            let mt = 1 - t
            let a = mt * mt * mt
            let b = 3 * mt * mt * t
            let c = 3 * mt * t * t
            let d = t * t * t
            let tip = CGPoint(x: end.x + tipOffset.width, y: end.y + tipOffset.height)
            return CGPoint(
                x: a * start.x + b * control1.x + c * control2.x + d * tip.x,
                y: a * start.y + b * control1.y + c * control2.y + d * tip.y
            )
        }

        /// The limb from the trunk to `t`, as its own curve (de Casteljau),
        /// so it can be stroked thicker near the trunk than at the tip.
        func path(to t: CGFloat, tipOffset: CGSize = .zero) -> Path {
            func lerp(_ p: CGPoint, _ q: CGPoint) -> CGPoint {
                CGPoint(x: p.x + (q.x - p.x) * t, y: p.y + (q.y - p.y) * t)
            }
            let tip = CGPoint(x: end.x + tipOffset.width, y: end.y + tipOffset.height)
            let p01 = lerp(start, control1)
            let p12 = lerp(control1, control2)
            let p23 = lerp(control2, tip)
            let p012 = lerp(p01, p12)
            let p123 = lerp(p12, p23)
            var path = Path()
            path.move(to: start)
            path.addCurve(to: lerp(p012, p123), control1: p01, control2: p012)
            return path
        }
    }

    struct Crown {
        let center: CGPoint
        let radiusX: CGFloat
        let radiusY: CGFloat
    }

    /// Where one letter sits on the tree.
    struct Placement: Identifiable {
        enum Mount {
            /// On a thread from a limb, `along` its curve.
            case hanging(branch: Int, along: CGFloat)
            /// On the ground beside the trunk, turned by `tilt` degrees.
            case resting(tilt: Double)
            /// A blossom in the canopy.
            case bloom
        }

        let ornament: JourneyTreeOrnament
        let mount: Mount
        /// At rest: the envelope's middle or the blossom's centre.
        let center: CGPoint

        var id: String { ornament.id }
    }

    private struct EnvelopeSlot {
        /// Nil for a place on the ground.
        let branch: Int?
        let along: CGFloat
        let center: CGPoint
    }

    let size: CGSize
    let unit: CGFloat
    let midX: CGFloat
    /// The top of the unit box.
    let top: CGFloat
    let groundY: CGFloat
    let trunkHeight: CGFloat
    let trunkWidth: CGFloat
    let canopyCenter: CGPoint
    let canopyRadius: CGFloat
    let branches: [Branch]
    let envelopeSize: CGSize
    let threadLength: CGFloat
    /// A stage blossom at rest.
    let blossomRadius: CGFloat
    /// About 1.2× a stage blossom.
    let letterBlossomRadius: CGFloat

    init(size: CGSize, stage: TreeGrowthStage) {
        let unit = max(1, min(size.width, size.height))
        let midX = size.width / 2
        let top = size.height - unit
        let groundY = top + unit * 0.93
        let scale = stage.trunkScale
        let trunkHeight = unit * 0.43 * scale
        let trunkWidth = max(unit * 0.034, unit * 0.095 * scale)
        let canopyRadius = unit * (0.04 + 0.30 * stage.canopyFullness)
        let trunkTopY = groundY - trunkHeight

        // Limbs alternate left and right up the trunk. Middle limbs reach
        // furthest, upper ones climb more steeply, and every tip ends inside
        // the canopy.
        var branches: [Branch] = []
        let count = stage.branchCount
        for i in 0..<count {
            let progress: CGFloat = count == 1 ? 0.5 : CGFloat(i) / CGFloat(count - 1)
            let isLeft = i % 2 == 0
            let direction: CGFloat = isLeft ? -1 : 1
            let attachY = groundY - trunkHeight * (0.35 + 0.60 * progress)
            let fromMiddle = abs(progress - 0.5) * 2
            let reach = canopyRadius * (0.55 + 0.35 * (1 - fromMiddle) + 0.05 * CGFloat(i % 3))
            let rise = reach * (0.35 + 0.45 * progress)
            branches.append(Branch(
                index: i,
                isLeft: isLeft,
                start: CGPoint(x: midX, y: attachY),
                control1: CGPoint(x: midX + direction * reach * 0.3, y: attachY - rise * 0.2),
                control2: CGPoint(x: midX + direction * reach * 0.7, y: attachY - rise * 0.7),
                end: CGPoint(x: midX + direction * reach, y: attachY - rise),
                reach: reach,
                width: max(unit * 0.009, trunkWidth * 0.45 * scale)
            ))
        }

        self.size = size
        self.unit = unit
        self.midX = midX
        self.top = top
        self.groundY = groundY
        self.trunkHeight = trunkHeight
        self.trunkWidth = trunkWidth
        self.canopyCenter = CGPoint(x: midX, y: trunkTopY - canopyRadius * 0.25)
        self.canopyRadius = canopyRadius
        self.branches = branches
        self.envelopeSize = CGSize(width: unit * 0.055, height: unit * 0.055 * 0.7)
        self.threadLength = unit * 0.03
        self.blossomRadius = unit * 0.023
        self.letterBlossomRadius = unit * 0.023 * 1.2
    }

    var trunkBase: CGPoint { CGPoint(x: midX, y: groundY) }
    var trunkTop: CGPoint { CGPoint(x: midX, y: groundY - trunkHeight) }

    /// A height inside the unit box, as a fraction of `unit` from its top.
    func y(_ fraction: CGFloat) -> CGFloat { top + unit * fraction }

    /// The ambient crown: a flat arch whose ends tuck behind the top of the
    /// canopy, never so high that its tallest spike leaves the frame.
    var crown: Crown {
        let radiusX = min(unit * 0.30, max(canopyRadius * 0.95, unit * 0.14))
        let radiusY = radiusX * 0.32
        let canopyTop = canopyCenter.y - canopyRadius * 0.85
        // Arch top, tallest spike (0.042) and half the largest tip dot (0.009).
        let highest = top + unit * (0.012 + 0.042 + 0.009) + radiusY
        let centerY = max(canopyTop + unit * 0.01 + radiusY * 0.342, highest)
        return Crown(center: CGPoint(x: midX, y: centerY), radiusX: radiusX, radiusY: radiusY)
    }

    // MARK: Letters

    /// Every letter's place. Envelopes go to their side (letters to you on
    /// the left, yours on the right); opened letters bloom in the canopy.
    /// Each group is processed in id order: a letter starts at the slot its
    /// seed picks and moves to the next free one if that is taken.
    func place(_ ornaments: [JourneyTreeOrnament]) -> [Placement] {
        // Opened letters first, so the envelopes can keep clear of them. They
        // still go last in the result; the painter draws by kind anyway.
        let blossomPlacements = placeBlossoms(ornaments)
        var placements: [Placement] = []

        // A hanging place within this distance of a blossom would cover it,
        // and a tap there could open the wrong letter.
        let clearance = envelopeSize.width / 2 + letterBlossomRadius * 1.6

        for direction in [JourneyLetterDirection.toMe, .fromMe] {
            let envelopes = ornaments
                .filter { $0.kind != .blossom && $0.direction == direction }
                .sorted { $0.id < $1.id }
            guard !envelopes.isEmpty else { continue }
            let (slots, firstTier) = envelopeSlots(onLeft: direction == .toMe)
            var taken = Set<Int>()
            // Ground places are never near the canopy, and a side shows at
            // most 3 envelopes, so a free place always remains.
            for (index, slot) in slots.enumerated() where slot.branch != nil {
                let nearBlossom = blossomPlacements.contains {
                    hypot($0.center.x - slot.center.x, $0.center.y - slot.center.y) < clearance
                }
                if nearBlossom { taken.insert(index) }
            }
            for ornament in envelopes {
                let start = Int(ornament.seed % UInt64(firstTier))
                let slot = slots[Self.probe(from: start, count: slots.count, taken: &taken)]
                let mount: Placement.Mount
                if let branch = slot.branch {
                    mount = .hanging(branch: branch, along: slot.along)
                } else {
                    mount = .resting(tilt: Double(Int(ornament.seed % 13) - 6))
                }
                placements.append(Placement(ornament: ornament, mount: mount, center: slot.center))
            }
        }
        return placements + blossomPlacements
    }

    /// Feed order is most recently opened first: when there are more opened
    /// letters than places, the newest ones bloom and no two blossoms ever
    /// share a place.
    private func placeBlossoms(_ ornaments: [JourneyTreeOrnament]) -> [Placement] {
        let blossoms = ornaments.filter { $0.kind == .blossom }
        guard !blossoms.isEmpty else { return [] }
        let spots = blossomSpots()
        var taken = Set<Int>()
        var result: [Placement] = []
        for ornament in blossoms.prefix(spots.count).sorted(by: { $0.id < $1.id }) {
            let start = Int(ornament.seed % UInt64(spots.count))
            let spot = spots[Self.probe(from: start, count: spots.count, taken: &taken)]
            result.append(Placement(ornament: ornament, mount: .bloom, center: spot))
        }
        return result
    }

    /// See `RelationshipTreeCanvas.blossomCapacity(at:)`.
    var blossomCapacity: Int { blossomSpots().count }

    /// One side's envelope places, in probing order: first the tip of every
    /// limb on that side (a letter's seed picks one of these), then a second
    /// and a third place further along each limb, then three places on the
    /// ground at the foot of the trunk (all a seed has, and where a small
    /// tree's overflow rests). A hanging place is kept only if its envelope
    /// clears the trunk, stays inside the frame and overlaps no other.
    private func envelopeSlots(onLeft: Bool) -> (slots: [EnvelopeSlot], firstTier: Int) {
        let gap = unit * 0.008
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: unit * 0.01, dy: unit * 0.01)
        // The trunk bulges to about 0.72 of its base width at 40% height.
        let trunkClearance = trunkWidth * 0.72 + unit * 0.01
        let limbs = branches.filter { $0.isLeft == onLeft }
        let candidates: [CGFloat] = [0.96, 0.84, 0.72, 0.6, 0.5, 0.4]
        var cursor = [Int](repeating: 0, count: limbs.count)
        var accepted: [CGRect] = []
        var tiers: [[EnvelopeSlot]] = []

        for _ in 0..<3 {
            var tier: [EnvelopeSlot] = []
            for (k, limb) in limbs.enumerated() {
                while cursor[k] < candidates.count {
                    let along = candidates[cursor[k]]
                    cursor[k] += 1
                    let hang = limb.point(at: along)
                    let center = CGPoint(x: hang.x, y: hang.y + threadLength + envelopeSize.height / 2)
                    let rect = CGRect(
                        x: center.x - envelopeSize.width / 2,
                        y: center.y - envelopeSize.height / 2,
                        width: envelopeSize.width,
                        height: envelopeSize.height
                    ).insetBy(dx: -gap, dy: -gap)
                    let clearsTrunk = abs(center.x - midX) - rect.width / 2 >= trunkClearance
                    guard clearsTrunk,
                          bounds.contains(rect),
                          !accepted.contains(where: { $0.intersects(rect) }) else { continue }
                    accepted.append(rect)
                    tier.append(EnvelopeSlot(branch: limb.index, along: along, center: center))
                    break
                }
            }
            tiers.append(tier)
        }

        let side: CGFloat = onLeft ? -1 : 1
        let ground = (0..<3).map { k -> EnvelopeSlot in
            let offset = trunkClearance + unit * 0.012 + envelopeSize.width / 2
                + CGFloat(k) * (envelopeSize.width + unit * 0.016)
            return EnvelopeSlot(
                branch: nil,
                along: 0,
                center: CGPoint(x: midX + side * offset, y: groundY - envelopeSize.height / 2)
            )
        }

        let hanging = tiers.flatMap { $0 }
        let firstTier = tiers[0].isEmpty ? ground.count : tiers[0].count
        return (hanging + ground, firstTier)
    }

    /// Places for opened letters. In a canopy: a sunflower spiral, spaced
    /// so two blossoms never overlap. On a seed or a sprout, whose canopy is
    /// a bud: two small arcs over the top of the trunk.
    private func blossomSpots() -> [CGPoint] {
        if branches.isEmpty || canopyRadius < unit * 0.12 {
            let inner = max(canopyRadius * 0.9, unit * 0.08)
            let outer = inner + unit * 0.075
            let arcs: [(radius: CGFloat, degrees: Double)] = [
                (inner, -150), (inner, -90), (inner, -30), (outer, -120), (outer, -60)
            ]
            return arcs.map { arc -> CGPoint in
                let angle = arc.degrees * .pi / 180
                return CGPoint(x: canopyCenter.x + arc.radius * CGFloat(cos(angle)),
                               y: canopyCenter.y + arc.radius * CGFloat(sin(angle)))
            }
        }
        let spread = canopyRadius * 0.74
        let spacing = letterBlossomRadius * 3.2
        let ratio = spread / spacing
        let count = min(12, max(3, Int(2.8 * ratio * ratio)))
        return (0..<count).map { k -> CGPoint in
            let radius = spread * CGFloat(((Double(k) + 0.5) / Double(count)).squareRoot())
            let angle = Double(k) * 2.399_963 - .pi / 2
            return CGPoint(x: canopyCenter.x + radius * CGFloat(cos(angle)),
                           y: canopyCenter.y + radius * CGFloat(sin(angle)) * 0.85)
        }
    }

    /// Linear probing: the first free index from `start`, wrapping around.
    /// When every index is taken, `start` (two letters then share a place).
    private static func probe(from start: Int, count: Int, taken: inout Set<Int>) -> Int {
        for step in 0..<count {
            let index = (start + step) % count
            if taken.insert(index).inserted { return index }
        }
        return start
    }
}

// MARK: - Painter

/// Draws one frame of the tree from plain values, so the canvas closure
/// captures nothing that can change under it.
private struct TreeCanvasPainter {

    let stage: TreeGrowthStage
    let season: TreeSeason
    let daysTogether: Int
    let memoryCount: Int
    let crownActive: Bool
    let ornaments: [JourneyTreeOrnament]

    private static let paper = Color(red: 0.98, green: 0.95, blue: 0.88)
    private static let crownGold = Color(red: 1.0, green: 0.85, blue: 0.45)

    func draw(in context: GraphicsContext, size: CGSize, motion: TreeCanvasMotion) {
        guard size.width >= 1, size.height >= 1 else { return }
        let layout = TreeCanvasLayout(size: size, stage: stage)
        let palette = TreeCanvasPalette(context.environment.colorScheme)

        drawAmbientGlow(context, layout, motion)
        if crownActive {
            drawCrownRing(context, layout, motion)
        }
        drawGround(context, layout, palette)
        drawTrunkAndBranches(context, layout, palette, motion)
        drawCanopy(context, layout, motion)
        drawBlossoms(context, layout, motion)
        drawFruits(context, layout, motion)
        drawMemoryStars(context, layout, palette, motion)
        drawLetters(context, layout, motion)
    }

    // MARK: Ambient glow

    private func drawAmbientGlow(_ context: GraphicsContext, _ layout: TreeCanvasLayout, _ motion: TreeCanvasMotion) {
        let unit = layout.unit
        let alpha = 0.10 + motion.pulse(0.6) * 0.08
        let rect = CGRect(x: layout.midX - unit * 0.30, y: layout.y(0.18),
                          width: unit * 0.60, height: unit * 0.64)
        // The blur goes on a copy: a filter added to `context` itself would
        // blur everything drawn after it.
        var glow = context
        glow.addFilter(.blur(radius: unit * 0.08))
        glow.fill(Path(ellipseIn: rect),
                  with: .color(Color(red: 1.0, green: 0.78, blue: 0.65).opacity(alpha)))
    }

    // MARK: Crown ring

    private func drawCrownRing(_ context: GraphicsContext, _ layout: TreeCanvasLayout, _ motion: TreeCanvasMotion) {
        let unit = layout.unit
        let crown = layout.crown
        let center = crown.center

        // Soft halo
        let halo = CGRect(x: center.x - crown.radiusX * 1.15, y: center.y - crown.radiusY * 1.6,
                          width: crown.radiusX * 2.3, height: crown.radiusY * 2.2)
        context.fill(Path(ellipseIn: halo), with: .color(Self.crownGold.opacity(0.10)))

        // Arch: the top of a flat ellipse, from 200° round to 340°.
        var arch = Path()
        let steps = 28
        for step in 0...steps {
            let angle = (200.0 + 140.0 * Double(step) / Double(steps)) * .pi / 180
            let point = CGPoint(x: center.x + crown.radiusX * CGFloat(cos(angle)),
                                y: center.y + crown.radiusY * CGFloat(sin(angle)))
            if step == 0 { arch.move(to: point) } else { arch.addLine(to: point) }
        }
        context.stroke(
            arch,
            with: .linearGradient(
                Gradient(colors: [
                    Color(red: 1.0, green: 0.85, blue: 0.40).opacity(0.85),
                    Color(red: 0.95, green: 0.55, blue: 0.30).opacity(0.85)
                ]),
                startPoint: CGPoint(x: center.x - crown.radiusX, y: center.y),
                endPoint: CGPoint(x: center.x + crown.radiusX, y: center.y)
            ),
            style: StrokeStyle(lineWidth: max(1.2, unit * 0.009), lineCap: .round, lineJoin: .round)
        )

        // Five points along the arch, each with a spike and a twinkling tip.
        let half = unit * 0.016
        for i in 0..<5 {
            let progress = Double(i) / 4
            let angle = .pi - (progress * .pi * 0.8 + .pi * 0.1)
            let px = center.x + crown.radiusX * CGFloat(cos(angle))
            let py = center.y - crown.radiusY * CGFloat(sin(angle))
            let twinkle = CGFloat(motion.pulse(1.2, Double(i) * 0.7))
            let spikeHeight = unit * (0.030 + 0.012 * twinkle)

            var point = Path()
            point.move(to: CGPoint(x: px, y: py))
            point.addLine(to: CGPoint(x: px - half, y: py + half))
            point.addLine(to: CGPoint(x: px + half, y: py + half))
            point.closeSubpath()
            context.fill(point, with: .color(Self.crownGold.opacity(0.95)))

            var spike = Path()
            spike.move(to: CGPoint(x: px, y: py))
            spike.addLine(to: CGPoint(x: px, y: py - spikeHeight))
            context.stroke(spike, with: .color(Self.crownGold.opacity(0.85)),
                           style: StrokeStyle(lineWidth: max(1, unit * 0.008), lineCap: .round))

            let dot = unit * (0.011 + 0.007 * twinkle)
            context.fill(
                Path(ellipseIn: CGRect(x: px - dot / 2, y: py - spikeHeight - dot / 2, width: dot, height: dot)),
                with: .color(Color(red: 1.0, green: 0.95, blue: 0.70).opacity(0.95))
            )
        }
    }

    // MARK: Ground

    /// A soft patch of earth, so the trunk (and a seed's letters) rest on
    /// something.
    private func drawGround(_ context: GraphicsContext, _ layout: TreeCanvasLayout, _ palette: TreeCanvasPalette) {
        let radius = layout.unit * (0.10 + 0.15 * stage.trunkScale)
        var ground = context
        ground.translateBy(x: layout.midX, y: layout.groundY + layout.unit * 0.004)
        ground.scaleBy(x: 1, y: 0.14)
        ground.fill(
            Path(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)),
            with: .radialGradient(
                Gradient(colors: [palette.limb.opacity(0.22), palette.limb.opacity(0)]),
                center: .zero, startRadius: 0, endRadius: radius
            )
        )
    }

    // MARK: Trunk + branches

    /// How far a limb's tip has swayed. Envelopes on the limb ride along.
    private func tipSway(_ branch: TreeCanvasLayout.Branch, _ unit: CGFloat, _ motion: TreeCanvasMotion) -> CGSize {
        let phase = Double(branch.index)
        return CGSize(width: CGFloat(motion.wave(0.4, phase)) * unit * 0.007,
                      height: CGFloat(motion.wave(0.45, phase + .pi / 2)) * unit * 0.0055)
    }

    private func drawTrunkAndBranches(_ context: GraphicsContext, _ layout: TreeCanvasLayout,
                                      _ palette: TreeCanvasPalette, _ motion: TreeCanvasMotion) {
        let unit = layout.unit
        let base = layout.trunkBase
        let top = layout.trunkTop
        let height = layout.trunkHeight
        let width = layout.trunkWidth
        let lean = CGFloat(motion.wave(0.3)) * unit * 0.005

        // Trunk: a gentle curve from base to top.
        var trunk = Path()
        trunk.move(to: CGPoint(x: base.x - width / 2, y: base.y))
        trunk.addQuadCurve(to: CGPoint(x: top.x - width * 0.3, y: top.y),
                           control: CGPoint(x: base.x + lean - width, y: base.y - height * 0.4))
        trunk.addLine(to: CGPoint(x: top.x + width * 0.3, y: top.y))
        trunk.addQuadCurve(to: CGPoint(x: base.x + width / 2, y: base.y),
                           control: CGPoint(x: base.x + lean + width, y: base.y - height * 0.4))
        trunk.closeSubpath()
        context.fill(
            trunk,
            with: .linearGradient(
                Gradient(colors: [palette.trunkBase, palette.trunkTop]),
                startPoint: base,
                endPoint: top
            )
        )

        // Highlight on the right side for dimensionality.
        var highlight = Path()
        highlight.move(to: CGPoint(x: base.x + width * 0.35, y: base.y - height * 0.05))
        highlight.addQuadCurve(to: CGPoint(x: top.x + width * 0.2, y: top.y + height * 0.05),
                               control: CGPoint(x: base.x + width * 0.6, y: base.y - height * 0.5))
        context.stroke(highlight, with: .color(Color.white.opacity(0.10)), lineWidth: max(1, unit * 0.008))

        for branch in layout.branches {
            let sway = tipSway(branch, unit, motion)
            // Tapered: the whole limb thin, its inner part thicker, the
            // part nearest the trunk at full width. Round caps blend the steps.
            for (extent, share) in [(CGFloat(1), CGFloat(0.45)), (0.62, 0.72), (0.3, 1)] {
                context.stroke(branch.path(to: extent, tipOffset: sway), with: .color(palette.limb),
                               style: StrokeStyle(lineWidth: max(unit * 0.008, branch.width * share),
                                                  lineCap: .round, lineJoin: .round))
            }

            // A twig off each limb on more mature trees.
            if stage >= .young {
                let direction: CGFloat = branch.isLeft ? -1 : 1
                let mid = branch.point(at: 0.55, tipOffset: sway)
                var twig = Path()
                twig.move(to: mid)
                twig.addQuadCurve(
                    to: CGPoint(x: mid.x + direction * branch.reach * 0.30, y: mid.y - branch.reach * 0.26),
                    control: CGPoint(x: mid.x + direction * branch.reach * 0.12, y: mid.y - branch.reach * 0.04)
                )
                context.stroke(twig, with: .color(palette.twig),
                               style: StrokeStyle(lineWidth: max(unit * 0.007, branch.width * 0.4), lineCap: .round))
            }
        }
    }

    // MARK: Canopy (leaves)

    private func drawCanopy(_ context: GraphicsContext, _ layout: TreeCanvasLayout, _ motion: TreeCanvasMotion) {
        let fullness = stage.canopyFullness
        guard fullness > 0 else { return }
        let unit = layout.unit
        let center = layout.canopyCenter
        let radius = layout.canopyRadius
        let colors = season.canopyColors

        // Soft silhouette: one blurred ellipse, on a copy of the context.
        let baseRect = CGRect(x: center.x - radius, y: center.y - radius * 0.85,
                              width: radius * 2, height: radius * 1.7)
        var blurred = context
        blurred.addFilter(.blur(radius: unit * 0.05))
        blurred.fill(
            Path(ellipseIn: baseRect),
            with: .linearGradient(
                Gradient(colors: [colors.top.opacity(0.55), colors.bottom.opacity(0.45)]),
                startPoint: CGPoint(x: baseRect.midX, y: baseRect.minY),
                endPoint: CGPoint(x: baseRect.midX, y: baseRect.maxY)
            )
        )

        // Both stops resolved once per frame; each leaf blends plain numbers.
        let top = colors.top.resolve(in: context.environment)
        let bottom = colors.bottom.resolve(in: context.environment)

        // Crisp leaf clusters, seeded from the days together so the tree
        // looks the same on every frame.
        let leafCount = Int(80 * fullness) + 6
        var rng = SeededRNG(seed: UInt64(truncatingIfNeeded: daysTogether) &* 17 &+ 11)
        for i in 0..<leafCount {
            let angle = rng.nextDouble() * .pi * 2
            let distance = CGFloat(rng.nextDouble()) * radius * 0.95
            let x = center.x + CGFloat(cos(angle)) * distance
            let y = center.y + CGFloat(sin(angle)) * distance * 0.85
            let flutter = CGFloat(motion.wave(0.6 + rng.nextDouble() * 0.4, Double(i))) * unit * 0.006
            let leafSize = unit * CGFloat(0.012 + rng.nextDouble() * 0.018)
            let leafRect = CGRect(x: x - leafSize / 2, y: y - leafSize / 2 + flutter,
                                  width: leafSize, height: leafSize * 1.4)
            let mix = Float(rng.nextDouble())
            context.fill(
                Path(ellipseIn: leafRect),
                with: .color(
                    red: Double(top.red + (bottom.red - top.red) * mix),
                    green: Double(top.green + (bottom.green - top.green) * mix),
                    blue: Double(top.blue + (bottom.blue - top.blue) * mix),
                    opacity: Double(top.opacity + (bottom.opacity - top.opacity) * mix) * 0.85
                )
            )
        }
    }

    // MARK: Blossoms

    private func drawBlossoms(_ context: GraphicsContext, _ layout: TreeCanvasLayout, _ motion: TreeCanvasMotion) {
        let count = stage.blossomCount
        guard count > 0 else { return }
        let center = layout.canopyCenter
        let radius = layout.canopyRadius
        let spin = motion.turn(0.12)

        // 5-petal blossom: soft pink for spring/summer, warmer for autumn.
        let petalColor: Color = {
            switch season {
            case .spring: return Color(red: 1.0,  green: 0.78, blue: 0.86)
            case .summer: return Color(red: 1.0,  green: 0.72, blue: 0.78)
            case .autumn: return Color(red: 1.0,  green: 0.82, blue: 0.55)
            case .winter: return Color(red: 0.92, green: 0.94, blue: 1.00)
            }
        }()
        let coreColor = Color(red: 1.0, green: 0.85, blue: 0.30)

        var rng = SeededRNG(seed: UInt64(truncatingIfNeeded: daysTogether) &* 31 &+ 7)
        for i in 0..<count {
            let angle = rng.nextDouble() * .pi * 2
            let distance = CGFloat(0.4 + rng.nextDouble() * 0.55) * radius
            let x = center.x + CGFloat(cos(angle)) * distance
            let y = center.y + CGFloat(sin(angle)) * distance * 0.9
            let pulse = CGFloat(motion.pulse(0.9, Double(i) * 1.3))
            let r = layout.blossomRadius * (0.87 + 0.26 * pulse)

            for p in 0..<5 {
                let petalAngle = Double(p) * (.pi * 2 / 5) + spin
                let px = x + CGFloat(cos(petalAngle)) * r * 0.9
                let py = y + CGFloat(sin(petalAngle)) * r * 0.9
                context.fill(
                    Path(ellipseIn: CGRect(x: px - r * 0.55, y: py - r * 0.55, width: r * 1.1, height: r * 1.1)),
                    with: .color(petalColor.opacity(0.85))
                )
            }
            context.fill(
                Path(ellipseIn: CGRect(x: x - r * 0.35, y: y - r * 0.35, width: r * 0.7, height: r * 0.7)),
                with: .color(coreColor.opacity(0.95))
            )
        }
    }

    // MARK: Fruits

    private func drawFruits(_ context: GraphicsContext, _ layout: TreeCanvasLayout, _ motion: TreeCanvasMotion) {
        let count = stage.fruitCount
        guard count > 0 else { return }
        let unit = layout.unit
        let center = layout.canopyCenter
        let radius = layout.canopyRadius

        var rng = SeededRNG(seed: UInt64(truncatingIfNeeded: daysTogether) &* 53 &+ 41)
        for i in 0..<count {
            let angle = rng.nextDouble() * .pi * 2
            let distance = CGFloat(0.5 + rng.nextDouble() * 0.4) * radius
            let baseX = center.x + CGFloat(cos(angle)) * distance
            let baseY = center.y + CGFloat(sin(angle)) * distance * 0.9

            // Gentle hang sway
            let swayY = CGFloat(motion.wave(0.4, Double(i))) * unit * 0.0036
            let fruitRadius = unit * CGFloat(0.025 + rng.nextDouble() * 0.009)

            // Stem
            var stem = Path()
            stem.move(to: CGPoint(x: baseX, y: baseY - fruitRadius - unit * 0.014))
            stem.addLine(to: CGPoint(x: baseX, y: baseY - fruitRadius + unit * 0.004))
            context.stroke(stem, with: .color(Color(red: 0.35, green: 0.25, blue: 0.18)),
                           lineWidth: max(0.75, unit * 0.007))

            // Fruit body, golden
            let fruitRect = CGRect(x: baseX - fruitRadius, y: baseY - fruitRadius + swayY,
                                   width: fruitRadius * 2, height: fruitRadius * 2)
            context.fill(
                Path(ellipseIn: fruitRect),
                with: .radialGradient(
                    Gradient(colors: [
                        Color(red: 1.0, green: 0.92, blue: 0.55),
                        Color(red: 0.95, green: 0.65, blue: 0.20)
                    ]),
                    center: CGPoint(x: fruitRect.midX - fruitRadius * 0.2, y: fruitRect.midY - fruitRadius * 0.3),
                    startRadius: 1,
                    endRadius: fruitRadius * 1.1
                )
            )

            // Highlight
            context.fill(
                Path(ellipseIn: CGRect(x: fruitRect.midX - fruitRadius * 0.6, y: fruitRect.midY - fruitRadius * 0.6,
                                       width: fruitRadius * 0.5, height: fruitRadius * 0.4)),
                with: .color(.white.opacity(0.55))
            )
        }
    }

    // MARK: Memory stars

    private func drawMemoryStars(_ context: GraphicsContext, _ layout: TreeCanvasLayout,
                                 _ palette: TreeCanvasPalette, _ motion: TreeCanvasMotion) {
        guard memoryCount > 0 else { return }
        let unit = layout.unit
        // Fewer on a narrow frame, so the constellation stays readable.
        let count = min(memoryCount, layout.size.width < 240 ? 12 : 24)
        let center = CGPoint(x: layout.midX, y: layout.y(0.36))

        for i in 0..<count {
            // Seeded by its own index: a new memory adds a star, moves none.
            var rng = SeededRNG(seed: UInt64(i) &* 977 &+ 13)
            let baseAngle = rng.nextDouble() * .pi * 2
            let speed = 0.10 + rng.nextDouble() * 0.18
            let radiusX = unit * CGFloat(0.30 + rng.nextDouble() * 0.15)
            let radiusY = unit * CGFloat(0.13 + rng.nextDouble() * 0.11)
            let phase = baseAngle + motion.turn(speed)
            let x = center.x + CGFloat(cos(phase)) * radiusX
            let y = center.y + CGFloat(sin(phase)) * radiusY

            let twinkle = CGFloat(motion.pulse(1.3, Double(i) * 0.9))
            let starSize = unit * (0.008 + 0.008 * twinkle)

            let glowRadius = starSize * 2
            context.fill(
                Path(ellipseIn: CGRect(x: x - glowRadius, y: y - glowRadius, width: glowRadius * 2, height: glowRadius * 2)),
                with: .radialGradient(
                    Gradient(colors: [palette.starGlow.opacity(0.40), palette.starGlow.opacity(0)]),
                    center: CGPoint(x: x, y: y), startRadius: 0, endRadius: glowRadius
                )
            )
            context.fill(
                Path(ellipseIn: CGRect(x: x - starSize / 2, y: y - starSize / 2, width: starSize, height: starSize)),
                with: .color(palette.starCore.opacity(0.95))
            )
        }
    }

    // MARK: Letters

    private func drawLetters(_ context: GraphicsContext, _ layout: TreeCanvasLayout, _ motion: TreeCanvasMotion) {
        guard !ornaments.isEmpty else { return }
        let placements = layout.place(ornaments)
        for placement in placements where placement.ornament.kind == .blossom {
            drawLetterBlossom(context, layout, placement, motion)
        }
        for placement in placements where placement.ornament.kind != .blossom {
            drawEnvelope(context, layout, placement, motion)
        }
    }

    /// A per-letter phase, so neighbouring envelopes never swing in step.
    private func letterPhase(_ ornament: JourneyTreeOrnament) -> Double {
        Double(ornament.seed % 6_283) / 1_000
    }

    private func drawEnvelope(_ context: GraphicsContext, _ layout: TreeCanvasLayout,
                              _ placement: TreeCanvasLayout.Placement, _ motion: TreeCanvasMotion) {
        let unit = layout.unit
        let size = layout.envelopeSize
        let isReady = placement.ornament.kind == .readyEnvelope
        let phase = letterPhase(placement.ornament)
        // Pulses only while the tree moves; otherwise a steady glow.
        let glow = motion.isLive ? 0.22 + 0.26 * motion.pulse(1.6, phase) : 0.35

        var local = context
        switch placement.mount {
        case .hanging(let branchIndex, let along):
            let branch = layout.branches[branchIndex]
            let hang = branch.point(at: along, tipOffset: tipSway(branch, unit, motion))
            // A gentle pendulum, ±3°, only while the tree moves.
            let swing = motion.isLive ? motion.wave(1.1, phase) * 3 : 0
            local.translateBy(x: hang.x, y: hang.y)
            local.rotate(by: .degrees(swing))

            var thread = Path()
            thread.move(to: .zero)
            thread.addLine(to: CGPoint(x: 0, y: layout.threadLength))
            local.stroke(thread, with: .color(FutureLetterStyle.goldDeep.opacity(0.85)),
                         lineWidth: max(0.5, unit * 0.003))
            drawEnvelopeBody(local, center: CGPoint(x: 0, y: layout.threadLength + size.height / 2),
                             size: size, isReady: isReady, glow: glow)

        case .resting(let tilt):
            local.translateBy(x: placement.center.x, y: placement.center.y)
            local.rotate(by: .degrees(tilt))
            drawEnvelopeBody(local, center: .zero, size: size, isReady: isReady, glow: glow)

        case .bloom:
            break
        }
    }

    /// Cream paper, a 0.75pt deep-gold edge, the flap's V and a wax seal.
    /// A ready letter adds a soft gold halo behind.
    private func drawEnvelopeBody(_ context: GraphicsContext, center: CGPoint, size: CGSize,
                                  isReady: Bool, glow: Double) {
        let rect = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                          width: size.width, height: size.height)
        if isReady {
            let haloRadius = size.width * 1.2
            context.fill(
                Path(ellipseIn: CGRect(x: center.x - haloRadius, y: center.y - haloRadius,
                                       width: haloRadius * 2, height: haloRadius * 2)),
                with: .radialGradient(
                    Gradient(colors: [FutureLetterStyle.gold.opacity(glow), FutureLetterStyle.gold.opacity(0)]),
                    center: center, startRadius: 0, endRadius: haloRadius
                )
            )
        }

        let paper = Path(roundedRect: rect, cornerRadius: size.width * 0.1)
        context.fill(paper, with: .color(Self.paper))
        context.stroke(paper, with: .color(FutureLetterStyle.goldDeep), lineWidth: 0.75)

        let apex = CGPoint(x: center.x, y: center.y + size.height * 0.1)
        let inset: CGFloat = 0.6
        var flap = Path()
        flap.move(to: CGPoint(x: rect.minX + inset, y: rect.minY + inset))
        flap.addLine(to: apex)
        flap.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY + inset))
        context.stroke(flap, with: .color(FutureLetterStyle.goldDeep),
                       style: StrokeStyle(lineWidth: 0.75, lineCap: .round, lineJoin: .round))

        let seal = size.width * 0.15
        context.fill(Path(ellipseIn: CGRect(x: apex.x - seal, y: apex.y - seal, width: seal * 2, height: seal * 2)),
                     with: .color(FutureLetterStyle.accent))
    }

    /// An opened letter: a gold five-petal blossom with a deep-gold rim and
    /// a sealing-wax centre, over a faint warm glow.
    private func drawLetterBlossom(_ context: GraphicsContext, _ layout: TreeCanvasLayout,
                                   _ placement: TreeCanvasLayout.Placement, _ motion: TreeCanvasMotion) {
        let ornament = placement.ornament
        let breathe: CGFloat = motion.isLive ? 1 + 0.05 * CGFloat(motion.wave(0.9, letterPhase(ornament))) : 1
        let r = layout.letterBlossomRadius * breathe
        let center = placement.center
        // Each blossom turned its own way (the petals repeat every 72°).
        let spin = Double(ornament.seed % 72) * .pi / 180

        let glowRadius = r * 2
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - glowRadius, y: center.y - glowRadius,
                                   width: glowRadius * 2, height: glowRadius * 2)),
            with: .radialGradient(
                Gradient(colors: [FutureLetterStyle.gold.opacity(0.35), FutureLetterStyle.gold.opacity(0)]),
                center: center, startRadius: 0, endRadius: glowRadius
            )
        )

        let petalCenters = (0..<5).map { p -> CGPoint in
            let angle = Double(p) * (.pi * 2 / 5) + spin
            return CGPoint(x: center.x + CGFloat(cos(angle)) * r * 0.9,
                           y: center.y + CGFloat(sin(angle)) * r * 0.9)
        }
        for petal in petalCenters {
            let rim = r * 0.64
            context.fill(Path(ellipseIn: CGRect(x: petal.x - rim, y: petal.y - rim, width: rim * 2, height: rim * 2)),
                         with: .color(FutureLetterStyle.goldDeep))
        }
        for petal in petalCenters {
            let fill = r * 0.52
            context.fill(Path(ellipseIn: CGRect(x: petal.x - fill, y: petal.y - fill, width: fill * 2, height: fill * 2)),
                         with: .color(FutureLetterStyle.gold))
        }
        let core = r * 0.36
        context.fill(Path(ellipseIn: CGRect(x: center.x - core, y: center.y - core, width: core * 2, height: core * 2)),
                     with: .color(FutureLetterStyle.accent))
    }
}

// MARK: - Helpers

/// Tiny seeded RNG so the tree topology is deterministic per couple.
/// xorshift64, with the seed scrambled by splitmix64 first: xorshift's
/// first draws from a small seed (a star's index) are all near zero.
private struct SeededRNG {
    private var state: UInt64

    init(seed: UInt64) {
        var z = seed &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        self.state = z == 0 ? 0xdead_beef_dead_beef : z
    }

    mutating func nextUInt64() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    mutating func nextDouble() -> Double {
        // 53-bit fraction in [0, 1)
        Double(nextUInt64() >> 11) / Double(UInt64(1) << 53)
    }
}

// MARK: - Previews

private enum TreeCanvasPreviewSamples {
    static func ornament(_ id: String, _ kind: JourneyTreeOrnament.Kind,
                         _ direction: JourneyLetterDirection) -> JourneyTreeOrnament {
        JourneyTreeOrnament(id: id, kind: kind, direction: direction, seed: JourneyTreeOrnament.stableSeed(id))
    }

    /// One sealed envelope per side, one ready envelope and two blossoms.
    static let letters: [JourneyTreeOrnament] = [
        ornament("preview-sealed-from-partner", .sealedEnvelope, .toMe),
        ornament("preview-sealed-from-you", .sealedEnvelope, .fromMe),
        ornament("preview-ready-from-partner", .readyEnvelope, .toMe),
        ornament("preview-opened-1", .blossom, .toMe),
        ornament("preview-opened-2", .blossom, .fromMe)
    ]

    static func tree(_ stage: TreeGrowthStage, letters: Bool = true) -> RelationshipTreeCanvas {
        RelationshipTreeCanvas(
            stage: stage,
            season: .current(),
            daysTogether: stage.startDay + 20,
            memoryCount: 9,
            crownActive: stage.showsAmbientCrown,
            ornaments: letters ? Self.letters : [],
            onSelectOrnament: { _ in }
        )
    }
}

/// The frame's edge, so clipping would show.
private struct TreeCanvasPreviewFrame: ViewModifier {
    let width: CGFloat
    let height: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(width: width, height: height)
            .overlay(Rectangle().strokeBorder(Color.secondary.opacity(0.35), lineWidth: 0.5))
    }
}

#Preview("Blooming · hero 176×196") {
    TreeCanvasPreviewSamples.tree(.blooming)
        .modifier(TreeCanvasPreviewFrame(width: 176, height: 196))
        .padding()
        .background(Brand.backgroundTop)
}

#Preview("Blooming · accessibility 343×180") {
    TreeCanvasPreviewSamples.tree(.blooming)
        .modifier(TreeCanvasPreviewFrame(width: 343, height: 180))
        .padding()
        .background(Brand.backgroundTop)
}

#Preview("Every stage · 160×160, 176×196, 343×180") {
    ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(TreeGrowthStage.allCases, id: \.self) { stage in
                VStack(alignment: .leading, spacing: 8) {
                    Text(stage.displayName)
                        .font(JourneyFont.label)
                        .foregroundStyle(Brand.textSecondary)
                    HStack(alignment: .bottom, spacing: 8) {
                        TreeCanvasPreviewSamples.tree(stage)
                            .modifier(TreeCanvasPreviewFrame(width: 160, height: 160))
                        TreeCanvasPreviewSamples.tree(stage)
                            .modifier(TreeCanvasPreviewFrame(width: 176, height: 196))
                    }
                    TreeCanvasPreviewSamples.tree(stage)
                        .modifier(TreeCanvasPreviewFrame(width: 343, height: 180))
                }
            }
        }
        .padding()
    }
    .background(Brand.backgroundTop)
}
