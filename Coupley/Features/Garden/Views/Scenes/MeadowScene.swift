//
//  MeadowScene.swift
//  Coupley
//
//  Our Garden, P5 (Scenes I): Meadow (C4 scene 1, the default; parks,
//  sports, amusement). Rolling hills with a tree line, a field with a
//  winding path, a split-rail fence and a windmill on the far hill; the tree
//  stands on a grassy knoll at (0.62, 0.86).
//

import CoreGraphics
import SwiftUI

nonisolated struct MeadowScene: GardenScenePainting {
    init() {}

    var scene: GardenSceneID { .meadow }

    private typealias Kit = GardenSceneKit

    // Geometry shared by the static layers and the ambient passes (band fractions).
    private static let hillA = (base: CGFloat(0.58), amplitude: CGFloat(0.06), frequency: CGFloat(0.9), phase: CGFloat(0.3))
    private static let hillB = (base: CGFloat(0.64), amplitude: CGFloat(0.05), frequency: CGFloat(1.4), phase: CGFloat(2.1))
    private static let field = (base: CGFloat(0.70), amplitude: CGFloat(0.035), frequency: CGFloat(0.55), phase: CGFloat(4.0))
    private static let knollHalfWidth: CGFloat = 0.30
    private static let windmillX: CGFloat = 0.20
    private static let windmillHeight: CGFloat = 0.11

    private var apex: CGPoint { scene.info.layout.knollApex }

    /// The windmill stands on hill A's crest; its hub is the tower top.
    private static func windmillBase(in size: CGSize) -> CGPoint {
        let y = Kit.hillTop(atX: windmillX, base: hillA.base, amplitude: hillA.amplitude,
                            frequency: hillA.frequency, phase: hillA.phase)
        return Kit.point(windmillX, y + 0.004, in: size)
    }

    private static func windmillHub(in size: CGSize) -> CGPoint {
        let base = windmillBase(in: size)
        return CGPoint(x: base.x, y: base.y - size.height * windmillHeight)
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
        let variant = style.variant, season = style.season
        let autumnDay = season == .autumn && variant == .day
        var rng = GardenSceneRandom(seed: GardenSceneStyle.staticSeed(for: scene))

        let a = Self.hillA
        let hillA = Kit.hills(in: size, base: a.base, amplitude: a.amplitude, frequency: a.frequency, phase: a.phase)
        let snow = Kit.rgb(0xDCE6EF, 0x7D8AA6, variant)
        var hillAColor = autumnDay ? GardenRGB(0xC9B48A) : Kit.ground(Kit.rgb(0xA8C8B4, 0x1F3446, variant), season: season, variant: variant)
        if season.hasSnow { hillAColor = hillAColor.mixed(with: snow, 0.7) }
        context.fill(hillA, with: .color(hillAColor.color))
        if season.hasSnow { Kit.drawSnow(on: hillA, depth: size.height * 0.03, in: context, variant: variant) }

        // A tree line of nine round silhouettes along hill A's crest.
        var treeLine = Path()
        let span = Kit.farSpan(in: size)
        let step = (span.upperBound - span.lowerBound) / 9
        for i in 0..<9 {
            let x = span.lowerBound + (CGFloat(i) + rng.next(0.2...0.8)) * step
            let top = Kit.hillTop(atX: x / size.width, base: a.base, amplitude: a.amplitude,
                                  frequency: a.frequency, phase: a.phase) * size.height
            let r = rng.next(5...9) as CGFloat
            treeLine.addEllipse(in: CGRect(x: x - r, y: top - r * 1.5, width: r * 2, height: r * 2))
            treeLine.addEllipse(in: CGRect(x: x + r * 0.35, y: top - r * 1.1, width: r * 1.3, height: r * 1.3))
        }
        var lineColor = Kit.rgb(0x7FAF78, 0x162A24, variant)
        switch season {
        case .autumn:     lineColor = lineColor.mixed(with: Kit.rgb(0xC9A04A, 0x2E2A1C, variant), 0.45)
        case .winter:     lineColor = lineColor.mixed(with: Kit.rgb(0xDCE6EF, 0x3A4256, variant), 0.35)
        case .drySeason:  lineColor = lineColor.mixed(with: Kit.rgb(0xC8B27A, 0x2E2A1C, variant), 0.2)
        case .spring, .summer, .mildWinter: break
        }
        context.fill(treeLine, with: .color(lineColor.color.opacity(variant == .day ? 0.6 : 1)))

        let b = Self.hillB
        let hillB = Kit.hills(in: size, base: b.base, amplitude: b.amplitude, frequency: b.frequency, phase: b.phase)
        var hillBColor = autumnDay ? GardenRGB(0xBFA87C) : Kit.ground(Kit.rgb(0x94BFA0, 0x1B3040, variant), season: season, variant: variant)
        if season.hasSnow { hillBColor = hillBColor.mixed(with: Kit.rgb(0xC9D6E2, 0x6F7D99, variant), 0.75) }
        context.fill(hillB, with: .color(hillBColor.color))
        if season.hasSnow { Kit.drawSnow(on: hillB, depth: size.height * 0.03, in: context, variant: variant) }
    }

    private func drawNear(in context: GraphicsContext, size: CGSize, style: GardenSceneStyle) {
        let variant = style.variant, season = style.season
        let staticSeed = GardenSceneStyle.staticSeed(for: scene)
        let snowTone = (Kit.rgb(0xEEF3F8, 0x9AA7C0, variant), Kit.rgb(0xC9D6E2, 0x6F7D99, variant))

        // The field, its top gently rolling.
        let f = Self.field
        let field = Kit.hills(in: size, base: f.base, amplitude: f.amplitude, frequency: f.frequency, phase: f.phase)
        switch season {
        case .autumn where variant == .day:
            Kit.fillVertical(field, in: context, top: GardenRGB(0xC9A35A), bottom: GardenRGB(0xB5873F))
        case .winter:
            // Snow over the whole field, its blue shadows gathering low.
            Kit.fillVertical(field, in: context, top: snowTone.0, bottom: snowTone.1)
        default:
            Kit.fillVertical(field, in: context,
                             top: Kit.ground(Kit.rgb(0x86C27A, 0x1E3A2E, variant), season: season, variant: variant),
                             bottom: Kit.ground(Kit.rgb(0x6EAE63, 0x183026, variant), season: season, variant: variant))
        }

        drawPath(in: context, size: size, variant: variant, snowy: season.hasSnow)
        drawFence(in: context, size: size, variant: variant, snowy: season.hasSnow)
        drawWindmill(in: context, size: size, variant: variant)

        // The knoll the tree stands on.
        let knoll = Kit.knoll(in: size, apex: apex, halfWidth: Self.knollHalfWidth)
        if season.hasSnow {
            context.fill(knoll, with: .color(snowTone.1.color))
            Kit.drawSnow(on: knoll, depth: size.height * 0.06, in: context, variant: variant)
        } else {
            let knollColor = season == .autumn && variant == .day
                ? GardenRGB(0xB89A55) : Kit.ground(Kit.rgb(0x6FAF5F, 0x1C3527, variant), season: season, variant: variant)
            context.fill(knoll, with: .color(knollColor.color))
            Kit.drawRim(on: knoll, thickness: 2.5, color: Kit.scaled(knollColor, variant == .day ? 1.18 : 1.35), in: context)
        }

        // 36 wildflowers while the meadow is green.
        if season == .spring || season == .summer || season == .drySeason {
            var rng = GardenSceneRandom(seed: Kit.seed(staticSeed, 0xF10))
            let colors = [0xFFFFFF, 0xFFE27A, 0xF7A8C4].map {
                GardenRGB(UInt32($0)).mixed(with: GardenRGB(0x1E3A2E), variant == .night ? 0.65 : 0).color
            }
            let meadow = CGRect(x: size.width * 0.02, y: size.height * 0.74, width: size.width * 0.96, height: size.height * 0.24)
            for p in Kit.scatter(count: 36, in: meadow, seed: rng.nextUInt64()) {
                let r = rng.next(1.2...2) as CGFloat
                context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                             with: .color(colors[rng.index(colors.count)]))
            }
        }
        Kit.drawGroundDetails(in: context, rect: CGRect(x: size.width * 0.03, y: size.height * 0.76,
                                                        width: size.width * 0.94, height: size.height * 0.21),
                              season: season, variant: variant, seed: staticSeed)
    }

    /// A winding path from the bottom-left towards the horizon, 18 → 4 pt wide.
    private func drawPath(in context: GraphicsContext, size: CGSize, variant: GardenSkyVariant, snowy: Bool) {
        let p0 = Kit.point(0.05, 0.98, in: size), c1 = Kit.point(0.34, 0.93, in: size)
        let c2 = Kit.point(0.20, 0.78, in: size), p3 = Kit.point(0.55, 0.72, in: size)
        func bezier(_ t: CGFloat) -> CGPoint {
            let u = 1 - t
            return CGPoint(x: u * u * u * p0.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * p3.x,
                           y: u * u * u * p0.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * p3.y)
        }
        let samples = 18
        var left: [CGPoint] = [], right: [CGPoint] = []
        for i in 0...samples {
            let t = CGFloat(i) / CGFloat(samples)
            let p = bezier(t), q = bezier(min(1, t + 0.01)), o = bezier(max(0, t - 0.01))
            let dx = q.x - o.x, dy = q.y - o.y
            let length = max(0.001, sqrt(dx * dx + dy * dy))
            let half = (18 + (4 - 18) * t) / 2
            left.append(CGPoint(x: p.x - dy / length * half, y: p.y + dx / length * half))
            right.append(CGPoint(x: p.x + dy / length * half, y: p.y - dx / length * half))
        }
        var path = Path()
        path.addLines(left + right.reversed())
        path.closeSubpath()
        var color = Kit.rgb(0xE8D6A8, 0x4C4636, variant)
        if snowy { color = color.mixed(with: Kit.rgb(0xF4F7FA, 0xA6B2C8, variant), 0.6) }
        context.fill(path, with: .color(color.color))
    }

    /// A split-rail fence across x 0.04–0.34 at y 0.76: six posts, two rails.
    private func drawFence(in context: GraphicsContext, size: CGSize, variant: GardenSkyVariant, snowy: Bool) {
        let wood = Kit.color(0x8C6B4A, 0x3B2E24, variant)
        let left = size.width * 0.04, right = size.width * 0.34
        var fence = Path()
        for rail in [CGFloat(0.728), 0.756] {
            fence.addRect(CGRect(x: left, y: size.height * rail, width: right - left, height: 1.6))
        }
        var caps = Path()
        for i in 0..<6 {
            let x = left + (right - left) * CGFloat(i) / 5
            let top = size.height * 0.705
            fence.addRect(CGRect(x: x - 1.2, y: top, width: 2.4, height: size.height * 0.08))
            caps.addRoundedRect(in: CGRect(x: x - 1.9, y: top - 1.6, width: 3.8, height: 2.2), cornerSize: CGSize(width: 1, height: 1))
        }
        context.fill(fence, with: .color(wood))
        if snowy { context.fill(caps, with: .color(Kit.color(0xF4F7FA, 0xA6B2C8, variant))) }
    }

    /// The windmill's tower, cap, window and hub (its blades turn in the behind pass).
    private func drawWindmill(in context: GraphicsContext, size: CGSize, variant: GardenSkyVariant) {
        let base = Self.windmillBase(in: size)
        let height = size.height * Self.windmillHeight
        let bottom = size.width * 0.018, top = size.width * 0.010
        context.fill(Kit.taperedTower(baseCenter: base, bottomWidth: bottom, topWidth: top, height: height),
                     with: .color(Kit.color(0xEDE6DA, 0x3A4256, variant)))
        let hub = Self.windmillHub(in: size)
        var cap = Path()
        cap.move(to: CGPoint(x: hub.x - top * 0.9, y: hub.y + 1))
        cap.addLine(to: CGPoint(x: hub.x, y: hub.y - size.height * 0.022))
        cap.addLine(to: CGPoint(x: hub.x + top * 0.9, y: hub.y + 1))
        cap.closeSubpath()
        context.fill(cap, with: .color(Kit.color(0xB5634B, 0x2A2F40, variant)))

        let window = CGRect(x: base.x - 1.1, y: base.y - height * 0.55, width: 2.2, height: 3)
        if variant == .night {
            Kit.drawGlow(in: context, center: CGPoint(x: window.midX, y: window.midY), radius: 7,
                         color: GardenRGB(0xFFD27A), opacity: 0.45)
            context.fill(Path(window), with: .color(GardenRGB(0xFFD27A).color))
        } else {
            context.fill(Path(window), with: .color(GardenRGB(0x8C7F70).color))
        }
        context.fill(Path(ellipseIn: CGRect(x: hub.x - 1.4, y: hub.y - 1.4, width: 2.8, height: 2.8)),
                     with: .color(Kit.color(0x6E5E4E, 0x1E2230, variant)))
    }

    private func drawFront(in context: GraphicsContext, size: CGSize, style: GardenSceneStyle) {
        let variant = style.variant, season = style.season
        let seed = GardenSceneStyle.staticSeed(for: scene)
        var blade = Kit.ground(Kit.rgb(0x4E8A47, 0x1A2E22, variant), season: season, variant: variant)
        if season.hasSnow { blade = blade.mixed(with: Kit.rgb(0xDCE6EF, 0x7D8AA6, variant), 0.45) }
        var grass = Kit.frontGrass(in: size, blades: 36, seed: Kit.seed(seed, 0xB1))
        // Tufts either side of the trunk base, so the tree stands in the grass.
        for (i, dx) in [CGFloat(-0.075), 0.08].enumerated() {
            let x = apex.x + dx
            let top = Kit.knollTop(atX: x, apex: apex, halfWidth: Self.knollHalfWidth) ?? apex.y
            grass.addPath(Kit.tuft(at: Kit.point(x, top + 0.012, in: size), width: 14, height: 9, blades: 7,
                                   seed: Kit.seed(seed, UInt64(0x70 + i))))
        }
        context.fill(grass, with: .color(blade.color))
    }

    // MARK: Ambient

    func drawAmbient(_ pass: GardenAmbientPass, in context: GraphicsContext, size: CGSize, state: GardenAmbientState) {
        guard size.width > 0, size.height > 0 else { return }
        let time = Kit.motionTime(state)
        switch pass {
        case .sky:
            Kit.drawCelestial(in: context, size: size, sky: state.sky, time: time)
            Kit.drawClouds(in: context, size: size, sky: state.sky, time: time, seed: state.seed)
        case .behind:
            drawBlades(in: context, size: size, angle: 0.3 + 0.25 * (time ?? 0), darkness: state.sky.darkness)
        case .front:
            if state.season == .spring || state.season == .summer, state.sky.darkness < 0.5 {
                drawButterflies(in: context, size: size, time: time, seed: state.seed, alpha: 1 - state.sky.darkness * 2)
            }
            Kit.drawSeasonParticles(in: context, size: size, state: state, maxCount: 24)
        }
    }

    /// Four sails 0.06 H long around the hub, turning 0.25 rad/s. One fill.
    private func drawBlades(in context: GraphicsContext, size: CGSize, angle: Double, darkness: Double) {
        let hub = Self.windmillHub(in: size)
        let length = size.height * 0.06
        var sail = Path()
        sail.move(to: CGPoint(x: 1.5, y: -0.6))
        sail.addLine(to: CGPoint(x: length, y: -1.8))
        sail.addLine(to: CGPoint(x: length, y: 1.8))
        sail.addLine(to: CGPoint(x: 1.5, y: 0.6))
        sail.closeSubpath()
        var blades = Path()
        for i in 0..<4 {
            blades.addPath(sail, transform: CGAffineTransform(translationX: hub.x, y: hub.y)
                .rotated(by: CGFloat(angle) + CGFloat(i) * .pi / 2))
        }
        context.fill(blades, with: .color(Kit.blend(0xF2EDE4, 0x4A5266, darkness: darkness).color))
    }

    private func drawButterflies(in context: GraphicsContext, size: CGSize, time: TimeInterval?, seed: UInt64, alpha: Double) {
        guard alpha > 0 else { return }
        var rng = GardenSceneRandom(seed: Kit.seed(seed, 0xB077))
        let t = time ?? 0
        for color in [GardenRGB(0xF7C6D9), GardenRGB(0xFFE27A)] {
            let phase = rng.next(0...(2 * Double.pi)), cx = rng.next(0.18...0.42), cy = rng.next(0.66...0.74)
            let center = Kit.point(CGFloat(cx + 0.12 * sin(0.45 * t + phase)),
                                   CGFloat(cy + 0.05 * sin(0.9 * t + phase * 1.7)), in: size)
            let flap = time == nil ? 0.8 : abs(sin(2 * .pi * 6 * t + phase))
            context.fill(Self.butterfly(at: center, flap: flap, size: 3.5), with: .color(color.color.opacity(alpha)))
        }
    }

    /// Two ellipse wings per side; `flap` 0…1 is how open they are.
    private static func butterfly(at center: CGPoint, flap: Double, size s: CGFloat) -> Path {
        let w = s * CGFloat(max(0.2, flap))
        var path = Path()
        path.addEllipse(in: CGRect(x: center.x - w, y: center.y - s * 0.9, width: w, height: s * 0.9))
        path.addEllipse(in: CGRect(x: center.x, y: center.y - s * 0.9, width: w, height: s * 0.9))
        path.addEllipse(in: CGRect(x: center.x - w * 0.7, y: center.y - s * 0.1, width: w * 0.7, height: s * 0.6))
        path.addEllipse(in: CGRect(x: center.x, y: center.y - s * 0.1, width: w * 0.7, height: s * 0.6))
        return path
    }

    // MARK: Watering accent

    /// Day: two butterflies lift off the knoll. Night: the fireflies brighten.
    func drawWateringAccent(in context: GraphicsContext, size: CGSize, state: GardenAmbientState, progress: Double) {
        guard size.width > 0, size.height > 0 else { return }
        let p = min(1, max(0, progress))
        let fade = min(1, p * 5) * (1 - max(0, (p - 0.8) / 0.2))
        if state.sky.darkness > 0.5 {
            let region = CGRect(x: size.width * 0.30, y: size.height * 0.60, width: size.width * 0.65, height: size.height * 0.30)
            Kit.drawFireflies(in: context, count: 8, region: region, time: state.time,
                              seed: Kit.seed(state.seed, 0xACC), brightness: 0.3 + 0.7 * sin(.pi * p))
            return
        }
        for (i, color) in [GardenRGB(0xF7C6D9), GardenRGB(0xFFE27A)].enumerated() {
            let side: CGFloat = i == 0 ? -1 : 1
            let center = Kit.point(apex.x + side * (0.04 + 0.12 * CGFloat(p)),
                                   apex.y - 0.05 - 0.45 * CGFloat(p) + 0.03 * CGFloat(sin(9 * p + Double(i))), in: size)
            let flap = abs(sin(2 * .pi * 8 * (state.time + Double(i) * 0.07)))
            context.fill(Self.butterfly(at: center, flap: flap, size: 4.6), with: .color(color.color.opacity(fade)))
        }
    }
}

#Preview("Meadow · day") {
    GardenSceneSketch(scene: .meadow, localHour: 11, season: .summer)
        .frame(width: 351, height: 208)
        .border(Color.gray.opacity(0.4))
}

#Preview("Meadow · night") {
    GardenSceneSketch(scene: .meadow, localHour: 22, season: .summer)
        .frame(width: 351, height: 208)
        .border(Color.gray.opacity(0.4))
}
