//
//  GardenSceneKit.swift
//  Coupley
//
//  Our Garden, P5 (Scenes I): shared, deterministic drawing primitives for
//  every scene painter (C3 sky life and season particles, C4 primitives).
//  Pure and nonisolated: safe in Canvas(rendersAsynchronously: true) and in
//  ImageRenderer. Never calls TreeGrowthStage / TreeSeason members; never
//  draws text.
//
//  Coordinates (every painter, every layer and pass):
//   - `size` is always the BAND (W × H) and painters draw in band points;
//     the spec's fractions are fractions of W and H.
//   - `.far` is cached GardenSceneLayout.farWidthFactor (1.35) wide for
//     parallax: GardenBackdropCache shifts the context so band x = 0 lands
//     0.175 W into the image. Far art must cover `farSpan(in:)`
//     (−0.175 W … 1.175 W); `hills` already does.
//   - `.front` is cached as the bottom 32% of the band only: anything a
//     painter draws above (1 − frontHeightFraction) · H is cut off.
//   - Static layers are seeded by GardenSceneStyle.staticSeed(for:) (never
//     the tree); ambient passes by GardenAmbientState.seed (per tree).
//   - Static art picks colours by `GardenSkyVariant`; ambient art blends
//     them by the sky's darkness (`blend`), so the night look arrives with
//     the night landscape images.
//

import CoreGraphics
import Foundation
import SwiftUI

// MARK: - Seeded randomness

/// splitmix64-scrambled xorshift64, the same family as the tree canvas's
/// generator: deterministic across launches and devices, so a scene's
/// props never move and two phones draw the same picture.
nonisolated struct GardenSceneRandom {
    private var state: UInt64

    init(seed: UInt64) {
        var z = seed &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        state = z == 0 ? 0xdead_beef_dead_beef : z
    }

    mutating func nextUInt64() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    /// Uniform in [0, 1).
    mutating func next() -> Double {
        Double(nextUInt64() >> 11) / Double(UInt64(1) << 53)
    }

    mutating func next(_ range: ClosedRange<Double>) -> Double {
        range.lowerBound + (range.upperBound - range.lowerBound) * next()
    }

    mutating func next(_ range: ClosedRange<CGFloat>) -> CGFloat {
        range.lowerBound + (range.upperBound - range.lowerBound) * CGFloat(next())
    }

    /// Uniform in 0..<upper (0 when upper ≤ 0).
    mutating func index(_ upper: Int) -> Int {
        upper > 0 ? Int(nextUInt64() % UInt64(upper)) : 0
    }
}

nonisolated enum GardenSceneKit {

    // MARK: Geometry

    /// The far layer's horizontal extent in band points (it is wider than the band).
    static func farSpan(in size: CGSize) -> ClosedRange<CGFloat> {
        let bleed = size.width * (GardenSceneLayout.farWidthFactor - 1) / 2
        return -bleed...(size.width + bleed)
    }

    /// The top of the front layer's image in band points.
    static func frontTop(in size: CGSize) -> CGFloat {
        size.height * (1 - GardenSceneLayout.frontHeightFraction)
    }

    /// A band fraction as a point.
    static func point(_ x: CGFloat, _ y: CGFloat, in size: CGSize) -> CGPoint {
        CGPoint(x: x * size.width, y: y * size.height)
    }

    /// Mixes two seeds so sibling streams (stars, clouds, flowers) never repeat each other.
    static func seed(_ base: UInt64, _ salt: UInt64) -> UInt64 {
        base ^ (salt &* 0x9E37_79B9_7F4A_7C15)
    }

    /// A closed hill band sampling y = base − a·(0.5 + 0.5·sin(2πfx + φ)) every 8 pt.
    /// `base` and `amplitude` are fractions of H, x a fraction of W; the band
    /// spans the far layer's full width and closes along the bottom edge.
    static func hills(in size: CGSize, base: CGFloat, amplitude: CGFloat, frequency: CGFloat, phase: CGFloat) -> Path {
        var path = Path()
        guard size.width > 0, size.height > 0 else { return path }
        let span = farSpan(in: size)
        func y(_ x: CGFloat) -> CGFloat {
            let wave = 0.5 + 0.5 * sin(2 * .pi * frequency * x / size.width + phase)
            return (base - amplitude * wave) * size.height
        }
        path.move(to: CGPoint(x: span.lowerBound, y: size.height))
        var x = span.lowerBound
        while x < span.upperBound {
            path.addLine(to: CGPoint(x: x, y: y(x)))
            x += 8
        }
        path.addLine(to: CGPoint(x: span.upperBound, y: y(span.upperBound)))
        path.addLine(to: CGPoint(x: span.upperBound, y: size.height))
        path.closeSubpath()
        return path
    }

    /// The y (fraction of H) of `hills(base:amplitude:frequency:phase:)` at x (fraction of W).
    static func hillTop(atX x: CGFloat, base: CGFloat, amplitude: CGFloat, frequency: CGFloat, phase: CGFloat) -> CGFloat {
        base - amplitude * (0.5 + 0.5 * sin(2 * .pi * frequency * x + phase))
    }

    /// A quad-curve knoll from (apexX − hw, 1.0) to (apexX + hw, 1.0), control (apexX, 2·apexY − 1.0).
    /// `apex` and `halfWidth` are band fractions; the curve's top lands exactly on the apex.
    static func knoll(in size: CGSize, apex: CGPoint, halfWidth: CGFloat) -> Path {
        var path = Path()
        path.move(to: point(apex.x - halfWidth, 1, in: size))
        path.addQuadCurve(to: point(apex.x + halfWidth, 1, in: size),
                          control: point(apex.x, 2 * apex.y - 1, in: size))
        path.closeSubpath()
        return path
    }

    /// The knoll's surface (fraction of H) at x (fraction of W); nil off the knoll.
    static func knollTop(atX x: CGFloat, apex: CGPoint, halfWidth: CGFloat) -> CGFloat? {
        guard halfWidth > 0 else { return nil }
        let t = (x - (apex.x - halfWidth)) / (2 * halfWidth)
        guard (0...1).contains(t) else { return nil }
        let control = 2 * apex.y - 1
        return (1 - t) * (1 - t) + 2 * t * (1 - t) * control + t * t
    }

    /// Points along a hanging line (bulbs, lanterns, flags), both ends
    /// included. `sag` is the drop at the middle below the straight line, in
    /// the same units as the points; the curve is a true catenary shape.
    static func catenary(from: CGPoint, to: CGPoint, sag: CGFloat, count: Int) -> [CGPoint] {
        guard count > 0 else { return [] }
        guard count > 1 else { return [catenaryPoint(from: from, to: to, sag: sag, t: 0.5)] }
        return (0..<count).map { catenaryPoint(from: from, to: to, sag: sag, t: CGFloat($0) / CGFloat(count - 1)) }
    }

    /// The same hanging line as a smooth stroke path (the wire).
    static func catenaryPath(from: CGPoint, to: CGPoint, sag: CGFloat) -> Path {
        var path = Path()
        path.move(to: from)
        for i in 1...24 {
            path.addLine(to: catenaryPoint(from: from, to: to, sag: sag, t: CGFloat(i) / 24))
        }
        return path
    }

    private static func catenaryPoint(from: CGPoint, to: CGPoint, sag: CGFloat, t: CGFloat) -> CGPoint {
        // cosh shape normalised to 0 at both ends and 1 in the middle.
        let k: CGFloat = 1.2
        let drop = (cosh(k * (2 * t - 1)) - cosh(k)) / (1 - cosh(k))
        return CGPoint(x: from.x + (to.x - from.x) * t,
                       y: from.y + (to.y - from.y) * t + sag * drop)
    }

    /// Seeded, deterministic points inside `rect`.
    static func scatter(count: Int, in rect: CGRect, seed: UInt64) -> [CGPoint] {
        guard count > 0 else { return [] }
        var rng = GardenSceneRandom(seed: seed)
        return (0..<count).map { _ in
            CGPoint(x: rect.minX + rect.width * CGFloat(rng.next()),
                    y: rect.minY + rect.height * CGFloat(rng.next()))
        }
    }

    /// Seeded glint slivers (6–14 pt wide) inside `band`. With a `time` they
    /// shimmer: each one breathes in width and drifts a few points on its own
    /// phase; without one they rest at full width.
    static func glints(count: Int, band: CGRect, seed: UInt64, time: TimeInterval?) -> [CGRect] {
        guard count > 0 else { return [] }
        var rng = GardenSceneRandom(seed: seed)
        return (0..<count).map { _ in
            let center = CGPoint(x: band.minX + band.width * CGFloat(rng.next()),
                                 y: band.minY + band.height * CGFloat(rng.next()))
            let width = rng.next(6...14) as CGFloat
            let speed = rng.next(0.8...1.6), phase = rng.next(0...(2 * Double.pi))
            var scale: CGFloat = 1, drift: CGFloat = 0
            if let time {
                scale = CGFloat(0.35 + 0.65 * (0.5 + 0.5 * sin(speed * time + phase)))
                drift = CGFloat(3 * sin(0.5 * speed * time + phase))
            }
            let w = width * scale
            return CGRect(x: center.x - w / 2 + drift, y: center.y - 0.6, width: w, height: 1.2)
        }
    }

    /// 30–40 quadratic grass blades (6–14 pt) rooted along the bottom of the band.
    static func frontGrass(in size: CGSize, blades: Int, seed: UInt64) -> Path {
        var path = Path()
        guard blades > 0, size.width > 0 else { return path }
        var rng = GardenSceneRandom(seed: seed)
        let step = size.width / CGFloat(blades)
        for i in 0..<blades {
            let x = (CGFloat(i) + CGFloat(rng.next())) * step
            addBlade(to: &path, root: CGPoint(x: x, y: size.height + 1),
                     width: rng.next(2...3.2), height: rng.next(6...14), lean: rng.next(-4...4))
        }
        return path
    }

    /// A tuft of blades rooted on a line `width` wide centred on `base`
    /// (front layers use it to tuck grass over a trunk base or a dune edge).
    static func tuft(at base: CGPoint, width: CGFloat, height: CGFloat, blades: Int, seed: UInt64) -> Path {
        var path = Path()
        guard blades > 0 else { return path }
        var rng = GardenSceneRandom(seed: seed)
        for i in 0..<blades {
            let f = blades == 1 ? 0.5 : CGFloat(i) / CGFloat(blades - 1)
            let x = base.x - width / 2 + width * f + rng.next(-1...1)
            // Taller in the middle of the tuft, leaning outwards at its edges.
            let middle = 1 - abs(f - 0.5) * 0.9
            addBlade(to: &path, root: CGPoint(x: x, y: base.y + 1),
                     width: rng.next(1.6...2.6), height: height * middle * rng.next(0.7...1),
                     lean: (f - 0.5) * height * 0.6 + rng.next(-1.5...1.5))
        }
        return path
    }

    private static func addBlade(to path: inout Path, root: CGPoint, width: CGFloat, height: CGFloat, lean: CGFloat) {
        let tip = CGPoint(x: root.x + lean, y: root.y - height)
        path.move(to: CGPoint(x: root.x - width / 2, y: root.y))
        path.addQuadCurve(to: tip, control: CGPoint(x: root.x - width / 2 + lean * 0.25, y: root.y - height * 0.55))
        path.addQuadCurve(to: CGPoint(x: root.x + width / 2, y: root.y),
                          control: CGPoint(x: root.x + width / 2 + lean * 0.35, y: root.y - height * 0.5))
        path.closeSubpath()
    }

    /// A snow cap following the top edge of `path`: the part of the shape
    /// within `thickness` points of its upper outline.
    static func snowCap(on path: Path, thickness: CGFloat) -> Path {
        guard thickness > 0, !path.isEmpty else { return Path() }
        return path.subtracting(path.offsetBy(dx: 0, dy: thickness))
    }

    /// A tapered tower (windmill, lighthouse, chimney) standing on `baseCenter`.
    static func taperedTower(baseCenter: CGPoint, bottomWidth: CGFloat, topWidth: CGFloat, height: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: baseCenter.x - bottomWidth / 2, y: baseCenter.y))
        path.addLine(to: CGPoint(x: baseCenter.x - topWidth / 2, y: baseCenter.y - height))
        path.addLine(to: CGPoint(x: baseCenter.x + topWidth / 2, y: baseCenter.y - height))
        path.addLine(to: CGPoint(x: baseCenter.x + bottomWidth / 2, y: baseCenter.y))
        path.closeSubpath()
        return path
    }

    /// One cloud: four overlapping circles on a flat base, `width` wide, its
    /// base line at `baseY`, starting at `x`. One path, so one fill.
    static func cloud(x: CGFloat, baseY: CGFloat, width: CGFloat) -> Path {
        var path = Path()
        let puffs: [(CGFloat, CGFloat)] = [(0.22, 0.20), (0.45, 0.28), (0.70, 0.22), (0.86, 0.14)]
        for (cx, r) in puffs {
            let radius = width * r
            path.addEllipse(in: CGRect(x: x + width * cx - radius, y: baseY - radius * 1.7,
                                       width: radius * 2, height: radius * 2))
        }
        path.addRoundedRect(in: CGRect(x: x + width * 0.04, y: baseY - width * 0.16, width: width * 0.92, height: width * 0.16),
                            cornerSize: CGSize(width: width * 0.08, height: width * 0.08))
        return path
    }

    /// The pose time for a moving primitive: nil under the `.still` pose
    /// (Reduce Motion), so the rest frame is identical every time.
    static func motionTime(_ state: GardenAmbientState) -> TimeInterval? {
        state.pose == .still ? nil : state.time
    }

    // MARK: Sky life (C3)

    private static let starSeed: UInt64 = 0x5354_4152_5331_3430
    private static let twinklingStars = 6

    /// Sun or moon on the sky arc, and the seeded stars at `sky.starsAlpha`.
    /// Six stars twinkle while a `time` is given.
    static func drawCelestial(in context: GraphicsContext, size: CGSize, sky: GardenSkyState, time: TimeInterval?) {
        guard size.width > 0, size.height > 0 else { return }
        drawStars(in: context, size: size, sky: sky, time: time)
        if let sun = sky.sun {
            let center = point(sun.x, sun.y, in: size)
            drawGlow(in: context, center: center, radius: 34, color: GardenRGB(0xFFE7A3), opacity: 0.35)
            context.fill(Path(ellipseIn: CGRect(x: center.x - 12, y: center.y - 12, width: 24, height: 24)),
                         with: .color(GardenRGB(0xFFF4CF).color))
        }
        if let moon = sky.moon {
            let center = point(moon.x, moon.y, in: size)
            drawGlow(in: context, center: center, radius: 28, color: GardenRGB(0xF4F1DE), opacity: 0.22)
            let disc = Path(ellipseIn: CGRect(x: center.x - 11, y: center.y - 11, width: 22, height: 22))
            let bite = Path(ellipseIn: CGRect(x: center.x - 6, y: center.y - 14, width: 21, height: 21))
            // An inverse clip, not a path boolean: this runs every live frame.
            var crescent = context
            crescent.clip(to: bite, options: .inverse)
            crescent.fill(disc, with: .color(GardenRGB(0xF4F1DE).color))
        }
    }

    /// 40 seeded stars in the upper half: the steady ones in three alpha
    /// buckets (three fills), the twinkling ones one fill each.
    private static func drawStars(in context: GraphicsContext, size: CGSize, sky: GardenSkyState, time: TimeInterval?) {
        guard sky.starsAlpha > 0 else { return }
        var rng = GardenSceneRandom(seed: starSeed)
        var buckets = [Path(), Path(), Path()]
        let star = GardenRGB(0xFFFFFF).color
        for i in 0..<40 {
            let center = CGPoint(x: size.width * CGFloat(rng.next()), y: size.height * CGFloat(rng.next(0.03...0.50)))
            let r = rng.next(0.6...1.4) as CGFloat
            let alpha = rng.next(0.4...0.9)
            let speed = rng.next(1.4...3.0), phase = rng.next(0...(2 * Double.pi))
            let dot = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
            if i < twinklingStars, let time {
                let twinkle = 0.55 + 0.45 * sin(speed * time + phase)
                context.fill(dot, with: .color(star.opacity(alpha * twinkle * sky.starsAlpha)))
            } else {
                buckets[min(2, Int((alpha - 0.4) / 0.5 * 3))].addPath(dot)
            }
        }
        for (i, bucket) in buckets.enumerated() where !bucket.isEmpty {
            context.fill(bucket, with: .color(star.opacity((0.5 + 0.15 * Double(i)) * sky.starsAlpha)))
        }
    }

    /// Two or three drifting clouds (3–6 pt/s; white 85% by day, `#9AA5C7`
    /// 35% at night, blended by the sky's darkness). One fill per cloud.
    static func drawClouds(in context: GraphicsContext, size: CGSize, sky: GardenSkyState, time: TimeInterval?, seed: UInt64) {
        guard size.width > 0 else { return }
        var rng = GardenSceneRandom(seed: GardenSceneKit.seed(seed, 0xC10D))
        let count = 2 + rng.index(2)
        let tone = GardenRGB(0xFFFFFF).mixed(with: GardenRGB(0x9AA5C7), sky.darkness)
        let alpha = 0.85 + (0.35 - 0.85) * min(1, max(0, sky.darkness))
        for _ in 0..<count {
            let width = rng.next(46...70) as CGFloat
            let baseY = size.height * rng.next(0.12...0.32)
            let speed = rng.next(3...6) as CGFloat
            let lap = size.width + width * 2
            let start = CGFloat(rng.next()) * lap
            let x = (start + speed * CGFloat(time ?? 0)).truncatingRemainder(dividingBy: lap) - width
            context.fill(cloud(x: x, baseY: baseY, width: width), with: .color(tone.color.opacity(alpha)))
        }
    }

    // MARK: Season particles (C3)

    /// Petals (spring, up to 8), falling leaves (autumn, up to 8), snow
    /// (winter, up to 24) or fireflies (summer nights, up to 8), never more
    /// than `maxCount`. Mild winter and the dry season have none. Particles
    /// are analytic in time, so a pause or a skipped frame never shows.
    static func drawSeasonParticles(in context: GraphicsContext, size: CGSize, state: GardenAmbientState, maxCount: Int) {
        guard maxCount > 0, size.width > 0, size.height > 0 else { return }
        let time = motionTime(state) ?? 0
        let seed = GardenSceneKit.seed(state.seed, 0x5EA5)
        let dim = min(1, max(0, state.sky.darkness)) * 0.55
        switch state.season {
        case .spring:
            let petal = GardenRGB(0xF7C6D9).mixed(with: GardenRGB(0x2A2F4A), dim)
            context.fill(fallingFlakes(count: min(8, maxCount), size: size, time: time, seed: seed,
                                       speed: 14, sway: 6, shape: .petal),
                         with: .color(petal.color.opacity(0.9)))
        case .autumn:
            let count = min(8, maxCount)
            let first = (count + 1) / 2
            let shades = [GardenRGB(0xE08A3C), GardenRGB(0xC9653A)]
            for (i, shade) in shades.enumerated() {
                let n = i == 0 ? first : count - first
                guard n > 0 else { continue }
                context.fill(fallingFlakes(count: n, size: size, time: time, seed: GardenSceneKit.seed(seed, UInt64(i + 1)),
                                           speed: 16, sway: 10, shape: .leaf),
                             with: .color(shade.mixed(with: GardenRGB(0x2A2F4A), dim).color.opacity(0.95)))
            }
        case .winter:
            let flake = GardenRGB(0xFFFFFF).mixed(with: GardenRGB(0xC9D6E2), state.sky.darkness)
            context.fill(fallingFlakes(count: min(24, maxCount), size: size, time: time, seed: seed,
                                       speed: 18, sway: 3, shape: .snow),
                         with: .color(flake.color.opacity(0.9)))
        case .summer:
            guard state.sky.darkness > 0.5 else { return }
            drawFireflies(in: context, count: min(8, maxCount),
                          region: CGRect(x: 0, y: size.height * 0.64, width: size.width, height: size.height * 0.30),
                          time: motionTime(state), seed: seed, brightness: min(1, (state.sky.darkness - 0.5) * 2))
        case .mildWinter, .drySeason:
            return
        }
    }

    private enum FlakeShape { case petal, leaf, snow }

    private static func fallingFlakes(count: Int, size: CGSize, time: TimeInterval, seed: UInt64,
                                      speed: Double, sway: Double, shape: FlakeShape) -> Path {
        var path = Path()
        guard count > 0 else { return path }
        var rng = GardenSceneRandom(seed: seed)
        let margin = 12.0
        let lap = Double(size.height) + margin * 2
        for _ in 0..<count {
            let x0 = Double(size.width) * rng.next()
            let y0 = lap * rng.next()
            let v = speed * rng.next(0.8...1.2)
            let swaySpeed = rng.next(0.6...1.3), phase = rng.next(0...(2 * Double.pi))
            let y = (y0 + v * time).truncatingRemainder(dividingBy: lap) - margin
            let x = x0 + sway * sin(swaySpeed * time + phase)
            let spin = 0.9 * sin(swaySpeed * 1.3 * time + phase)
            let at = CGAffineTransform(translationX: x, y: y).rotated(by: spin)
            switch shape {
            case .petal:
                path.addPath(Path(ellipseIn: CGRect(x: -2.4, y: -1.4, width: 4.8, height: 2.8)), transform: at)
            case .leaf:
                var leaf = Path()
                leaf.move(to: CGPoint(x: -3.2, y: 0))
                leaf.addQuadCurve(to: CGPoint(x: 3.2, y: 0), control: CGPoint(x: 0, y: -2.6))
                leaf.addQuadCurve(to: CGPoint(x: -3.2, y: 0), control: CGPoint(x: 0, y: 2.6))
                path.addPath(leaf, transform: at)
            case .snow:
                let r: Double = rng.next(1...2)
                path.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            }
        }
        return path
    }

    /// Fireflies drifting inside `region`, each blinking on its own phase.
    /// One fill per firefly: a radial gradient whose centre is the bright
    /// core. `brightness` 0…1 scales them (a watering accent brightens them).
    static func drawFireflies(in context: GraphicsContext, count: Int, region: CGRect, time: TimeInterval?,
                              seed: UInt64, brightness: Double) {
        guard count > 0, brightness > 0 else { return }
        var rng = GardenSceneRandom(seed: seed)
        let t = time ?? 0
        let glow = GardenRGB(0xE9F59A).color, core = GardenRGB(0xF8FFD0).color
        let radius: CGFloat = 6
        for _ in 0..<count {
            let x0 = region.minX + region.width * CGFloat(rng.next())
            let y0 = region.minY + region.height * CGFloat(rng.next())
            let phase = rng.next(0...(2 * Double.pi)), speed = rng.next(0.7...1.4)
            let blink = time == nil ? 0.8 : max(0, sin(speed * 1.7 * t + phase)) * 0.8 + 0.2
            let alpha = min(1, brightness * blink)
            guard alpha > 0.02 else { continue }
            let center = CGPoint(x: x0 + CGFloat(8 * sin(0.4 * speed * t + phase)),
                                 y: y0 + CGFloat(5 * sin(0.5 * speed * t + phase * 1.3)))
            let gradient = Gradient(stops: [
                .init(color: core.opacity(alpha), location: 0),
                .init(color: core.opacity(alpha), location: 0.16),
                .init(color: glow.opacity(0.55 * alpha), location: 0.24),
                .init(color: glow.opacity(0), location: 1)
            ])
            context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                         with: .radialGradient(gradient, center: center, startRadius: 0, endRadius: radius))
        }
    }

    // MARK: Static ground details (C3)

    /// Spring's 14 flower dots or autumn's 12 leaf dots, scattered in `rect`
    /// (a part of the scene's ground). Other seasons draw nothing.
    static func drawGroundDetails(in context: GraphicsContext, rect: CGRect, season: GardenSceneSeason,
                                  variant: GardenSkyVariant, seed: UInt64) {
        let night = variant == .night
        func shade(_ hex: UInt32) -> Color {
            GardenRGB(hex).mixed(with: GardenRGB(0x1E2A30), night ? 0.65 : 0).color
        }
        var rng = GardenSceneRandom(seed: GardenSceneKit.seed(seed, 0x6D07))
        switch season {
        case .spring:
            let colors = [shade(0xFFFFFF), shade(0xFFE27A), shade(0xF7A8C4)]
            for p in scatter(count: 14, in: rect, seed: rng.nextUInt64()) {
                let r = rng.next(1.2...1.8) as CGFloat
                context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                             with: .color(colors[rng.index(colors.count)]))
            }
        case .autumn:
            let colors = [shade(0xE08A3C), shade(0xC9653A)]
            for p in scatter(count: 12, in: rect, seed: rng.nextUInt64()) {
                let leaf = Path(ellipseIn: CGRect(x: -1.8, y: -1, width: 3.6, height: 2))
                    .applying(CGAffineTransform(translationX: p.x, y: p.y).rotated(by: rng.next(0...3.1)))
                context.fill(leaf, with: .color(colors[rng.index(colors.count)]))
            }
        case .summer, .winter, .mildWinter, .drySeason:
            return
        }
    }

    // MARK: Colour

    /// The day or night colour of the same geometry.
    static func color(_ day: UInt32, _ night: UInt32, _ variant: GardenSkyVariant) -> Color {
        rgb(day, night, variant).color
    }

    static func rgb(_ day: UInt32, _ night: UInt32, _ variant: GardenSkyVariant) -> GardenRGB {
        GardenRGB(variant == .day ? day : night)
    }

    /// For ambient art: the day colour fading into the night one as the sky darkens.
    static func blend(_ day: UInt32, _ night: UInt32, darkness: Double) -> GardenRGB {
        GardenRGB(day).mixed(with: GardenRGB(night), darkness)
    }

    /// C3's shared ground treatment: summer 8% more saturated, autumn 30%
    /// toward `#C9A04A`, mild winter 10% paler, the dry season 25% toward
    /// `#C8B27A`. (Winter's snow is drawn on top with `drawSnow`.) At night the
    /// targets are darkened so a tint never lights the night landscape.
    static func ground(_ base: GardenRGB, season: GardenSceneSeason, variant: GardenSkyVariant) -> GardenRGB {
        let night = variant == .night
        func toward(_ hex: UInt32, _ amount: Double) -> GardenRGB {
            let target = GardenRGB(hex)
            return base.mixed(with: night ? scaled(target, 0.3) : target, amount)
        }
        switch season {
        case .spring:     return base
        case .summer:     return saturated(base, by: 0.08)
        case .autumn:     return toward(0xC9A04A, 0.30)
        case .winter:     return toward(0xDCE6EF, 0.12)
        case .mildWinter: return base.mixed(with: night ? GardenRGB(0x3A4256) : GardenRGB(0xFFFFFF), 0.10)
        case .drySeason:  return toward(0xC8B27A, 0.25)
        }
    }

    static func scaled(_ rgb: GardenRGB, _ factor: Double) -> GardenRGB {
        GardenRGB(r: min(1, rgb.r * factor), g: min(1, rgb.g * factor), b: min(1, rgb.b * factor))
    }

    /// Pushes a colour away from its own grey by `amount` (0.08 = 8%).
    static func saturated(_ rgb: GardenRGB, by amount: Double) -> GardenRGB {
        let grey = 0.299 * rgb.r + 0.587 * rgb.g + 0.114 * rgb.b
        func push(_ c: Double) -> Double { min(1, max(0, c + (c - grey) * amount)) }
        return GardenRGB(r: push(rgb.r), g: push(rgb.g), b: push(rgb.b))
    }

    // MARK: Fills

    /// Fills `path` with a vertical gradient over its own bounds.
    static func fillVertical(_ path: Path, in context: GraphicsContext, top: GardenRGB, bottom: GardenRGB, opacity: Double = 1) {
        let bounds = path.boundingRect
        guard !bounds.isEmpty else { return }
        context.fill(path, with: .linearGradient(Gradient(colors: [top.color.opacity(opacity), bottom.color.opacity(opacity)]),
                                                 startPoint: CGPoint(x: bounds.midX, y: bounds.minY),
                                                 endPoint: CGPoint(x: bounds.midX, y: bounds.maxY)))
    }

    /// Winter's snow on a ground shape: `#EEF3F8 → #DCE6EF` (night `#9AA7C0 →
    /// #7D8AA6`) over the top `depth` points of its outline.
    static func drawSnow(on path: Path, depth: CGFloat, in context: GraphicsContext, variant: GardenSkyVariant) {
        let cap = snowCap(on: path, thickness: depth)
        guard !cap.isEmpty else { return }
        fillVertical(cap, in: context,
                     top: rgb(0xEEF3F8, 0x9AA7C0, variant), bottom: rgb(0xDCE6EF, 0x7D8AA6, variant))
    }

    /// A lighter rim along a knoll's or dune's top edge, so the mound the
    /// tree stands on reads against ground of a similar colour.
    static func drawRim(on path: Path, thickness: CGFloat, color: GardenRGB, in context: GraphicsContext) {
        let rim = snowCap(on: path, thickness: thickness)
        guard !rim.isEmpty else { return }
        context.fill(rim, with: .color(color.color))
    }

    /// A soft radial glow (never a blur filter).
    static func drawGlow(in context: GraphicsContext, center: CGPoint, radius: CGFloat, color: GardenRGB, opacity: Double) {
        guard radius > 0, opacity > 0 else { return }
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.fill(Path(ellipseIn: rect),
                     with: .radialGradient(Gradient(colors: [color.color.opacity(opacity), color.color.opacity(0)]),
                                           center: center, startRadius: 0, endRadius: radius))
    }
}
