//
//  TreeCanvasSpecies.swift
//  Coupley
//
//  Our Garden: the five species one painter draws (spec C5). Every species
//  keeps `TreeCanvasLayout`'s geometry (trunk, limbs, canopy centre and
//  radius), so letters, blossoms and their tap targets work on any species;
//  only the drawing changes.
//
//   - oak: today's tree, unchanged (the default).
//   - cherry ("Blossom"): a wider, flatter canopy, half its leaves
//     blossom-pink in spring and summer, 1.6× the stage's blossoms, bare
//     twigs in winter.
//   - banyan: a broad dome with aerial roots, green all year.
//   - pine: stacked tiers where the limbs are, pinecones for fruit.
//   - palm: a ringed, gently curving trunk, fronds, coconuts.
//
//  Main-actor isolated like `TreeCanvasPainter` (spec I6): it reads
//  `TreeGrowthStage` and `TreeSeason` members. Never mark it `nonisolated`.
//

import CoreGraphics
import Foundation
import SwiftUI

enum TreeCanvasSpecies {
    static let cherryPinkTop = GardenRGB(0xF9C5D5)
    static let cherryPinkBottom = GardenRGB(0xF4A6BD)
    static let cherryAutumnTop = GardenRGB(0xE79A5C)
    static let cherryAutumnBottom = GardenRGB(0xC9653A)
    static let pineTop = GardenRGB(0x3E7B5A)
    static let pineBottom = GardenRGB(0x2F6249)
    static let pineSnow = GardenRGB(0xEEF3F8)
    static let pinecone = GardenRGB(0x7A5233)
    static let pineconeScale = GardenRGB(0x5A3B22)
    static let palmLeafTop = GardenRGB(0x4E9A5A)
    static let palmLeafBottom = GardenRGB(0x3C7F47)
    static let palmRing = GardenRGB(0x8A6A4E)
    static let coconut = GardenRGB(0x6B4A2F)
    static let coconutLight = GardenRGB(0x8A6440)

    /// How much wider and taller the canopy ellipse is than today's oak
    /// (cherry 1.10 × 0.90, banyan 1.25 × 0.75). Pine and palm draw no
    /// ellipse; their foliage follows the layout's canopy radius.
    static func canopyScale(for species: GardenSpecies) -> CGSize {
        switch species {
        case .cherry: return CGSize(width: 1.10, height: 0.90)
        case .banyan: return CGSize(width: 1.25, height: 0.75)
        case .oak, .pine, .palm: return CGSize(width: 1, height: 1)
        }
    }

    /// The canopy's two colours (top → bottom of a leaf) for `season`.
    /// `snows` (TreeCanvasStyle.snows) marks a temperate winter, as opposed
    /// to the mild winter of a tree without a place.
    static func canopyColors(for species: GardenSpecies, season: TreeSeason, snows: Bool = false) -> (top: Color, bottom: Color) {
        switch species {
        case .oak:
            return season.canopyColors
        case .cherry:
            return season == .autumn ? (cherryAutumnTop.color, cherryAutumnBottom.color) : season.canopyColors
        case .banyan:
            // Always green: spring's fresh green, otherwise summer's. A
            // temperate (snowy) winter keeps the summer palette; a mild
            // winter darkens it by 10% (C5).
            switch season {
            case .spring:
                return season.canopyColors
            case .summer, .autumn:
                return TreeSeason.summer.canopyColors
            case .winter where snows:
                return TreeSeason.summer.canopyColors
            case .winter:
                let leaves = TreeSeason.summer.canopyColors
                return (leaves.top.mix(with: .black, by: 0.10, in: .device),
                        leaves.bottom.mix(with: .black, by: 0.10, in: .device))
            }
        case .pine:
            return (pineTop.color, pineBottom.color)
        case .palm:
            return (palmLeafTop.color, palmLeafBottom.color)
        }
    }

    /// The blossom pinks a cherry mixes into its leaves in spring and
    /// summer: half of them take these colours instead of the green (a 50%
    /// blend of the two colours read as khaki). Nil for every other tree.
    static func blossomLeafColors(for species: GardenSpecies, season: TreeSeason) -> (top: Color, bottom: Color)? {
        guard species == .cherry, season == .spring || season == .summer else { return nil }
        return (cherryPinkTop.color, cherryPinkBottom.color)
    }

    /// A share of the stage's canopy: a cherry stands nearly bare in
    /// winter (× 0.4), its twigs showing.
    static func fullnessFactor(for species: GardenSpecies, season: TreeSeason) -> CGFloat {
        species == .cherry && season == .winter ? 0.4 : 1
    }

    /// The stage's decorative blossoms: 1.6× on a cherry, none on a pine or
    /// a palm (their stage shows in tiers or fronds and in cones or
    /// coconuts).
    static func blossomCount(for species: GardenSpecies, stage: TreeGrowthStage) -> Int {
        switch species {
        case .oak, .banyan: return stage.blossomCount
        case .cherry:       return Int((Double(stage.blossomCount) * 1.6).rounded())
        case .pine, .palm:  return 0
        }
    }

    /// A banyan's aerial roots: 8 to 14 once it has a few limbs to hang
    /// them from (a sapling on), more as it grows.
    static func aerialRootCount(for stage: TreeGrowthStage) -> Int {
        stage >= .sapling ? min(14, max(8, stage.branchCount + 3)) : 0
    }
}

// MARK: - Geometry

extension TreeCanvasLayout {

    /// One tier of a pine: a triangle from `apex` to its two lower
    /// corners, whose bottom edge scallops between the corners.
    struct PineTier {
        let apex: CGPoint
        let left: CGPoint
        let right: CGPoint
        let halfWidth: CGFloat
        let height: CGFloat

        /// The tier's outline: concave flanks and a scalloped hem.
        var path: Path {
            var path = Path()
            path.move(to: apex)
            path.addQuadCurve(to: left, control: CGPoint(x: apex.x - halfWidth * 0.42, y: apex.y + height * 0.62))
            let scallops = 4
            for k in 1...scallops {
                let t = CGFloat(k) / CGFloat(scallops)
                let from = CGFloat(k - 1) / CGFloat(scallops)
                let to = CGPoint(x: left.x + (right.x - left.x) * t, y: left.y + (right.y - left.y) * t)
                let mid = (from + t) / 2
                let control = CGPoint(x: left.x + (right.x - left.x) * mid,
                                      y: left.y + (right.y - left.y) * mid - height * 0.16)
                path.addQuadCurve(to: to, control: control)
            }
            path.addQuadCurve(to: apex, control: CGPoint(x: apex.x + halfWidth * 0.42, y: apex.y + height * 0.62))
            path.closeSubpath()
            return path
        }

        /// A point inside the tier, `down` (0 at the apex, 1 at the hem) and
        /// `across` (−1 left … 1 right) of the width there.
        func point(down: CGFloat, across: CGFloat) -> CGPoint {
            let y = apex.y + (left.y + right.y - 2 * apex.y) / 2 * down
            return CGPoint(x: apex.x + across * halfWidth * down * 0.8, y: y)
        }
    }

    /// A pine's `max(1, limbs / 2)` tiers, bottom first, stacked from below
    /// the canopy to its top, each overlapping the next. The tops sway
    /// most; thirst sags the corners; a lush tree is a little fuller.
    func pineTiers(motion: TreeCanvasMotion, droop: Double, lushness: Double) -> [PineTier] {
        let count = max(1, branches.count / 2)
        let topY = canopyCenter.y - canopyRadius * 1.10
        let bottomY = canopyCenter.y + canopyRadius * 0.85
        let step = (bottomY - topY) / CGFloat(count + 1)
        let fuller = 1 + 0.04 * CGFloat(lushness)
        let sway = CGFloat(motion.wave(0.35)) * unit * 0.006
        return (0..<count).map { k -> PineTier in
            let rise = count == 1 ? 1 : CGFloat(k) / CGFloat(count - 1)
            let taper = count == 1 ? 0.85 : 1 - 0.62 * rise
            let halfWidth = canopyRadius * 0.95 * taper * fuller
            let baseY = bottomY - CGFloat(k) * step
            let lean = sway * CGFloat(k + 1) / CGFloat(count)
            let sag = halfWidth * 0.10 * CGFloat(droop)
            return PineTier(apex: CGPoint(x: midX + lean, y: baseY - step * 2),
                            left: CGPoint(x: midX - halfWidth + lean * 0.5, y: baseY + sag),
                            right: CGPoint(x: midX + halfWidth + lean * 0.5, y: baseY + sag),
                            halfWidth: halfWidth,
                            height: step * 2)
        }
    }

    /// One palm frond: a quadratic arc from the crown.
    struct PalmFrond {
        let start: CGPoint
        let control: CGPoint
        let end: CGPoint
        let length: CGFloat

        func point(at t: CGFloat) -> CGPoint {
            let mt = 1 - t
            return CGPoint(x: mt * mt * start.x + 2 * mt * t * control.x + t * t * end.x,
                           y: mt * mt * start.y + 2 * mt * t * control.y + t * t * end.y)
        }

        /// The unit direction of the arc at `t`.
        func direction(at t: CGFloat) -> CGVector {
            let dx = 2 * (1 - t) * (control.x - start.x) + 2 * t * (end.x - control.x)
            let dy = 2 * (1 - t) * (control.y - start.y) + 2 * t * (end.y - control.y)
            let length = max(0.0001, hypot(dx, dy))
            return CGVector(dx: dx / length, dy: dy / length)
        }
    }

    /// How far a palm's crown has leaned in the breeze.
    func palmLean(_ motion: TreeCanvasMotion) -> CGFloat {
        CGFloat(motion.wave(0.3)) * unit * 0.008
    }

    /// The top of a palm's trunk, where its fronds start.
    func palmCrown(_ motion: TreeCanvasMotion) -> CGPoint {
        CGPoint(x: midX + palmLean(motion), y: groundY - trunkHeight)
    }

    /// A palm's `max(3, limbs)` fronds, fanned from the lower left over the
    /// top to the lower right (the last is the lowest on the right). Each
    /// arches up and falls; thirst lets them hang lower.
    func palmFronds(motion: TreeCanvasMotion, droop: Double) -> [PalmFrond] {
        let count = max(3, branches.count)
        let crown = palmCrown(motion)
        let reach = max(canopyRadius * 1.05, unit * 0.07)
        let d = CGFloat(droop)
        return (0..<count).map { i -> PalmFrond in
            var rng = TreeCanvasRNG(seed: UInt64(i) &* 131 &+ 17)
            let fan = count == 1 ? 0.5 : Double(i) / Double(count - 1)
            let angle = Double.pi * (0.88 + 1.24 * fan)
            let length = reach * CGFloat(0.88 + rng.nextDouble() * 0.24)
            let direction = CGVector(dx: CGFloat(cos(angle)), dy: CGFloat(sin(angle)))
            let flutter = CGSize(width: CGFloat(motion.wave(0.5, Double(i) * 1.3)) * unit * 0.006,
                                 height: CGFloat(motion.wave(0.55, Double(i))) * unit * 0.004)
            let end = CGPoint(x: crown.x + direction.dx * length + flutter.width,
                              y: crown.y + direction.dy * length + length * (0.30 + 0.25 * d) + flutter.height)
            let control = CGPoint(x: crown.x + direction.dx * length * 0.55,
                                  y: crown.y + direction.dy * length * 0.55 - length * 0.22 * (1 - 0.5 * d))
            return PalmFrond(start: crown, control: control, end: end, length: length)
        }
    }
}

// MARK: - Drawing

extension TreeCanvasPainter {

    /// A cherry in winter: forked twigs at every limb's tip and a side twig
    /// on every limb, so the bare tree reads as a tree.
    func drawBareTwigs(_ context: GraphicsContext, _ layout: TreeCanvasLayout, _ palette: TreeCanvasPalette,
                       _ motion: TreeCanvasMotion, _ care: TreeCanvasCare) {
        guard !layout.branches.isEmpty else { return }
        var twigs = Path()
        for branch in layout.branches {
            let sway = layout.tipOffset(of: branch, motion: motion, droop: care.droop)
            let direction: CGFloat = branch.isLeft ? -1 : 1
            let reach = branch.reach
            let tip = branch.point(at: 1, tipOffset: sway)
            twigs.move(to: tip)
            twigs.addLine(to: CGPoint(x: tip.x + direction * reach * 0.16, y: tip.y - reach * 0.18))
            twigs.move(to: tip)
            twigs.addLine(to: CGPoint(x: tip.x + direction * reach * 0.05, y: tip.y - reach * 0.26))
            let mid = branch.point(at: 0.7, tipOffset: sway)
            twigs.move(to: mid)
            twigs.addQuadCurve(to: CGPoint(x: mid.x + direction * reach * 0.2, y: mid.y - reach * 0.22),
                               control: CGPoint(x: mid.x + direction * reach * 0.06, y: mid.y - reach * 0.04))
        }
        context.stroke(twigs, with: .color(palette.twig),
                       style: StrokeStyle(lineWidth: max(0.6, layout.unit * 0.005), lineCap: .round))
    }

    /// A banyan's aerial roots: hairlines hanging from the outer half of
    /// its limbs to 70–90% of the way to the ground, swaying ±1.5pt at
    /// 0.3 Hz. Drawn before the canopy, which covers where they start.
    func drawAerialRoots(_ context: GraphicsContext, _ layout: TreeCanvasLayout, _ palette: TreeCanvasPalette,
                         _ motion: TreeCanvasMotion, _ care: TreeCanvasCare) {
        let count = TreeCanvasSpecies.aerialRootCount(for: stage)
        guard count > 0, !layout.branches.isEmpty else { return }
        var rng = TreeCanvasRNG(seed: topologySeed &* 67 &+ 19)
        var roots = Path()
        for i in 0..<count {
            let branch = layout.branches[i % layout.branches.count]
            let along = CGFloat(0.5 + rng.nextDouble() * 0.45)
            let share = CGFloat(0.7 + rng.nextDouble() * 0.2)
            let phase = rng.nextDouble() * .pi * 2
            let start = branch.point(at: along, tipOffset: layout.tipOffset(of: branch, motion: motion, droop: care.droop))
            let length = max(0, layout.groundY - start.y) * share
            let sway = CGFloat(motion.wave(2 * .pi * 0.3, phase)) * 1.5
            roots.move(to: start)
            roots.addQuadCurve(to: CGPoint(x: start.x + sway, y: start.y + length),
                               control: CGPoint(x: start.x + sway * 0.2, y: start.y + length * 0.5))
        }
        context.stroke(roots, with: .color(palette.twig.opacity(0.7)), lineWidth: 1)
    }

    /// A pine: its tiers (green every season, a snow edge on each when the
    /// scene has snow), then pinecones hanging under their hems.
    func drawPine(_ context: GraphicsContext, _ layout: TreeCanvasLayout,
                  _ motion: TreeCanvasMotion, _ care: TreeCanvasCare) {
        let tiers = layout.pineTiers(motion: motion, droop: care.droop, lushness: care.lushness)
        let tint = care.leafTint(TreeCanvasSpecies.canopyColors(for: .pine, season: season), in: context.environment)
        let sheen = care.sheen(atHeight: layout.canopyRadius * 0.85, radius: layout.canopyRadius)
        let top = sheen > 0 ? tint.top.mix(with: .white, by: sheen, in: .device) : tint.top
        let snowy = season == .winter && style.snows
        let snowWidth: CGFloat = 1.5

        for tier in tiers {
            let path = tier.path
            let hemY = (tier.left.y + tier.right.y) / 2
            context.fill(path, with: .linearGradient(
                Gradient(colors: [top, tint.bottom]),
                startPoint: tier.apex,
                endPoint: CGPoint(x: tier.apex.x, y: hemY)
            ))
            // The right half in shade, for volume.
            var shade = Path()
            shade.move(to: tier.apex)
            shade.addQuadCurve(to: tier.right, control: CGPoint(x: tier.apex.x + tier.halfWidth * 0.42,
                                                                y: tier.apex.y + tier.height * 0.62))
            shade.addLine(to: CGPoint(x: tier.apex.x, y: hemY))
            shade.closeSubpath()
            context.fill(shade, with: .color(Color.black.opacity(0.08)))

            if snowy {
                var snow = Path()
                for corner in [tier.left, tier.right] {
                    let shoulder = CGPoint(x: tier.apex.x + (corner.x - tier.apex.x) * 0.45,
                                           y: tier.apex.y + (corner.y - tier.apex.y) * 0.45)
                    snow.move(to: shoulder)
                    snow.addLine(to: corner)
                }
                context.stroke(snow, with: .color(TreeCanvasSpecies.pineSnow.color),
                               style: StrokeStyle(lineWidth: snowWidth, lineCap: .round))
            }
        }
        drawPinecones(context, layout, tiers, motion)
    }

    /// The stage's fruit as pinecones under the tiers' hems.
    private func drawPinecones(_ context: GraphicsContext, _ layout: TreeCanvasLayout,
                               _ tiers: [TreeCanvasLayout.PineTier], _ motion: TreeCanvasMotion) {
        let count = stage.fruitCount
        guard count > 0, !tiers.isEmpty else { return }
        let unit = layout.unit
        let width = unit * 0.024
        let height = unit * 0.036
        var rng = TreeCanvasRNG(seed: topologySeed &* 53 &+ 41)
        var cones = Path()
        var scales = Path()
        for i in 0..<count {
            let tier = tiers[min(tiers.count - 1, Int(rng.nextDouble() * Double(tiers.count)))]
            let side: CGFloat = rng.nextDouble() < 0.5 ? -1 : 1
            let across = CGFloat(0.3 + rng.nextDouble() * 0.45)
            let corner = side < 0 ? tier.left : tier.right
            let swayY = CGFloat(motion.wave(0.4, Double(i))) * unit * 0.003
            let x = tier.apex.x + (corner.x - tier.apex.x) * across
            let y = corner.y - tier.height * 0.06 + swayY
            let rect = CGRect(x: x - width / 2, y: y, width: width, height: height)
            cones.addEllipse(in: rect)
            for k in 1...2 {
                let lineY = rect.minY + height * CGFloat(k) / 3
                scales.move(to: CGPoint(x: rect.minX + width * 0.2, y: lineY))
                scales.addLine(to: CGPoint(x: rect.maxX - width * 0.2, y: lineY))
            }
        }
        context.fill(cones, with: .color(TreeCanvasSpecies.pinecone.color))
        context.stroke(scales, with: .color(TreeCanvasSpecies.pineconeScale.color), lineWidth: max(0.5, unit * 0.003))
    }

    /// A palm: a slim trunk with ring marks and a gentle S-curve back to
    /// the middle at the top, its fronds (the most upright behind), and
    /// coconuts under the crown.
    func drawPalm(_ context: GraphicsContext, _ layout: TreeCanvasLayout, _ palette: TreeCanvasPalette,
                  _ motion: TreeCanvasMotion, _ care: TreeCanvasCare) {
        let unit = layout.unit
        let height = layout.trunkHeight
        let lean = layout.palmLean(motion)
        let curve = height * 0.06
        let baseWidth = max(unit * 0.02, layout.trunkWidth * 0.62)
        func spine(_ t: CGFloat) -> CGPoint {
            CGPoint(x: layout.midX + CGFloat(sin(2 * .pi * Double(t))) * curve + lean * t * t,
                    y: layout.groundY - height * t)
        }
        func halfWidth(_ t: CGFloat) -> CGFloat { baseWidth * (1 - 0.45 * t) / 2 }

        let steps = 12
        var trunk = Path()
        for k in 0...steps {
            let t = CGFloat(k) / CGFloat(steps)
            let p = spine(t)
            let point = CGPoint(x: p.x - halfWidth(t), y: p.y)
            if k == 0 { trunk.move(to: point) } else { trunk.addLine(to: point) }
        }
        for k in stride(from: steps, through: 0, by: -1) {
            let t = CGFloat(k) / CGFloat(steps)
            let p = spine(t)
            trunk.addLine(to: CGPoint(x: p.x + halfWidth(t), y: p.y))
        }
        trunk.closeSubpath()
        context.fill(trunk, with: .linearGradient(
            Gradient(colors: [palette.trunkBase, palette.trunkTop]),
            startPoint: layout.trunkBase,
            endPoint: layout.palmCrown(motion)
        ))

        let ringStep = unit * 0.06
        if height > ringStep {
            var rings = Path()
            var y = ringStep
            while y < height {
                let t = y / height
                let p = spine(t)
                let w = halfWidth(t)
                rings.move(to: CGPoint(x: p.x - w, y: p.y))
                rings.addQuadCurve(to: CGPoint(x: p.x + w, y: p.y), control: CGPoint(x: p.x, y: p.y + w * 0.5))
                y += ringStep
            }
            context.stroke(rings, with: .color(TreeCanvasSpecies.palmRing.color), lineWidth: max(0.6, unit * 0.004))
        }

        drawPalmFronds(context, layout, motion, care)
        drawCoconuts(context, layout, motion)
    }

    /// Each frond: its midrib and 10 leaflets a side, angled toward the tip
    /// and hanging lower with thirst, as one stroke from crown to tip.
    private func drawPalmFronds(_ context: GraphicsContext, _ layout: TreeCanvasLayout,
                                _ motion: TreeCanvasMotion, _ care: TreeCanvasCare) {
        let unit = layout.unit
        let fronds = layout.palmFronds(motion: motion, droop: care.droop)
            .sorted { $0.end.y < $1.end.y }
        let tint = care.leafTint(TreeCanvasSpecies.canopyColors(for: .palm, season: season), in: context.environment)
        let hang = 0.9 + 0.5 * CGFloat(care.droop)
        let longer = 1 + 0.10 * CGFloat(care.lushness)
        let leafletWidth = max(1.1, unit * 0.011)
        let ribWidth = max(0.9, unit * 0.007)

        for (i, frond) in fronds.enumerated() {
            var leaflets = Path()
            for j in 0..<10 {
                let t = 0.16 + 0.082 * CGFloat(j)
                let base = frond.point(at: t)
                let along = frond.direction(at: t)
                let length = frond.length * 0.24 * (1 - 0.5 * t) * longer
                let flutter = CGFloat(motion.wave(1.4, Double(i * 10 + j))) * unit * 0.002
                for side: CGFloat in [-1, 1] {
                    var dx = -along.dy * side + along.dx * 0.55
                    var dy = along.dx * side + along.dy * 0.55 + hang
                    let norm = max(0.0001, hypot(dx, dy))
                    dx /= norm
                    dy /= norm
                    leaflets.move(to: base)
                    leaflets.addLine(to: CGPoint(x: base.x + dx * length + flutter, y: base.y + dy * length))
                }
            }
            let sheen = care.sheen(atHeight: frond.start.y - frond.end.y, radius: layout.canopyRadius)
            let top = sheen > 0 ? tint.top.mix(with: .white, by: sheen, in: .device) : tint.top
            let shading = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [top, tint.bottom]), startPoint: frond.start, endPoint: frond.end
            )
            context.stroke(leaflets, with: shading,
                           style: StrokeStyle(lineWidth: leafletWidth, lineCap: .round))
            var rib = Path()
            rib.move(to: frond.start)
            rib.addQuadCurve(to: frond.end, control: frond.control)
            context.stroke(rib, with: .color(tint.bottom),
                           style: StrokeStyle(lineWidth: ribWidth, lineCap: .round))
        }
    }

    /// The stage's fruit as coconuts clustered under the crown.
    private func drawCoconuts(_ context: GraphicsContext, _ layout: TreeCanvasLayout, _ motion: TreeCanvasMotion) {
        let count = stage.fruitCount
        guard count > 0 else { return }
        let unit = layout.unit
        let crown = layout.palmCrown(motion)
        let radius = unit * 0.016
        var rng = TreeCanvasRNG(seed: topologySeed &* 53 &+ 41)
        for _ in 0..<count {
            let angle = Double.pi * (0.15 + rng.nextDouble() * 0.7)
            let distance = unit * CGFloat(0.012 + rng.nextDouble() * 0.02)
            let center = CGPoint(x: crown.x + CGFloat(cos(angle)) * distance * 1.4,
                                 y: crown.y + CGFloat(sin(angle)) * distance)
            let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: rect), with: .radialGradient(
                Gradient(colors: [TreeCanvasSpecies.coconutLight.color, TreeCanvasSpecies.coconut.color]),
                center: CGPoint(x: rect.midX - radius * 0.3, y: rect.midY - radius * 0.3),
                startRadius: 0, endRadius: radius * 1.2
            ))
        }
    }

    /// `count` seeded points on the foliage, where it is drawn this frame
    /// (drooped and swaying): dew sits on them.
    func foliagePoints(count: Int, seed: UInt64, layout: TreeCanvasLayout,
                       motion: TreeCanvasMotion, care: TreeCanvasCare) -> [CGPoint] {
        var rng = TreeCanvasRNG(seed: seed)
        switch style.species {
        case .oak, .cherry, .banyan:
            let scale = TreeCanvasSpecies.canopyScale(for: style.species)
            let center = layout.canopyCenter
            let radius = layout.canopyRadius
            return (0..<count).map { _ in
                let angle = rng.nextDouble() * .pi * 2
                let distance = CGFloat(0.15 + rng.nextDouble() * 0.75) * radius
                return CGPoint(x: center.x + CGFloat(cos(angle)) * distance * scale.width,
                               y: center.y + CGFloat(sin(angle)) * distance * 0.85 * scale.height
                                + care.leafDrop(distance: distance, radius: radius, unit: layout.unit))
            }
        case .pine:
            let tiers = layout.pineTiers(motion: motion, droop: care.droop, lushness: care.lushness)
            guard !tiers.isEmpty else { return [] }
            return (0..<count).map { _ in
                let tier = tiers[min(tiers.count - 1, Int(rng.nextDouble() * Double(tiers.count)))]
                let down = CGFloat(0.35 + rng.nextDouble() * 0.55)
                return tier.point(down: down, across: CGFloat(rng.nextDouble() * 2 - 1))
            }
        case .palm:
            let fronds = layout.palmFronds(motion: motion, droop: care.droop)
            guard !fronds.isEmpty else { return [] }
            return (0..<count).map { _ in
                let frond = fronds[min(fronds.count - 1, Int(rng.nextDouble() * Double(fronds.count)))]
                return frond.point(at: CGFloat(0.3 + rng.nextDouble() * 0.6))
            }
        }
    }
}

// MARK: - Previews

private enum TreeSpeciesPreviewSamples {
    static func tree(_ species: GardenSpecies, _ stage: TreeGrowthStage, season: TreeSeason = .summer,
                     backdrop: TreeBackdrop = .automatic, letters: Bool = false) -> some View {
        RelationshipTreeCanvas(
            stage: stage,
            season: season,
            daysTogether: stage.startDay + 20,
            memoryCount: 0,
            crownActive: false,
            ornaments: letters ? TreeCanvasPreviewSamples.letters : [],
            onSelectOrnament: letters ? { _ in } : nil,
            style: TreeCanvasStyle(species: species, backdrop: backdrop, drawsGround: backdrop == .automatic,
                                   glow: backdrop == .dark ? .dusk(intensity: 1) : .always, topologySeed: 42,
                                   snows: season == .winter),
            clock: .external(time: 0, pose: .still)
        )
    }
}

#Preview("Species · every stage") {
    ScrollView([.horizontal, .vertical]) {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(GardenSpecies.allCases) { species in
                VStack(alignment: .leading, spacing: 4) {
                    Text(species.displayName)
                        .font(JourneyFont.label)
                        .foregroundStyle(Brand.textSecondary)
                    HStack(alignment: .bottom, spacing: 8) {
                        ForEach(TreeGrowthStage.allCases, id: \.self) { stage in
                            TreeSpeciesPreviewSamples.tree(species, stage)
                                .modifier(TreeCanvasPreviewFrame(width: 120, height: 120))
                        }
                    }
                }
            }
        }
        .padding()
    }
    .background(Brand.backgroundTop)
}

#Preview("Species · seasons") {
    ScrollView {
        VStack(spacing: 8) {
            ForEach(GardenSpecies.allCases) { species in
                HStack(spacing: 8) {
                    ForEach([TreeSeason.spring, .summer, .autumn, .winter], id: \.self) { season in
                        TreeSpeciesPreviewSamples.tree(species, .fruiting, season: season)
                            .modifier(TreeCanvasPreviewFrame(width: 88, height: 88))
                    }
                }
            }
        }
        .padding()
    }
    .background(Brand.backgroundTop)
}

#Preview("Species · night sky, letters") {
    HStack(spacing: 8) {
        ForEach(GardenSpecies.ourTreeChoices) { species in
            TreeSpeciesPreviewSamples.tree(species, .mature, backdrop: .dark, letters: true)
                .modifier(TreeCanvasPreviewFrame(width: 150, height: 150))
        }
    }
    .padding()
    .background(LinearGradient(colors: [GardenRGB(0x0B1430).color, GardenRGB(0x1F3157).color],
                               startPoint: .top, endPoint: .bottom))
}
