//
//  SeasideScene.swift
//  Coupley
//
//  Our Garden, P5 (Scenes I): Seaside (C4 scene 2; beach, marina, surfing,
//  kayaking, fishing, aquarium). The sea under a headland with a striped
//  lighthouse; the tree stands on a dune at (0.64, 0.84) above the shore,
//  with driftwood, shells and beach grass.
//
//  Snow: C4 allows it only above 45° latitude. GardenSeasons maps a Seaside
//  winter below that latitude to `.mildWinter`, so here `.winter` snows and
//  `.mildWinter` is a winter without snow; both grey the sea and send the
//  gulls away.
//

import CoreGraphics
import SwiftUI

nonisolated struct SeasideScene: GardenScenePainting {
    init() {}

    var scene: GardenSceneID { .seaside }

    private typealias Kit = GardenSceneKit

    /// The beach runs below the dune, so the dune rises out of it.
    private static let shore = (base: CGFloat(0.90), amplitude: CGFloat(0.04), frequency: CGFloat(0.7), phase: CGFloat(0.9))
    private static let duneHalfWidth: CGFloat = 0.30
    private static let lighthouseBase = CGPoint(x: 0.13, y: 0.405)
    private static let lighthouseHeight: CGFloat = 0.16

    private var apex: CGPoint { scene.info.layout.knollApex }

    /// The lantern room's centre: the beam and the night glow start here.
    private static func lantern(in size: CGSize) -> CGPoint {
        let base = Kit.point(lighthouseBase.x, lighthouseBase.y, in: size)
        return CGPoint(x: base.x, y: base.y - size.height * lighthouseHeight - 2 - size.height * 0.0175)
    }

    // MARK: Static layers

    func drawLayer(_ layer: GardenBackdropLayer, in context: GraphicsContext, size: CGSize, style: GardenSceneStyle) {
        guard size.width > 0, size.height > 0 else { return }
        switch layer {
        case .far:   drawFar(in: context, size: size, style: style)
        case .near:  drawNear(in: context, size: size, style: style)
        case .front: drawFront(in: context, size: size, style: style)
        }
    }

    private func drawFar(in context: GraphicsContext, size: CGSize, style: GardenSceneStyle) {
        let variant = style.variant
        let span = Kit.farSpan(in: size)
        let horizon = size.height * scene.info.layout.horizon
        let sea = Path(CGRect(x: span.lowerBound, y: horizon, width: span.upperBound - span.lowerBound,
                              height: size.height * 0.34))
        let (top, bottom): (GardenRGB, GardenRGB)
        switch style.season {
        case .winter, .mildWinter:
            (top, bottom) = (Kit.rgb(0x6E8FA3, 0x16283A, variant), Kit.rgb(0x9DB7C4, 0x1E3446, variant))
        case .summer:
            (top, bottom) = (Kit.rgb(0x36A3C9, 0x0E2A45, variant), Kit.rgb(0x6CC7DD, 0x173C5A, variant))
        case .spring, .autumn, .drySeason:
            (top, bottom) = (Kit.rgb(0x2F8FBF, 0x0E2A45, variant), Kit.rgb(0x6CC7DD, 0x173C5A, variant))
        }
        Kit.fillVertical(sea, in: context, top: top, bottom: bottom)
        context.fill(Path(CGRect(x: span.lowerBound, y: horizon - 0.5, width: span.upperBound - span.lowerBound, height: 1)),
                     with: .color(.white.opacity(variant == .day ? 0.4 : 0.15)))

        // The headland, two bumps falling to the water at x 0.30.
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { Kit.point(x, y, in: size) }
        var headland = Path()
        headland.move(to: CGPoint(x: span.lowerBound, y: horizon + 2))
        headland.addLine(to: CGPoint(x: span.lowerBound, y: size.height * 0.44))
        headland.addQuadCurve(to: p(0.05, 0.41), control: CGPoint(x: span.lowerBound * 0.3, y: size.height * 0.40))
        headland.addQuadCurve(to: p(0.13, 0.40), control: p(0.09, 0.37))
        headland.addQuadCurve(to: p(0.22, 0.45), control: p(0.18, 0.40))
        headland.addQuadCurve(to: p(0.30, 0.54), control: p(0.27, 0.46))
        headland.addLine(to: p(0.30, 0.545))
        headland.closeSubpath()
        let rock = Kit.ground(Kit.rgb(0x6F8F7A, 0x1B2B33, variant), season: style.season, variant: variant)
        context.fill(headland, with: .color(rock.color))
        if style.season.hasSnow { Kit.drawSnow(on: headland, depth: size.height * 0.025, in: context, variant: variant) }
    }

    private func drawNear(in context: GraphicsContext, size: CGSize, style: GardenSceneStyle) {
        let variant = style.variant, season = style.season
        let seed = GardenSceneStyle.staticSeed(for: scene)
        // Sand is already golden: autumn's ground tint would only muddy it.
        func sand(_ day: UInt32, _ night: UInt32) -> GardenRGB {
            let base = Kit.rgb(day, night, variant)
            return season == .autumn ? base : Kit.ground(base, season: season, variant: variant)
        }
        drawLighthouse(in: context, size: size, variant: variant)

        let s = Self.shore
        let beach = Kit.hills(in: size, base: s.base, amplitude: s.amplitude, frequency: s.frequency, phase: s.phase)
        Kit.fillVertical(beach, in: context, top: sand(0xEAD3A3, 0x544B3A), bottom: sand(0xE2C08A, 0x463F31))
        // The wet edge where the foam runs out.
        let wet = Kit.snowCap(on: beach, thickness: 2.5)
        context.fill(wet, with: .color(sand(0xCDB487, 0x3E382D).color.opacity(0.8)))

        let dune = Kit.knoll(in: size, apex: apex, halfWidth: Self.duneHalfWidth)
        Kit.fillVertical(dune, in: context, top: sand(0xF2DDB0, 0x5B5240), bottom: sand(0xE2C08A, 0x463F31))
        Kit.drawRim(on: dune, thickness: 2.5, color: sand(0xFAEBCB, 0x6B6150), in: context)
        if season.hasSnow { Kit.drawSnow(on: dune, depth: size.height * 0.05, in: context, variant: variant) }

        // Driftwood at (0.30, 0.92), with a knot.
        let wood = Kit.rgb(0x9C8466, 0x3E372C, variant)
        let log = Path(roundedRect: CGRect(x: -size.width * 0.05, y: -2, width: size.width * 0.10, height: 4),
                       cornerRadius: 2)
            .applying(CGAffineTransform(translationX: size.width * 0.30, y: size.height * 0.92).rotated(by: -0.14))
        context.fill(log, with: .color(wood.color))
        context.fill(Path(ellipseIn: CGRect(x: size.width * 0.31, y: size.height * 0.915, width: 2.4, height: 1.6)),
                     with: .color(Kit.scaled(wood, 0.75).color))

        // Two shells.
        let shell = Kit.color(0xF7E6DA, 0x6A625C, variant)
        for (x, y) in [(CGFloat(0.43), CGFloat(0.95)), (0.50, 0.91)] {
            var fan = Path()
            let c = Kit.point(x, y, in: size)
            fan.move(to: CGPoint(x: c.x - 3, y: c.y))
            fan.addQuadCurve(to: CGPoint(x: c.x + 3, y: c.y), control: CGPoint(x: c.x, y: c.y - 5))
            fan.closeSubpath()
            context.fill(fan, with: .color(shell))
        }
        Kit.drawGroundDetails(in: context, rect: CGRect(x: size.width * 0.40, y: size.height * 0.88,
                                                        width: size.width * 0.50, height: size.height * 0.09),
                              season: season, variant: variant, seed: seed)
    }

    private func drawLighthouse(in context: GraphicsContext, size: CGSize, variant: GardenSkyVariant) {
        let base = Kit.point(Self.lighthouseBase.x, Self.lighthouseBase.y, in: size)
        let height = size.height * Self.lighthouseHeight
        let bottom = size.width * 0.028, top = size.width * 0.018
        let tower = Kit.taperedTower(baseCenter: base, bottomWidth: bottom, topWidth: top, height: height)
        context.fill(tower, with: .color(Kit.color(0xF7F4EE, 0x4A5266, variant)))
        var bands = Path()
        for (from, to) in [(CGFloat(0.15), CGFloat(0.27)), (0.42, 0.54), (0.69, 0.81)] {
            bands.addRect(CGRect(x: base.x - bottom, y: base.y - height * to, width: bottom * 2, height: height * (to - from)))
        }
        context.fill(bands.intersection(tower), with: .color(Kit.color(0xD9534F, 0x5A2E36, variant)))

        let dark = Kit.color(0x3C3C3C, 0x22242C, variant)
        let galleryY = base.y - height - 2
        context.fill(Path(CGRect(x: base.x - top * 0.8, y: galleryY, width: top * 1.6, height: 2)), with: .color(dark))
        let lantern = Self.lantern(in: size)
        let room = CGRect(x: base.x - top * 0.38, y: lantern.y - size.height * 0.0175, width: top * 0.76, height: size.height * 0.035)
        if variant == .night {
            Kit.drawGlow(in: context, center: lantern, radius: 14, color: GardenRGB(0xFFE8A0), opacity: 0.5)
        }
        context.fill(Path(room), with: .color(Kit.color(0xCFE6EE, 0xFFE8A0, variant)))
        context.stroke(Path(room), with: .color(dark), lineWidth: 0.8)
        var cap = Path()
        cap.move(to: CGPoint(x: room.minX - 1.5, y: room.minY))
        cap.addLine(to: CGPoint(x: base.x, y: room.minY - size.height * 0.03))
        cap.addLine(to: CGPoint(x: room.maxX + 1.5, y: room.minY))
        cap.closeSubpath()
        context.fill(cap, with: .color(dark))
    }

    private func drawFront(in context: GraphicsContext, size: CGSize, style: GardenSceneStyle) {
        let variant = style.variant
        let seed = GardenSceneStyle.staticSeed(for: scene)
        var grass = Path()
        let spots: [(x: CGFloat, y: CGFloat?, height: CGFloat)] = [
            (apex.x - 0.08, nil, 12), (apex.x + 0.09, nil, 11), (0.47, 0.955, 13), (0.06, 0.995, 14), (0.93, 0.99, 12)
        ]
        for (i, spot) in spots.enumerated() {
            let y = spot.y ?? (Kit.knollTop(atX: spot.x, apex: apex, halfWidth: Self.duneHalfWidth) ?? apex.y) + 0.012
            grass.addPath(Kit.tuft(at: Kit.point(spot.x, y, in: size), width: 12, height: spot.height, blades: 6,
                                   seed: Kit.seed(seed, UInt64(0x20 + i))))
        }
        let blade = Kit.ground(Kit.rgb(0x9BB86B, 0x3C4A2E, variant), season: style.season, variant: variant)
        context.fill(grass, with: .color(blade.color))
    }

    // MARK: Ambient

    func drawAmbient(_ pass: GardenAmbientPass, in context: GraphicsContext, size: CGSize, state: GardenAmbientState) {
        guard size.width > 0, size.height > 0 else { return }
        let time = Kit.motionTime(state)
        let darkness = state.sky.darkness
        switch pass {
        case .sky:
            Kit.drawCelestial(in: context, size: size, sky: state.sky, time: time)
            Kit.drawClouds(in: context, size: size, sky: state.sky, time: time, seed: state.seed)
        case .behind:
            drawGlints(in: context, size: size, state: state, time: time)
            drawFoam(in: context, size: size, time: time, darkness: darkness)
            if darkness < 0.5, state.season != .winter, state.season != .mildWinter {
                drawGulls(in: context, size: size, time: time, seed: state.seed, alpha: 1 - darkness * 2)
            }
            if darkness > 0.3 {
                drawBeam(in: context, size: size, time: time, intensity: min(1, (darkness - 0.3) / 0.3))
            }
        case .front:
            Kit.drawSeasonParticles(in: context, size: size, state: state, maxCount: state.season == .winter ? 12 : 8)
        }
    }

    /// Eight glints on the sea; at night they gather under the moon.
    private func drawGlints(in context: GraphicsContext, size: CGSize, state: GardenAmbientState, time: TimeInterval?) {
        var band = CGRect(x: 0, y: size.height * 0.57, width: size.width, height: size.height * 0.19)
        if let moon = state.sky.moon, state.sky.darkness > 0.5 {
            band = CGRect(x: size.width * (moon.x - 0.12), y: size.height * 0.57, width: size.width * 0.24, height: size.height * 0.19)
        }
        var path = Path()
        for rect in Kit.glints(count: 8, band: band, seed: Kit.seed(state.seed, 0x6117), time: time) {
            path.addRoundedRect(in: rect, cornerSize: CGSize(width: 0.6, height: 0.6))
        }
        context.fill(path, with: .color(Kit.blend(0xFFFFFF, 0xE8EEF8, darkness: state.sky.darkness).color.opacity(0.5)))
    }

    /// Two foam lines at 0.78 and 0.80, sliding ±6 pt over 4 s.
    private func drawFoam(in context: GraphicsContext, size: CGSize, time: TimeInterval?, darkness: Double) {
        for (i, y) in [CGFloat(0.78), 0.80].enumerated() {
            let shift = CGFloat(6 * sin(2 * .pi * (time ?? 0) / 4 + Double(i) * 1.9))
            var line = Path()
            var x: CGFloat = -8
            line.move(to: CGPoint(x: x + shift, y: size.height * y))
            while x < size.width + 8 {
                x += 12
                line.addQuadCurve(to: CGPoint(x: x + shift, y: size.height * y),
                                  control: CGPoint(x: x - 6 + shift, y: size.height * y - 1.2))
            }
            context.stroke(line, with: .color(.white.opacity(0.5 - 0.3 * darkness)),
                           style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [9, 5]))
        }
    }

    /// Two gulls, stroked "M"s gliding across the sky.
    private func drawGulls(in context: GraphicsContext, size: CGSize, time: TimeInterval?, seed: UInt64, alpha: Double) {
        guard alpha > 0 else { return }
        var rng = GardenSceneRandom(seed: Kit.seed(seed, 0x6011))
        let t = time ?? 0
        var gulls = Path()
        for _ in 0..<2 {
            let lap = Double(size.width) + 40
            let x = CGFloat((rng.next() * lap + rng.next(6...10) * t).truncatingRemainder(dividingBy: lap)) - 20
            let phase = rng.next(0...(2 * Double.pi))
            let y = size.height * rng.next(0.16...0.30) + CGFloat(3 * sin(0.7 * t + phase))
            let depth = CGFloat(2.4 + 1.4 * sin(5 * t + phase))
            gulls.move(to: CGPoint(x: x - 6, y: y))
            gulls.addQuadCurve(to: CGPoint(x: x, y: y + 0.8), control: CGPoint(x: x - 3, y: y - depth))
            gulls.addQuadCurve(to: CGPoint(x: x + 6, y: y), control: CGPoint(x: x + 3, y: y - depth))
        }
        context.stroke(gulls, with: .color(GardenRGB(0x3C4652).color.opacity(0.8 * alpha)),
                       style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
    }

    /// The lighthouse beam: a wedge 0.5 W long, 35% → 0, sweeping ±40° at 0.6 rad/s.
    private func drawBeam(in context: GraphicsContext, size: CGSize, time: TimeInterval?, intensity: Double) {
        let origin = Self.lantern(in: size)
        let swing = 40.0 * .pi / 180
        let angle = swing * sin(0.6 * (time ?? 0) / swing)
        let spread = 5.0 * .pi / 180
        let length = Double(size.width) * 0.5
        func end(_ a: Double) -> CGPoint {
            CGPoint(x: origin.x + CGFloat(cos(a) * length), y: origin.y + CGFloat(sin(a) * length))
        }
        var wedge = Path()
        wedge.move(to: origin)
        wedge.addLine(to: end(angle - spread))
        wedge.addLine(to: end(angle + spread))
        wedge.closeSubpath()
        let light = GardenRGB(0xFFE8A0).color
        context.fill(wedge, with: .linearGradient(Gradient(colors: [light.opacity(0.35 * intensity), light.opacity(0)]),
                                                  startPoint: origin, endPoint: end(angle)))
    }

    // MARK: Watering accent

    /// A wave crest curls at the dune's edge and throws spray over it.
    func drawWateringAccent(in context: GraphicsContext, size: CGSize, state: GardenAmbientState, progress: Double) {
        guard size.width > 0, size.height > 0 else { return }
        let p = min(1, max(0, progress))
        let fade = 1 - p
        let water = Kit.blend(0xFFFFFF, 0xCFE3FF, darkness: state.sky.darkness).color

        var crest = Path()
        let rise = size.height * 0.05 * CGFloat(sin(.pi * p))
        crest.move(to: Kit.point(0.29, 0.80, in: size))
        crest.addQuadCurve(to: CGPoint(x: size.width * 0.41, y: size.height * 0.80 - rise),
                           control: CGPoint(x: size.width * 0.36, y: size.height * 0.80 - rise * 1.6))
        context.stroke(crest, with: .color(water.opacity(0.75 * fade)), style: StrokeStyle(lineWidth: 2, lineCap: .round))

        var spray = Path()
        var rng = GardenSceneRandom(seed: Kit.seed(state.seed, 0x5A2A))
        let tau = p * 0.6
        for _ in 0..<14 {
            let x0 = size.width * rng.next(0.34...0.44), y0 = size.height * 0.80
            let vx: Double = rng.next(40...90), vy: Double = -rng.next(90...150)
            let x = x0 + CGFloat(vx * tau), y = y0 + CGFloat(vy * tau + 0.5 * 400 * tau * tau)
            let r = rng.next(1.2...2) as CGFloat
            spray.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        }
        context.fill(spray, with: .color(water.opacity(0.85 * fade)))
    }
}

#Preview("Seaside · day") {
    GardenSceneSketch(scene: .seaside, localHour: 10, season: .summer)
        .frame(width: 351, height: 208)
        .border(Color.gray.opacity(0.4))
}

#Preview("Seaside · night") {
    GardenSceneSketch(scene: .seaside, localHour: 21.5, season: .summer)
        .frame(width: 351, height: 208)
        .border(Color.gray.opacity(0.4))
}
