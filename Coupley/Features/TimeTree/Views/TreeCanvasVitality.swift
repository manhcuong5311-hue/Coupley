//
//  TreeCanvasVitality.swift
//  Coupley
//
//  Our Garden: how a tree shows its care (spec C6). Thirst droops and dulls
//  the leaves, the soil bed dries and cracks, dew beads after a watering,
//  revival springs the leaves back, and a freshly watered tree is lush:
//  greener, fuller and glossier than its baseline. Also the watering
//  note's tag on the lowest right limb.
//
//  The app's trees never get thirst or dry soil while
//  `GardenTreeLook.withersWhenThirsty` is off (owner decision 3: watering
//  is a reward only), so their droop paths draw nothing; the code stays for
//  that switch, the lab's species gallery and the previews below.
//
//  Main-actor isolated like `TreeCanvasPainter` (spec I6). Never mark it
//  `nonisolated`.
//
//  Every effect here is zero for `TreeVitality.healthy`, and the painter
//  skips what is zero, so today's tree is drawn exactly as before.
//

import Foundation
import SwiftUI

// MARK: - Curves and colours

enum TreeCanvasVitality {
    /// Dry olive the leaves fade toward while thirsty.
    static let dryLeafTop = GardenRGB(0x9C9A5A)
    static let dryLeafBottom = GardenRGB(0x7D6B3F)
    /// Vivid spring green a freshly watered tree's leaves lean toward.
    static let lushLeafTop = GardenRGB(0x5FBF4A)
    static let lushLeafBottom = GardenRGB(0x3E8E3A)
    /// The soil bed, dry and soaked, and the hairline cracks of a thirsty one.
    static let drySoil = GardenRGB(0xC2A27C)
    static let wetSoil = GardenRGB(0x5A3E2B)
    static let paleSoil = GardenRGB(0xE6D8BF)
    static let soilCrack = GardenRGB(0x7A6248)
    /// The note tag: cream paper, a blue drop and a twine thread.
    static let tagInk = GardenRGB(0x4A90C2)
    static let tagDrop = GardenRGB(0x5AAFE6)
    static let tagTwine = GardenRGB(0xB08A5A)
    /// A closed blossom's green sepal.
    static let budSepal = GardenRGB(0x6E8B4A)

    /// How far the leaf colour mixes toward dry olive for a droop `d`:
    /// half of `d` up to 0.5 (25% when thirsty), then 0.3 per unit more
    /// (40% when resting). Nothing for the revival's overshoot (d < 0).
    static func dryMix(droop: Double) -> Double {
        guard droop > 0 else { return 0 }
        let d = min(1, droop)
        return d <= 0.5 ? 0.5 * d : 0.25 + 0.3 * (d - 0.5)
    }

    /// How far the leaf colour mixes toward vivid spring green for a
    /// lushness `l` (0.30 × l).
    static func lushMix(lushness: Double) -> Double {
        0.30 * min(1, max(0, lushness))
    }

    /// Moves a colour away from its own grey by `amount` (0.12 = +12%).
    static func saturated(_ color: GardenRGB, by amount: Double) -> GardenRGB {
        let grey = 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b
        func push(_ c: Double) -> Double { min(1, max(0, grey + (c - grey) * (1 + amount))) }
        return GardenRGB(r: push(color.r), g: push(color.g), b: push(color.b))
    }
}

/// The two leaf colours of one frame, after the care has dried or
/// refreshed them, both as colours and resolved (each leaf blends plain
/// numbers between the two).
struct TreeLeafTint {
    let top: Color
    let bottom: Color
    let topResolved: Color.Resolved
    let bottomResolved: Color.Resolved
}

// MARK: - One frame's care

/// What `TreeVitality` means for one frame at `time`: the droop to draw
/// (eased through a revival), and what follows from it. All zero for
/// `.healthy`.
struct TreeCanvasCare {
    /// `TreeVitality.healthy`: nothing to draw beyond today's tree.
    let isPlain: Bool
    /// 0…1 (and a little below 0 during the revival's overshoot).
    let droop: Double
    /// 0…1, rising on the revival's curve after a watering.
    let lushness: Double
    let wetness: Double
    let dew: Double
    let soilDryness: Double
    /// Leaves on the ground: 3 when thirsty, 6 when resting.
    let fallenCount: Int
    /// 1 while thirsty; fades on the revival's curve.
    let fallenOpacity: Double

    init(_ vitality: TreeVitality, at time: TimeInterval) {
        func unit(_ value: Double) -> Double { min(1, max(0, value)) }
        let droop = vitality.droop(at: time)
        // How far the revival has come, on the same easeOutBack curve as
        // the droop; a tree with nothing to revive takes the 1.2 s plainly.
        let progress: Double
        if let start = vitality.reviveStart {
            progress = vitality.reviveFrom > 0
                ? unit(1 - droop / vitality.reviveFrom)
                : unit((time - start) / 1.2)
        } else {
            progress = 1
        }
        let fallenFrom = vitality.reviveStart == nil ? vitality.thirst : vitality.reviveFrom
        isPlain = vitality == .healthy
        self.droop = droop
        lushness = unit(vitality.lushness) * progress
        wetness = unit(vitality.wetness)
        dew = unit(vitality.dew)
        soilDryness = unit(vitality.soilDryness)
        fallenCount = Int((6 * unit(fallenFrom)).rounded())
        fallenOpacity = vitality.reviveStart == nil ? 1 : 1 - progress
    }

    /// Thirsty leaves hang still: flutter × (1 − 0.6d).
    var flutterScale: CGFloat { 1 - 0.6 * CGFloat(droop) }

    /// Thirsty leaves hang long: height × (1 + 0.25d).
    var leafStretch: CGFloat { 1 + 0.25 * CGFloat(droop) }

    /// How far a leaf `distance` from the canopy centre sinks: the outer
    /// leaves most (spec C6: d · unit · 0.012 · (0.4 + 0.6 · r/R)).
    func leafDrop(distance: CGFloat, radius: CGFloat, unit: CGFloat) -> CGFloat {
        guard radius > 0 else { return 0 }
        return CGFloat(droop) * unit * 0.012 * (0.4 + 0.6 * distance / radius)
    }

    /// Blossoms shrink with thirst and open 10% wider when lush.
    var blossomScale: CGFloat {
        CGFloat((1 - 0.25 * droop) * (1 + 0.10 * lushness))
    }

    /// A resting tree's blossoms close into buds.
    var closesBlossoms: Bool { droop >= 0.95 }

    /// Extra leaves round the canopy's edge when lush.
    var extraLeafCount: Int { Int((8 * lushness).rounded()) }

    /// Dew beads on the leaves after a watering.
    var dewCount: Int { Int((12 * dew).rounded()) }

    /// The white sheen on a leaf `height` above the canopy centre: up to
    /// 18% × lushness on the topmost leaves, nothing below the centre.
    func sheen(atHeight height: CGFloat, radius: CGFloat) -> Double {
        guard lushness > 0, radius > 0 else { return 0 }
        let upper = min(1, max(0, Double(height / (radius * 0.85))))
        return 0.18 * lushness * upper
    }

    /// The species' leaf colours, refreshed toward spring green (and a
    /// little more saturated) when lush, faded toward dry olive by thirst.
    /// Unchanged colours when neither applies.
    func leafTint(_ colors: (top: Color, bottom: Color), in environment: EnvironmentValues) -> TreeLeafTint {
        let top = colors.top.resolve(in: environment)
        let bottom = colors.bottom.resolve(in: environment)
        let dry = TreeCanvasVitality.dryMix(droop: droop)
        guard dry > 0 || lushness > 0 else {
            return TreeLeafTint(top: colors.top, bottom: colors.bottom, topResolved: top, bottomResolved: bottom)
        }
        let newTop = adjusted(top, lush: TreeCanvasVitality.lushLeafTop, dry: TreeCanvasVitality.dryLeafTop, dryMix: dry)
        let newBottom = adjusted(bottom, lush: TreeCanvasVitality.lushLeafBottom, dry: TreeCanvasVitality.dryLeafBottom, dryMix: dry)
        return TreeLeafTint(top: Color(newTop), bottom: Color(newBottom), topResolved: newTop, bottomResolved: newBottom)
    }

    private func adjusted(_ color: Color.Resolved, lush: GardenRGB, dry: GardenRGB, dryMix: Double) -> Color.Resolved {
        var rgb = GardenRGB(r: Double(color.red), g: Double(color.green), b: Double(color.blue))
        if lushness > 0 {
            rgb = TreeCanvasVitality.saturated(rgb.mixed(with: lush, TreeCanvasVitality.lushMix(lushness: lushness)),
                                               by: 0.12 * lushness)
        }
        if dryMix > 0 {
            rgb = rgb.mixed(with: dry, dryMix)
        }
        return Color.Resolved(red: Float(rgb.r), green: Float(rgb.g), blue: Float(rgb.b), opacity: color.opacity)
    }

    /// The soil bed's colour: dry → soaked by wetness, paled while the
    /// garden is ready for water.
    var soilColor: Color {
        TreeCanvasVitality.drySoil
            .mixed(with: TreeCanvasVitality.wetSoil, wetness)
            .mixed(with: TreeCanvasVitality.paleSoil, 0.45 * soilDryness)
            .color
    }
}

// MARK: - Geometry

extension TreeCanvasLayout {
    /// The soil bed at the trunk base (rx 0.16, ry 0.035 of the side).
    var soilBedRect: CGRect {
        CGRect(x: midX - unit * 0.16, y: groundY - unit * 0.035, width: unit * 0.32, height: unit * 0.07)
    }

    /// A letter's centre at rest, with its limb drooped by `droop` as
    /// drawn, so its tap target sits on the envelope.
    func restingCenter(of placement: Placement, droop: Double) -> CGPoint {
        guard droop != 0, case .hanging(let index, let along) = placement.mount else { return placement.center }
        let branch = branches[index]
        let hang = branch.point(at: along, tipOffset: tipOffset(of: branch, motion: .rest, droop: droop))
        return CGPoint(x: hang.x, y: hang.y + threadLength + envelopeSize.height / 2)
    }

    var noteTagSize: CGSize { CGSize(width: unit * 0.06, height: unit * 0.08) }

    /// Where the note tag's thread is tied: the lowest right limb at 72%
    /// of its length (a palm's lowest right frond), as it sways and droops.
    /// Nil on a seed or sprout, whose tag rests on the ground.
    func noteTagHangPoint(stage: TreeGrowthStage, species: GardenSpecies,
                          motion: TreeCanvasMotion, droop: Double) -> CGPoint? {
        guard stage > .sprout else { return nil }
        if species == .palm {
            return palmFronds(motion: motion, droop: droop).last?.point(at: 0.72)
        }
        guard let limb = branches.first(where: { !$0.isLeft }) else { return nil }
        return limb.point(at: 0.72, tipOffset: tipOffset(of: limb, motion: motion, droop: droop))
    }

    /// The tag's centre: under its thread, or on the ground right of the
    /// trunk when there is nothing to hang it from.
    func noteTagCenter(hangingFrom hang: CGPoint?) -> CGPoint {
        if let hang {
            return CGPoint(x: hang.x, y: hang.y + threadLength + noteTagSize.height / 2)
        }
        return CGPoint(x: midX + unit * 0.15, y: groundY - noteTagSize.height / 2)
    }
}

// MARK: - Drawing

extension TreeCanvasPainter {

    /// The soil bed at the trunk base: soaked dark after a watering, pale
    /// while the garden is ready, cracked while thirsty, with a puddle
    /// glint while it is still wet through.
    func drawSoilBed(_ context: GraphicsContext, _ layout: TreeCanvasLayout, _ care: TreeCanvasCare) {
        let rect = layout.soilBedRect
        let rx = rect.width / 2
        let ry = rect.height / 2
        let soil = care.soilColor

        var bed = context
        bed.translateBy(x: rect.midX, y: rect.midY)
        bed.scaleBy(x: 1, y: ry / rx)
        bed.fill(
            Path(ellipseIn: CGRect(x: -rx, y: -rx, width: rx * 2, height: rx * 2)),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: soil.opacity(0.55), location: 0),
                    .init(color: soil.opacity(0.55), location: 0.62),
                    .init(color: soil.opacity(0), location: 1)
                ]),
                center: .zero, startRadius: 0, endRadius: rx
            )
        )

        if care.droop >= 0.5 {
            var cracks = Path()
            var rng = TreeCanvasRNG(seed: topologySeed &* 71 &+ 5)
            let squash = ry / rx
            for _ in 0..<3 {
                let angle = rng.nextDouble() * .pi * 2
                var reach = rx * CGFloat(0.25 + rng.nextDouble() * 0.15)
                cracks.move(to: CGPoint(x: rect.midX + CGFloat(cos(angle)) * reach,
                                        y: rect.midY + CGFloat(sin(angle)) * reach * squash))
                for _ in 0..<3 {
                    reach += rx * CGFloat(0.14 + rng.nextDouble() * 0.10)
                    let bend = angle + (rng.nextDouble() - 0.5) * 0.6
                    cracks.addLine(to: CGPoint(x: rect.midX + CGFloat(cos(bend)) * reach,
                                               y: rect.midY + CGFloat(sin(bend)) * reach * squash))
                }
            }
            context.stroke(cracks, with: .color(TreeCanvasVitality.soilCrack.color.opacity(0.4)), lineWidth: 0.6)
        }

        if care.wetness > 0.85 {
            let glint = CGRect(x: rect.midX - rx * 0.66, y: rect.midY - ry * 0.42,
                               width: rx * 0.42, height: ry * 0.55)
            context.fill(Path(ellipseIn: glint), with: .color(Color.white.opacity(0.35)))
        }
    }

    /// Dry leaves lying round the trunk: 3 when thirsty, 6 when resting.
    /// They fade as the tree revives.
    func drawFallenLeaves(_ context: GraphicsContext, _ layout: TreeCanvasLayout, _ care: TreeCanvasCare) {
        guard care.fallenCount > 0, care.fallenOpacity > 0 else { return }
        let unit = layout.unit
        var rng = TreeCanvasRNG(seed: topologySeed &* 83 &+ 29)
        for i in 0..<care.fallenCount {
            let side: CGFloat = i % 2 == 0 ? -1 : 1
            let offset = layout.trunkWidth * 0.7 + unit * CGFloat(0.015 + rng.nextDouble() * 0.11)
            let center = CGPoint(x: layout.midX + side * offset,
                                 y: layout.groundY - unit * CGFloat(0.002 + rng.nextDouble() * 0.012))
            let tilt = (rng.nextDouble() - 0.5) * 1.6
            let width = unit * CGFloat(0.022 + rng.nextDouble() * 0.008)
            let color = TreeCanvasVitality.dryLeafTop.mixed(with: TreeCanvasVitality.dryLeafBottom, rng.nextDouble())
            var leaf = context
            leaf.translateBy(x: center.x, y: center.y)
            leaf.rotate(by: .radians(tilt))
            leaf.fill(Path(ellipseIn: CGRect(x: -width / 2, y: -width / 4, width: width, height: width / 2)),
                      with: .color(color.color.opacity(0.9 * care.fallenOpacity)))
        }
    }

    /// White beads of dew on seeded leaves after a watering, twinkling
    /// while the tree moves.
    func drawDew(_ context: GraphicsContext, _ layout: TreeCanvasLayout,
                 _ motion: TreeCanvasMotion, _ care: TreeCanvasCare) {
        let count = care.dewCount
        guard count > 0 else { return }
        let points = foliagePoints(count: count, seed: topologySeed &* 97 &+ 3,
                                   layout: layout, motion: motion, care: care)
        for (i, point) in points.enumerated() {
            let twinkle = motion.isLive ? 0.6 + 0.4 * motion.pulse(2.2, Double(i) * 1.7) : 0.85
            context.fill(Path(ellipseIn: CGRect(x: point.x - 1.2, y: point.y - 1.2, width: 2.4, height: 2.4)),
                         with: .color(Color.white.opacity(0.6 * twinkle)))
            context.fill(Path(ellipseIn: CGRect(x: point.x - 1.05, y: point.y - 1.05, width: 1.2, height: 1.2)),
                         with: .color(Color.white.opacity(twinkle)))
        }
    }

    /// A blossom closed against thirst: a petal-coloured bud on a sepal.
    func drawBud(_ context: GraphicsContext, at center: CGPoint, radius r: CGFloat, color: Color) {
        context.fill(Path(ellipseIn: CGRect(x: center.x - r * 0.3, y: center.y + r * 0.2, width: r * 0.6, height: r * 0.35)),
                     with: .color(TreeCanvasVitality.budSepal.color.opacity(0.9)))
        context.fill(Path(ellipseIn: CGRect(x: center.x - r * 0.42, y: center.y - r * 0.62, width: r * 0.84, height: r * 1.1)),
                     with: .color(color.opacity(0.85)))
    }

    /// The watering note's paper tag: a cream luggage tag with a blue drop,
    /// on a twine thread from the lowest right limb (swinging gently while
    /// the tree moves), or resting on the ground beside a small tree.
    func drawNoteTag(_ context: GraphicsContext, _ layout: TreeCanvasLayout,
                     _ motion: TreeCanvasMotion, _ care: TreeCanvasCare) {
        let size = layout.noteTagSize
        var local = context
        if let hang = layout.noteTagHangPoint(stage: stage, species: style.species, motion: motion, droop: care.droop) {
            let swing = motion.isLive ? motion.wave(1.0, 0.7) * 4 : 0
            local.translateBy(x: hang.x, y: hang.y)
            local.rotate(by: .degrees(swing))
            var thread = Path()
            thread.move(to: .zero)
            thread.addLine(to: CGPoint(x: 0, y: layout.threadLength))
            local.stroke(thread, with: .color(TreeCanvasVitality.tagTwine.color.opacity(0.9)),
                         lineWidth: max(0.5, layout.unit * 0.003))
            local.translateBy(x: 0, y: layout.threadLength + size.height / 2)
        } else {
            let center = layout.noteTagCenter(hangingFrom: nil)
            local.translateBy(x: center.x, y: center.y)
            local.rotate(by: .degrees(-8))
        }

        let w = size.width
        let h = size.height
        let corner = w * 0.3
        var tag = Path()
        tag.move(to: CGPoint(x: -w / 2, y: -h / 2 + corner))
        tag.addLine(to: CGPoint(x: -w / 2 + corner, y: -h / 2))
        tag.addLine(to: CGPoint(x: w / 2 - corner, y: -h / 2))
        tag.addLine(to: CGPoint(x: w / 2, y: -h / 2 + corner))
        tag.addLine(to: CGPoint(x: w / 2, y: h / 2))
        tag.addLine(to: CGPoint(x: -w / 2, y: h / 2))
        tag.closeSubpath()
        let ink = TreeCanvasVitality.tagInk.color
        local.fill(tag, with: .color(Self.paper))
        local.stroke(tag, with: .color(ink), lineWidth: 0.75)

        let hole = w * 0.08
        local.stroke(Path(ellipseIn: CGRect(x: -hole, y: -h / 2 + corner * 0.9 - hole, width: hole * 2, height: hole * 2)),
                     with: .color(ink), lineWidth: 0.6)

        // The drop: a point above a round belly.
        let s = w * 0.46
        let belly = CGPoint(x: 0, y: h * 0.14)
        var drop = Path()
        drop.move(to: CGPoint(x: 0, y: belly.y - s * 0.75))
        drop.addQuadCurve(to: CGPoint(x: s * 0.33, y: belly.y),
                          control: CGPoint(x: s * 0.3, y: belly.y - s * 0.3))
        drop.addArc(center: belly, radius: s * 0.33, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        drop.addQuadCurve(to: CGPoint(x: 0, y: belly.y - s * 0.75),
                          control: CGPoint(x: -s * 0.3, y: belly.y - s * 0.3))
        drop.closeSubpath()
        local.fill(drop, with: .color(TreeCanvasVitality.tagDrop.color))
    }
}

// MARK: - Previews

/// Lush, plain, ready, thirsty and resting, side by side. Lush and plain
/// are what the app draws (it stays plain from 48 h on); ready, thirsty and
/// resting are the look `GardenTreeLook.withersWhenThirsty` would add.
private enum TreeVitalityPreviewSamples {
    static let states: [(name: String, vitality: TreeVitality)] = [
        ("lush", TreeVitality(GardenTreeVisual.at(hoursSinceWater: 1, withers: false))),
        ("plain", TreeVitality(GardenTreeVisual.at(hoursSinceWater: 50, withers: false))),
        ("ready", TreeVitality(GardenTreeVisual.at(hoursSinceWater: 70, withers: true))),
        ("thirsty", TreeVitality(GardenTreeVisual.at(hoursSinceWater: 120, withers: true))),
        ("resting", TreeVitality(GardenTreeVisual.at(hoursSinceWater: 200, withers: true)))
    ]

    static func tree(_ species: GardenSpecies, _ vitality: TreeVitality, noteTag: Bool = false) -> some View {
        RelationshipTreeCanvas(
            stage: .fruiting,
            season: .summer,
            daysTogether: 400,
            memoryCount: 0,
            crownActive: false,
            style: TreeCanvasStyle(species: species, backdrop: .light, drawsGround: false,
                                   glow: .none, topologySeed: 7),
            vitality: vitality,
            clock: .external(time: 0, pose: .still),
            noteTag: noteTag ? TreeNoteTag(wateringId: "preview") : nil,
            onSelectNoteTag: noteTag ? {} : nil
        )
        .modifier(TreeCanvasPreviewFrame(width: 120, height: 120))
    }
}

#Preview("Thirst · lush to resting") {
    ScrollView([.horizontal, .vertical]) {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(GardenSpecies.allCases) { species in
                HStack(spacing: 8) {
                    ForEach(TreeVitalityPreviewSamples.states, id: \.name) { state in
                        VStack(spacing: 4) {
                            TreeVitalityPreviewSamples.tree(species, state.vitality)
                            Text(verbatim: "\(species.rawValue) · \(state.name)")
                                .font(.caption2)
                                .foregroundStyle(Brand.textSecondary)
                        }
                    }
                }
            }
        }
        .padding()
    }
    .background(LinearGradient(colors: [GardenRGB(0x6FB7EA).color, GardenRGB(0xD8EEF8).color],
                               startPoint: .top, endPoint: .bottom))
}

#Preview("Note tag · every stage") {
    ScrollView(.horizontal) {
        HStack(spacing: 8) {
            ForEach(TreeGrowthStage.allCases, id: \.self) { stage in
                RelationshipTreeCanvas(
                    stage: stage,
                    season: .summer,
                    daysTogether: stage.startDay + 20,
                    memoryCount: 0,
                    crownActive: false,
                    vitality: TreeVitality(GardenTreeVisual.at(hoursSinceWater: 3)),
                    clock: .external(time: 0, pose: .still),
                    noteTag: TreeNoteTag(wateringId: "preview"),
                    onSelectNoteTag: {}
                )
                .modifier(TreeCanvasPreviewFrame(width: 140, height: 140))
            }
        }
        .padding()
    }
    .background(Brand.backgroundTop)
}

#Preview("Revival · every 3 s") {
    TimelineView(.animation) { timeline in
        let now = timeline.date.timeIntervalSinceReferenceDate
        let watered = (now / 3).rounded(.down) * 3 + 0.5
        let vitality = TreeVitality(thirst: 0, wetness: 1, dew: 1, soilDryness: 0, lushness: 1,
                                    reviveFrom: 1, reviveStart: watered)
        HStack(spacing: 12) {
            ForEach([GardenSpecies.oak, .pine, .palm]) { species in
                RelationshipTreeCanvas(
                    stage: .blooming,
                    season: .spring,
                    daysTogether: 200,
                    memoryCount: 0,
                    crownActive: false,
                    style: TreeCanvasStyle(species: species, backdrop: .light, drawsGround: false,
                                           glow: .none, topologySeed: 11),
                    vitality: vitality,
                    clock: .external(time: now, pose: .live)
                )
                .modifier(TreeCanvasPreviewFrame(width: 150, height: 150))
            }
        }
        .padding()
    }
    .background(Brand.backgroundTop)
}
