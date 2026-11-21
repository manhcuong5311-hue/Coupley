//
//  RiceTerracesScene.swift
//  Coupley
//
//  Our Garden, P6 (Scenes II): Rice Terraces (C4 scene 6). Three misty
//  ridgelines, six terraces stepping down the hillside whose fill IS the
//  season (flooded in spring, green in summer, harvest gold in autumn,
//  stubble in the dry season), a stilt house with cooking smoke, and a
//  terrace-edge knoll with a short bamboo fence.
//
//  Shared helpers (ScenesIIBand, ScenesII) live in LanternTownScene.swift.
//

import CoreGraphics
import Foundation
import SwiftUI

nonisolated struct RiceTerracesScene: GardenScenePainting {
    init() {}

    var scene: GardenSceneID { .riceTerraces }

    // MARK: Layout (band fractions, C4)

    private static let apex = CGPoint(x: 0.62, y: 0.84)
    private static let knollHalfWidth: CGFloat = 0.30
    private static let terraceCount = 6
    /// The darker bund along the front lip of each terrace.
    private static let bund: CGFloat = 0.012
    /// Cooking smoke seeps out of the stilt house's thatch at its ridge.
    private static let smokeOrigin = CGPoint(x: 0.205, y: 0.47)
    /// Scene life besides the sky: three smoke puffs, the mist band and six
    /// glints on flooded terraces.
    private static let particleBudget = ScenesII.particleBudget(sceneLife: 10)

    private static var staticSeed: UInt64 { GardenSceneStyle.staticSeed(for: .riceTerraces) }

    private struct Ridge {
        let base: CGFloat
        let amplitude: CGFloat
        let day: UInt32
        let night: UInt32
        let frequencies: (CGFloat, CGFloat)
        let phases: (CGFloat, CGFloat)
    }

    /// Three ridgelines (bases 0.40, 0.48, 0.56), each two seeded sines.
    private static let ridges: [Ridge] = {
        var rng = GardenSceneRandom(seed: GardenSceneKit.seed(GardenSceneStyle.staticSeed(for: .riceTerraces), 0x41D6))
        let specs: [(CGFloat, CGFloat, UInt32, UInt32)] = [
            (0.40, 0.08, 0x7E9AA6, 0x1B2733), (0.48, 0.065, 0x92AEB4, 0x22303D), (0.56, 0.05, 0xA9C3C3, 0x2A3A46)
        ]
        return specs.map { base, amplitude, day, night in
            Ridge(base: base, amplitude: amplitude, day: day, night: night,
                  frequencies: (rng.next(0.9...1.5), rng.next(2.2...3.4)),
                  phases: (rng.next(0...1), rng.next(0...1)))
        }
    }()

    /// Each terrace edge's seeded wobble phase.
    private static let edgePhases: [CGFloat] = {
        var rng = GardenSceneRandom(seed: GardenSceneKit.seed(GardenSceneStyle.staticSeed(for: .riceTerraces), 0x7E44))
        return (0..<terraceCount).map { _ in rng.next(0...(2 * .pi)) }
    }()

    /// The top edge of terrace `index` at band x: a concave curve dipping
    /// toward the valley on the left third, with a gentle seeded wobble.
    /// Terraces step from 0.56 down to 0.86.
    private static func edge(_ index: Int, at x: CGFloat) -> CGFloat {
        let base = 0.56 + CGFloat(index) * 0.05
        let sag = 0.02 + 0.01 * CGFloat(index)
        let dip = CGFloat(exp(-pow(Double((x - 0.34) / 0.38), 2)))
        return base + sag * dip + 0.004 * sin(x * 9 + edgePhases[index])
    }

    // MARK: GardenScenePainting

    func drawLayer(_ layer: GardenBackdropLayer, in context: GraphicsContext, size: CGSize, style: GardenSceneStyle) {
        let band = ScenesIIBand(size, layer: layer)
        switch layer {
        case .far:   Self.drawFar(in: context, band: band, style: style)
        case .near:  Self.drawNear(in: context, band: band, style: style)
        case .front: Self.drawFront(in: context, band: band, style: style)
        }
    }

    func drawAmbient(_ pass: GardenAmbientPass, in context: GraphicsContext, size: CGSize, state: GardenAmbientState) {
        switch pass {
        case .sky:
            ScenesII.drawSky(in: context, size: size, state: state)
        case .behind:
            let band = ScenesIIBand(size)
            ScenesII.drawSmoke(in: context, band: band, origin: Self.smokeOrigin, clock: GardenSceneKit.motionTime(state),
                               seed: state.seed, color: GardenSceneKit.blend(0xF2F2F0, 0x8C95A8, darkness: state.sky.darkness),
                               opacity: 0.4)
            Self.drawMist(in: context, band: band, state: state)
        case .front:
            if state.season == .spring {
                Self.drawGlints(in: context, band: ScenesIIBand(size), state: state)
            }
            GardenSceneKit.drawSeasonParticles(in: context, size: size, state: state, maxCount: Self.particleBudget)
        }
    }

    /// Glints run down the bunds, terrace to terrace.
    func drawWateringAccent(in context: GraphicsContext, size: CGSize, state: GardenAmbientState, progress: Double) {
        let band = ScenesIIBand(size)
        let p = min(1, max(0, progress))
        for index in 0..<Self.terraceCount {
            let u = (p - Double(index) * 0.11) / 0.4
            guard u > 0, u < 1 else { continue }
            let x = 0.04 + 0.46 * CGFloat(u)
            let center = band.point(x, Self.edge(index, at: x) + Self.bund * 0.5)
            let opacity = 0.85 * sin(.pi * u)
            GardenSceneKit.drawGlow(in: context, center: center, radius: band.pt(7), color: GardenRGB(0xFFFFFF), opacity: opacity * 0.5)
            let glint = CGRect(x: center.x - band.pt(5), y: center.y - band.pt(0.8), width: band.pt(10), height: band.pt(1.6))
            context.fill(Path(roundedRect: glint, cornerRadius: band.pt(0.8)), with: .color(Color.white.opacity(opacity)))
        }
    }

    // MARK: Far: misty ridgelines

    private static func drawFar(in context: GraphicsContext, band: ScenesIIBand, style: GardenSceneStyle) {
        let variant = style.variant
        let mist = GardenSceneKit.rgb(0xFFFFFF, 0x8FA0B8, variant)
        let mistOpacity = variant == .day ? 0.25 : 0.12
        for (index, ridge) in ridges.enumerated() {
            let path = ridgePath(ridge, band: band, bottom: 0.68)
            let rock = ScenesII.distant(GardenSceneKit.rgb(ridge.day, ridge.night, variant), style, amount: 0.5)
            if style.season.hasSnow {
                let snow = ScenesII.snowTop(variant)
                context.fill(path, with: .linearGradient(
                    Gradient(stops: [Gradient.Stop(color: snow.color, location: 0), Gradient.Stop(color: snow.color, location: 0.25),
                                     Gradient.Stop(color: rock.color, location: 0.55), Gradient.Stop(color: rock.color, location: 1)]),
                    startPoint: CGPoint(x: 0, y: band.y(ridge.base - ridge.amplitude)),
                    endPoint: CGPoint(x: 0, y: band.y(ridge.base))))
            } else {
                context.fill(path, with: .color(rock.color))
            }
            // A white mist strip hugging this ridge's foot, between it and the next.
            guard index < ridges.count - 1 else { continue }
            let strip = band.rect(band.minX, ridge.base - 0.04, band.maxX, ridge.base + 0.015)
            context.fill(Path(strip), with: .linearGradient(
                Gradient(stops: [Gradient.Stop(color: mist.color.opacity(0), location: 0),
                                 Gradient.Stop(color: mist.color.opacity(mistOpacity), location: 0.6),
                                 Gradient.Stop(color: mist.color.opacity(0), location: 1)]),
                startPoint: CGPoint(x: 0, y: strip.minY), endPoint: CGPoint(x: 0, y: strip.maxY)))
        }
    }

    /// A ridge sampled every 8 pt across the canvas, closed down to `bottom`.
    private static func ridgePath(_ ridge: Ridge, band: ScenesIIBand, bottom: CGFloat) -> Path {
        func height(at x: CGFloat) -> CGFloat {
            let wave = 0.62 * sin(2 * .pi * (ridge.frequencies.0 * x + ridge.phases.0))
                + 0.38 * sin(2 * .pi * (ridge.frequencies.1 * x + ridge.phases.1))
            return ridge.base - ridge.amplitude * (0.5 + 0.5 * wave)
        }
        var path = Path()
        path.move(to: band.point(band.minX, bottom))
        let step = 8 / max(1, band.width)
        var x = band.minX
        while true {
            path.addLine(to: band.point(x, height(at: x)))
            if x >= band.maxX { break }
            x = min(band.maxX, x + step)
        }
        path.addLine(to: band.point(band.maxX, bottom))
        path.closeSubpath()
        return path
    }

    // MARK: Near: terraces, stilt house, knoll, fence

    private static func drawNear(in context: GraphicsContext, band: ScenesIIBand, style: GardenSceneStyle) {
        let variant = style.variant
        let fill = paddyFill(style)
        let bundColor = bundFill(style)
        let lipLight = fill.top.mixed(with: GardenRGB(0xFFFFFF), 0.35).color.opacity(variant == .day ? 0.6 : 0.25)
        for index in 0..<terraceCount {
            let base = 0.56 + CGFloat(index) * 0.05
            context.fill(terraceRegion(index, band: band, inset: 0), with: .color(bundColor.color))
            let paddy = terraceRegion(index, band: band, inset: bund)
            ScenesII.fillGround(paddy, in: context, band: band, top: fill.top, bottom: fill.bottom,
                                from: base + bund, to: base + 0.05, style: style, seasonTint: false)
            drawRows(index, in: context, band: band, style: style, clip: paddy)
            // The paddy's back edge catches the light, so each step reads.
            context.stroke(edgeLine(index, band: band, inset: bund), with: .color(lipLight), lineWidth: band.pt(0.8))
        }
        drawStiltHouse(in: context, band: band, style: style)

        let knoll = GardenSceneKit.knoll(in: band.size, apex: apex, halfWidth: knollHalfWidth)
        fillKnoll(knoll, in: context, band: band, style: style)
        let rim = style.season.hasSnow ? ScenesII.snowTop(variant)
            : GardenSceneKit.ground(GardenSceneKit.rgb(0xA6D77A, 0x2C4630, variant), season: style.season, variant: variant)
        GardenSceneKit.drawRim(on: knoll, thickness: band.pt(1), color: rim, in: context)
        drawFence(in: context, band: band, style: style)
    }

    /// Terrace `index` from its top edge (pushed down by `inset`) to below
    /// the band: later terraces paint over its lower part.
    private static func terraceRegion(_ index: Int, band: ScenesIIBand, inset: CGFloat) -> Path {
        var path = edgeLine(index, band: band, inset: inset)
        path.addLine(to: band.point(1, 1.02))
        path.addLine(to: band.point(0, 1.02))
        path.closeSubpath()
        return path
    }

    /// Terrace `index`'s top edge, pushed down by `inset`, sampled every 6 pt.
    private static func edgeLine(_ index: Int, band: ScenesIIBand, inset: CGFloat) -> Path {
        var path = Path()
        let step = 6 / max(1, band.width)
        var x: CGFloat = 0
        path.move(to: band.point(x, edge(index, at: x) + inset))
        while x < 1 {
            x = min(1, x + step)
            path.addLine(to: band.point(x, edge(index, at: x) + inset))
        }
        return path
    }

    /// The paddies' fill is the season (C4): spring flooded with a mirror of
    /// the sky, summer green, autumn harvest gold, dry-season stubble; a
    /// temperate winter leaves them fallow under snow.
    private static func paddyFill(_ style: GardenSceneStyle) -> (top: GardenRGB, bottom: GardenRGB) {
        func tinted(_ hex: UInt32) -> GardenRGB {
            GardenSceneKit.ground(GardenRGB(hex), season: style.season, variant: style.variant)
        }
        if style.variant == .night {
            if style.season == .spring { return (GardenRGB(0x1F3157), GardenRGB(0x15213F)) }
            return (tinted(0x1E3324), tinted(0x1A2C1F))
        }
        switch style.season {
        case .spring:     return (GardenRGB(0xD8EEF8), GardenRGB(0x9CCBEA))
        case .summer:     return (GardenRGB(0x7DBF4E), GardenRGB(0x5FA23A))
        case .mildWinter: return (tinted(0x7DBF4E), tinted(0x5FA23A))
        case .autumn:     return (GardenRGB(0xE5C15A), GardenRGB(0xD4A83A))
        case .drySeason:  return (GardenRGB(0xB8A27A), GardenRGB(0xAA9468))
        case .winter:     return (GardenRGB(0xA08E6A), GardenRGB(0x8C7A58))
        }
    }

    private static func bundFill(_ style: GardenSceneStyle) -> GardenRGB {
        if style.season.hasSnow { return GardenSceneKit.rgb(0x7C6E56, 0x22221C, style.variant) }
        return GardenSceneKit.ground(GardenSceneKit.rgb(0x6C8A3F, 0x16271B, style.variant), season: style.season, variant: style.variant)
    }

    /// Two planting rows per terrace, following its curve: seedlings in the
    /// flooded spring paddies, row lines in summer and autumn, stubble in the
    /// dry season.
    private static func drawRows(_ index: Int, in context: GraphicsContext, band: ScenesIIBand, style: GardenSceneStyle, clip: Path) {
        let night = style.variant == .night
        let ink: GardenRGB
        let ticks: Bool
        switch style.season {
        case .spring:              ink = night ? GardenRGB(0x2F4A30) : GardenRGB(0x7DBF4E); ticks = true
        case .summer, .mildWinter: ink = night ? GardenRGB(0x152619) : GardenRGB(0x4E8F30); ticks = false
        case .autumn:              ink = night ? GardenRGB(0x2E2C1A) : GardenRGB(0xC99A30); ticks = false
        case .drySeason:           ink = night ? GardenRGB(0x2A281C) : GardenRGB(0x8C7856); ticks = true
        case .winter:              return
        }
        var rows = Path()
        let step = band.pt(5) / max(1, band.width)
        for offset: CGFloat in [0.02, 0.036] {
            var x: CGFloat = 0
            if ticks {
                while x <= 1 {
                    let root = band.point(x, edge(index, at: x) + bund + offset)
                    rows.move(to: root)
                    rows.addLine(to: CGPoint(x: root.x, y: root.y - band.pt(2.2)))
                    x += step
                }
            } else {
                rows.move(to: band.point(x, edge(index, at: x) + bund + offset))
                while x < 1 {
                    x = min(1, x + step)
                    rows.addLine(to: band.point(x, edge(index, at: x) + bund + offset))
                }
            }
        }
        var clipped = context
        clipped.clip(to: clip)
        clipped.stroke(rows, with: .color(ink.color.opacity(ticks ? 0.6 : 0.35)), lineWidth: band.pt(ticks ? 0.7 : 0.8))
    }

    /// A stilt house at (0.20, 0.60): thatched roof, plank walls, a ladder.
    private static func drawStiltHouse(in context: GraphicsContext, band: ScenesIIBand, style: GardenSceneStyle) {
        let variant = style.variant
        let wood = GardenSceneKit.rgb(0x8C6A4A, 0x2E241C, variant)
        let thatch = GardenSceneKit.rgb(0x6B4F35, 0x221A12, variant)
        let dark = GardenSceneKit.scaled(wood, 0.6)

        var stilts = Path()
        for x: CGFloat in [0.162, 0.188, 0.212, 0.238] {
            stilts.move(to: band.point(x, 0.60))
            stilts.addLine(to: band.point(x, 0.638))
        }
        context.stroke(stilts, with: .color(GardenSceneKit.scaled(wood, 0.75).color), lineWidth: band.pt(1.4))
        context.fill(Path(band.rect(0.152, 0.596, 0.248, 0.604)), with: .color(GardenSceneKit.scaled(wood, 0.8).color))

        let wall = band.rect(0.158, 0.538, 0.242, 0.598)
        context.fill(Path(wall), with: .color(wood.color))
        var planks = Path()
        var y = wall.minY + band.pt(2.5)
        while y < wall.maxY {
            planks.move(to: CGPoint(x: wall.minX, y: y))
            planks.addLine(to: CGPoint(x: wall.maxX, y: y))
            y += band.pt(2.5)
        }
        context.stroke(planks, with: .color(dark.color.opacity(0.3)), lineWidth: band.pt(0.5))
        context.fill(Path(band.rect(0.19, 0.556, 0.21, 0.598)), with: .color(dark.color))
        let window = band.rect(0.218, 0.556, 0.234, 0.572)
        if variant == .night {
            GardenSceneKit.drawGlow(in: context, center: CGPoint(x: window.midX, y: window.midY), radius: band.pt(8),
                                    color: GardenRGB(0xFFC46B), opacity: 0.4)
            context.fill(Path(window), with: .color(GardenRGB(0xFFC46B).color))
        } else {
            context.fill(Path(window), with: .color(dark.color))
        }

        // A ladder from the door down to the terrace.
        var ladder = Path()
        ladder.move(to: band.point(0.192, 0.598))
        ladder.addLine(to: band.point(0.186, 0.642))
        ladder.move(to: band.point(0.208, 0.598))
        ladder.addLine(to: band.point(0.214, 0.642))
        for rung: CGFloat in [0.61, 0.622, 0.634] {
            ladder.move(to: band.point(0.19, rung))
            ladder.addLine(to: band.point(0.21, rung))
        }
        context.stroke(ladder, with: .color(GardenSceneKit.scaled(wood, 0.85).color), lineWidth: band.pt(0.9))

        let eaveLeft = band.point(0.138, 0.548), ridgeLeft = band.point(0.18, 0.47)
        let ridgeRight = band.point(0.222, 0.47), eaveRight = band.point(0.262, 0.548)
        var roof = Path()
        roof.addLines([eaveLeft, ridgeLeft, ridgeRight, eaveRight])
        roof.closeSubpath()
        context.fill(roof, with: .color(thatch.color))
        var straw = Path()
        for step in 0...10 {
            let t = CGFloat(step) / 10
            straw.move(to: CGPoint(x: ridgeLeft.x + (ridgeRight.x - ridgeLeft.x) * t, y: ridgeLeft.y))
            straw.addLine(to: CGPoint(x: eaveLeft.x + (eaveRight.x - eaveLeft.x) * t, y: eaveLeft.y))
        }
        context.stroke(straw, with: .color(GardenSceneKit.scaled(thatch, 0.7).color.opacity(0.4)), lineWidth: band.pt(0.6))
        if style.season.hasSnow {
            GardenSceneKit.drawSnow(on: roof, depth: band.pt(2.4), in: context, variant: variant)
        }
    }

    private static func fillKnoll(_ path: Path, in context: GraphicsContext, band: ScenesIIBand, style: GardenSceneStyle) {
        ScenesII.fillGround(path, in: context, band: band,
                            top: GardenSceneKit.rgb(0x86C25A, 0x1E3324, style.variant),
                            bottom: GardenSceneKit.rgb(0x6AAE45, 0x18291D, style.variant),
                            from: apex.y, to: 1, style: style)
    }

    /// A short bamboo fence on the knoll's left slope, its feet in the grass.
    private static func drawFence(in context: GraphicsContext, band: ScenesIIBand, style: GardenSceneStyle) {
        let variant = style.variant
        let bamboo = GardenSceneKit.rgb(0xB5B060, 0x39391F, variant)
        let height = band.pt(12)
        var posts = Path(), rails = Path(), nodes = Path()
        var previous: CGPoint?
        var x: CGFloat = 0.375
        while x <= 0.50, let ground = GardenSceneKit.knollTop(atX: x, apex: apex, halfWidth: knollHalfWidth) {
            let base = band.point(x, ground + 0.012)
            posts.move(to: base)
            posts.addLine(to: CGPoint(x: base.x, y: base.y - height))
            nodes.move(to: CGPoint(x: base.x - band.pt(1), y: base.y - height / 2))
            nodes.addLine(to: CGPoint(x: base.x + band.pt(1), y: base.y - height / 2))
            if let previous {
                for level: CGFloat in [0.35, 0.75] {
                    rails.move(to: CGPoint(x: previous.x, y: previous.y - height * level))
                    rails.addLine(to: CGPoint(x: base.x, y: base.y - height * level))
                }
            }
            previous = base
            x += 0.021
        }
        let stroked = posts.strokedPath(StrokeStyle(lineWidth: band.pt(1.6), lineCap: .round))
        context.stroke(rails, with: .color(GardenSceneKit.scaled(bamboo, 0.85).color), lineWidth: band.pt(1))
        context.fill(stroked, with: .color(bamboo.color))
        context.stroke(nodes, with: .color(GardenSceneKit.scaled(bamboo, 0.6).color), lineWidth: band.pt(0.6))
        if style.season.hasSnow {
            GardenSceneKit.drawSnow(on: stroked, depth: band.pt(1.6), in: context, variant: variant)
        }
    }

    // MARK: Front: the knoll's lip, ground details, rice tufts

    private static func drawFront(in context: GraphicsContext, band: ScenesIIBand, style: GardenSceneStyle) {
        fillKnoll(GardenSceneKit.knoll(in: band.size, apex: ScenesII.lipApex(apex), halfWidth: knollHalfWidth),
                  in: context, band: band, style: style)
        // The flower or leaf dots go on the lip, the knoll's only ground the
        // terraces and the front layer leave in view.
        GardenSceneKit.drawGroundDetails(in: context, rect: band.rect(0.42, 0.945, 0.80, 0.99), season: style.season,
                                         variant: style.variant, seed: staticSeed)

        let night = style.variant == .night
        let blade: GardenRGB
        switch style.season {
        case .spring:              blade = night ? GardenRGB(0x263E28) : GardenRGB(0x9BD06A)
        case .summer, .mildWinter: blade = ScenesII.grass(0x8CC55A, 0x233A26, style)
        case .autumn:              blade = night ? GardenRGB(0x3E3A22) : GardenRGB(0xD9B44A)
        case .drySeason:           blade = night ? GardenRGB(0x3A3426) : GardenRGB(0xC2AC78)
        case .winter:              blade = night ? GardenRGB(0x3A4038) : GardenRGB(0xB9C2A8)
        }
        let roots: [(CGPoint, CGFloat)] = [
            (CGPoint(x: 0.575, y: 0.858), 13), (CGPoint(x: 0.622, y: 0.866), 8), (CGPoint(x: 0.668, y: 0.857), 13),
            (CGPoint(x: 0.05, y: 0.985), 15), (CGPoint(x: 0.20, y: 0.99), 14), (CGPoint(x: 0.86, y: 0.975), 15),
            (CGPoint(x: 0.97, y: 0.99), 14)
        ]
        var tufts = Path(), grain = Path()
        var rng = GardenSceneRandom(seed: GardenSceneKit.seed(staticSeed, 19))
        for (index, (root, height)) in roots.enumerated() {
            let base = band.point(root.x, root.y), tall = band.pt(height), width = band.pt(7)
            tufts.addPath(GardenSceneKit.tuft(at: base, width: width, height: tall, blades: 7,
                                              seed: GardenSceneKit.seed(staticSeed, 19 + UInt64(index))))
            // Harvest-ready grain heads nod near the tops in autumn.
            for _ in 0..<4 where style.season == .autumn {
                let head = CGPoint(x: base.x + width * rng.next(-0.6...0.6), y: base.y - tall * rng.next(0.7...0.95))
                grain.addEllipse(in: CGRect(x: head.x - band.pt(1), y: head.y - band.pt(0.4), width: band.pt(2), height: band.pt(3)))
            }
        }
        context.fill(tufts, with: .color(blade.color))
        context.fill(grain, with: .color((night ? GardenRGB(0x4A4426) : GardenRGB(0xE8C860)).color))
    }

    // MARK: Ambient: mist and glints

    /// A soft mist band drifting over the ridges at 6 pt/s (15%).
    private static func drawMist(in context: GraphicsContext, band: ScenesIIBand, state: GardenAmbientState) {
        let width = band.width * 0.55
        let travel = Double(band.width + width)
        let start = ScenesII.phase(seed: state.seed, salt: 0x3157, index: 0) * travel
        let elapsed = GardenSceneKit.motionTime(state) ?? 0
        let x = CGFloat((start + elapsed * Double(band.pt(6))).truncatingRemainder(dividingBy: travel)) - width
        let rect = CGRect(x: x, y: band.y(0.47), width: width, height: band.height * 0.045)
        let tint = GardenSceneKit.blend(0xFFFFFF, 0x8FA0B8, darkness: state.sky.darkness).color
        context.fill(Path(roundedRect: rect, cornerRadius: rect.height / 2), with: .linearGradient(
            Gradient(colors: [tint.opacity(0), tint.opacity(0.15), tint.opacity(0)]),
            startPoint: CGPoint(x: rect.minX, y: rect.midY), endPoint: CGPoint(x: rect.maxX, y: rect.midY)))
    }

    /// Six glints on the flooded spring terraces left of the tree, where
    /// nothing in the front layer covers them.
    private static func drawGlints(in context: GraphicsContext, band: ScenesIIBand, state: GardenAmbientState) {
        let clock = GardenSceneKit.motionTime(state)
        let tint = GardenSceneKit.blend(0xFFFFFF, 0xDDE6FF, darkness: state.sky.darkness)
        let strength = state.sky.darkness > 0.5 ? 0.45 : 0.6
        for index in 0..<6 {
            let a = ScenesII.phase(seed: state.seed, salt: 0x611E, index: index)
            let b = ScenesII.phase(seed: state.seed, salt: 0x611F, index: index)
            let terrace = 1 + index % 3
            let x = 0.05 + 0.36 * CGFloat(a)
            let shimmer = ScenesII.pulse(clock, hz: 0.5, phase: a)
            let length = band.pt(6 + 6 * CGFloat(b))
            let center = band.point(x, edge(terrace, at: x) + bund + 0.012 + 0.018 * CGFloat(b))
            let glint = CGRect(x: center.x - length / 2, y: center.y - band.pt(0.6), width: length, height: band.pt(1.2))
            context.fill(Path(roundedRect: glint, cornerRadius: band.pt(0.6)), with: .color(tint.color.opacity(strength * shimmer * shimmer)))
        }
    }
}

#Preview("Rice Terraces · day") {
    GardenSceneSketch(scene: .riceTerraces, localHour: 9, season: .summer)
        .frame(width: 351, height: 208)
        .border(Color.gray.opacity(0.4))
}

#Preview("Rice Terraces · night") {
    GardenSceneSketch(scene: .riceTerraces, localHour: 22, season: .spring)
        .frame(width: 351, height: 208)
        .border(Color.gray.opacity(0.4))
}
