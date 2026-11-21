//
//  WateringEffectPainter.swift
//  Coupley
//
//  P8: the one watering-effect painter (spec C9). Dispatches to the six
//  effects, holds the analytic particle math, the shared sprites (the can,
//  drops, glints, the rainbow) and the golden first drop.
//
//  How it draws (C9, C11):
//   - Every particle is analytic. Its start position, velocity and spawn
//     time come from the watering's seed and the particle's index through
//     `unit(_:_:_:)`, and it is drawn at p(t) = p0 + v·(t − spawn) +
//     ½·g·(t − spawn)². Nothing is stored between frames, nothing is
//     allocated per particle, and any frame (after a pause, a skipped
//     frame, a replay) is exactly the frame for its time.
//   - Particles of one kind are gathered into ONE path and filled once.
//   - Glows are radial gradients, never blur filters.
//   - Budget: at most 80 particles and 2 sprites per frame (≤ 1.5 ms on an
//     A12). DEBUG builds wrap each frame in a `garden.effect` signpost.
//
//  nonisolated: uses only what GardenEffectFrame hands it (anchors, sky,
//  size) and never calls a TreeGrowthStage / TreeSeason member, so it is
//  safe inside Canvas(rendersAsynchronously: true). No text is ever drawn.
//

import SwiftUI
#if DEBUG
import os
#endif

nonisolated enum WateringEffectPainter: WateringEffectDrawing {

    /// The golden first drop that opens the garden's very first watering
    /// (`GardenEffectPlayback.totalDuration` adds the same 0.4 s).
    static let firstDropDuration: TimeInterval = 0.4

    #if DEBUG
    private static let signposter = OSSignposter(subsystem: "com.SamCorp.Coupley", category: "Garden")
    #endif

    /// Draws one frame of `frame.playback.effect`; nothing after it ends.
    static func draw(in context: GraphicsContext, frame: GardenEffectFrame) {
        let playback = frame.playback
        guard frame.elapsed >= 0, frame.elapsed < playback.totalDuration else { return }
        #if DEBUG
        let interval = signposter.beginInterval("garden.effect")
        defer { signposter.endInterval("garden.effect", interval) }
        #endif

        var effectFrame = frame
        if playback.isFirstEver {
            drawGoldenDrop(in: context, frame: frame)
            effectFrame.elapsed -= firstDropDuration
            guard effectFrame.elapsed >= 0 else { return }
        }
        switch playback.effect {
        case .can:            drawCan(in: context, frame: effectFrame)
        case .together:       drawTogether(in: context, frame: effectFrame)
        case .rainCloud:      drawRainCloud(in: context, frame: effectFrame)
        case .morningDew:     drawMorningDew(in: context, frame: effectFrame)
        case .moonlitDrizzle: drawMoonlitDrizzle(in: context, frame: effectFrame)
        case .rainReturns:    drawRainReturns(in: context, frame: effectFrame)
        }
    }
}

// MARK: - The golden first drop

nonisolated extension WateringEffectPainter {
    /// One big golden drop falls onto the canopy's crown in 0.4 s, then a
    /// warm glow blooms where it lands while the effect begins.
    static func drawGoldenDrop(in context: GraphicsContext, frame: GardenEffectFrame) {
        let a = frame.anchors
        let t = frame.elapsed
        let crown = CGPoint(x: a.canopyCenter.x, y: a.canopyCenter.y - a.canopyRadius * 0.55)
        let gold = GardenRGB(0xFFD36B).color
        let deepGold = GardenRGB(0xF5A623).color

        if t < firstDropDuration {
            let p = easeInCubic(t / firstDropDuration)
            let startY = max(10, crown.y - 90)
            let center = CGPoint(x: crown.x, y: startY + (crown.y - startY) * p)
            let glowRadius: CGFloat = 16
            context.fill(Path(ellipseIn: CGRect(x: center.x - glowRadius, y: center.y - glowRadius,
                                                width: glowRadius * 2, height: glowRadius * 2)),
                         with: .radialGradient(Gradient(colors: [gold.opacity(0.45), gold.opacity(0)]),
                                               center: center, startRadius: 0, endRadius: glowRadius))
            let drop = teardrop(center: center, width: 10, height: 14)
            context.fill(drop, with: .linearGradient(Gradient(colors: [gold, deepGold]),
                                                     startPoint: CGPoint(x: center.x, y: center.y - 7),
                                                     endPoint: CGPoint(x: center.x, y: center.y + 7)))
            context.fill(Path(ellipseIn: CGRect(x: center.x - 2.6, y: center.y + 0.5, width: 2.4, height: 3.2)),
                         with: .color(.white.opacity(0.7)))
        }

        // The landing glow: 0.4 → 0.9 s, growing and fading, lighting the
        // canopy rather than tinting it.
        let glow = (t - firstDropDuration) / 0.5
        if glow >= 0, glow < 1 {
            let radius = 10 + 34 * CGFloat(easeOutCubic(glow))
            var lit = context
            lit.blendMode = .plusLighter
            lit.fill(Path(ellipseIn: CGRect(x: crown.x - radius, y: crown.y - radius,
                                                width: radius * 2, height: radius * 2)),
                         with: .radialGradient(Gradient(colors: [gold.opacity(0.4 * (1 - glow)), gold.opacity(0)]),
                                               center: crown, startRadius: 0, endRadius: radius))
        }
    }
}

// MARK: - Shared sprites

nonisolated extension WateringEffectPainter {

    /// The teal-zinc can's paint (C9 #1).
    static let canBody = GardenRGB(0x5E8C8A)
    static let canShade = GardenRGB(0x4A7270)
    static let canLight = GardenRGB(0x86B3B0)

    /// The rose (the sprinkler head) in the can's own units, where the body
    /// is 1 wide and centred on the origin. Drops leave from here.
    static let canRoseLocal = CGPoint(x: -1.02, y: -0.46)

    /// The can's transform: its body centre at `position`, `size` points
    /// wide, turned by `angle` (radians, clockwise positive). Unmirrored, the
    /// spout points left; mirrored (the partner's can), it points right.
    static func canTransform(position: CGPoint, size: CGFloat, angle: Double,
                             mirrored: Bool) -> CGAffineTransform {
        CGAffineTransform(translationX: position.x, y: position.y)
            .rotated(by: CGFloat(angle))
            .scaledBy(x: mirrored ? -size : size, y: size)
    }

    /// Where the can's rose is on screen for a pose.
    static func canRose(position: CGPoint, size: CGFloat, angle: Double, mirrored: Bool) -> CGPoint {
        canRoseLocal.applying(canTransform(position: position, size: size, angle: angle, mirrored: mirrored))
    }

    /// A watering can: rounded-trapezoid body, tapered spout, arc handle and
    /// a rose with five holes. Also used, upright, by the resting cans.
    static func drawCanSprite(in context: GraphicsContext, position: CGPoint, size: CGFloat,
                              angle: Double, mirrored: Bool, opacity: Double) {
        guard opacity > 0.01 else { return }
        var c = context
        c.opacity *= opacity
        c.concatenate(canTransform(position: position, size: size, angle: angle, mirrored: mirrored))

        // Handle: an arc from the top of the body over to its back.
        var handle = Path()
        handle.move(to: CGPoint(x: 0.02, y: -0.36))
        handle.addCurve(to: CGPoint(x: 0.46, y: 0.06),
                        control1: CGPoint(x: 0.10, y: -0.80),
                        control2: CGPoint(x: 0.78, y: -0.46))
        c.stroke(handle, with: .color(canShade.color), style: StrokeStyle(lineWidth: 0.09, lineCap: .round))

        // Spout: tapering from the body's lower front up to the rose.
        var spout = Path()
        spout.move(to: CGPoint(x: -0.36, y: 0.00))
        spout.addLine(to: CGPoint(x: -0.94, y: -0.40))
        spout.addLine(to: CGPoint(x: -0.98, y: -0.33))
        spout.addLine(to: CGPoint(x: -0.42, y: 0.24))
        spout.closeSubpath()
        c.fill(spout, with: .color(canShade.color))

        // Rose and its five holes.
        let rose = CGRect(x: canRoseLocal.x - 0.09, y: canRoseLocal.y - 0.09, width: 0.18, height: 0.18)
        c.fill(Path(ellipseIn: rose), with: .color(canBody.color))
        var holes = Path()
        for i in 0..<5 {
            let angle = Double(i) / 5 * 2 * .pi
            let p = CGPoint(x: canRoseLocal.x + 0.05 * CGFloat(cos(angle)),
                            y: canRoseLocal.y + 0.05 * CGFloat(sin(angle)))
            holes.addEllipse(in: CGRect(x: p.x - 0.014, y: p.y - 0.014, width: 0.028, height: 0.028))
        }
        c.fill(holes, with: .color(canShade.color))

        // Body: a rounded trapezoid, wider at the base.
        var body = Path()
        body.move(to: CGPoint(x: -0.36, y: -0.39))
        body.addLine(to: CGPoint(x: 0.36, y: -0.39))
        body.addQuadCurve(to: CGPoint(x: 0.44, y: -0.30), control: CGPoint(x: 0.42, y: -0.39))
        body.addLine(to: CGPoint(x: 0.50, y: 0.30))
        body.addQuadCurve(to: CGPoint(x: 0.40, y: 0.39), control: CGPoint(x: 0.51, y: 0.39))
        body.addLine(to: CGPoint(x: -0.40, y: 0.39))
        body.addQuadCurve(to: CGPoint(x: -0.50, y: 0.30), control: CGPoint(x: -0.51, y: 0.39))
        body.addLine(to: CGPoint(x: -0.44, y: -0.30))
        body.addQuadCurve(to: CGPoint(x: -0.36, y: -0.39), control: CGPoint(x: -0.42, y: -0.39))
        body.closeSubpath()
        c.fill(body, with: .linearGradient(Gradient(colors: [canLight.color, canBody.color, canShade.color]),
                                           startPoint: CGPoint(x: -0.5, y: 0), endPoint: CGPoint(x: 0.5, y: 0)))
        // Rim and a soft highlight.
        c.fill(Path(CGRect(x: -0.38, y: -0.42, width: 0.76, height: 0.07)), with: .color(canShade.color))
        c.fill(Path(roundedRect: CGRect(x: -0.26, y: -0.28, width: 0.08, height: 0.52), cornerRadius: 0.04),
               with: .color(.white.opacity(0.28)))
    }

    /// Water drops are 2 × 6 pt capsules along their velocity.
    static func addDrop(to path: inout Path, at point: CGPoint, velocity: CGVector,
                        width: CGFloat = 2, length: CGFloat = 6) {
        let angle = atan2(velocity.dy, velocity.dx) - .pi / 2
        let rect = CGRect(x: -width / 2, y: -length / 2, width: width, height: length)
        let transform = CGAffineTransform(translationX: point.x, y: point.y).rotated(by: angle)
        path.addPath(Path(roundedRect: rect, cornerRadius: width / 2), transform: transform)
    }

    /// A straight streak of rain, `slant` radians off vertical.
    static func addStreak(to path: inout Path, at point: CGPoint, width: CGFloat, length: CGFloat,
                          slant: CGFloat) {
        let rect = CGRect(x: -width / 2, y: -length / 2, width: width, height: length)
        let transform = CGAffineTransform(translationX: point.x, y: point.y).rotated(by: -slant)
        path.addPath(Path(roundedRect: rect, cornerRadius: width / 2), transform: transform)
    }

    /// A four-point star.
    static func addGlint(to path: inout Path, center c: CGPoint, radius r: CGFloat) {
        guard r > 0.1 else { return }
        let w = r * 0.26
        path.move(to: CGPoint(x: c.x, y: c.y - r))
        path.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + w, y: c.y - w))
        path.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x + w, y: c.y + w))
        path.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - w, y: c.y + w))
        path.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x - w, y: c.y - w))
        path.closeSubpath()
    }

    /// `count` glints popping on the canopy `stagger` apart from `start`,
    /// each growing and shrinking over `life`.
    static func drawCanopyGlints(in context: GraphicsContext, anchors a: TreeCanvasAnchors, seed: UInt64,
                                 count: Int, time t: Double, start: Double, stagger: Double, life: Double,
                                 salt: UInt64) {
        var glints = Path()
        for i in 0..<count {
            let age = t - (start + Double(i) * stagger)
            guard age >= 0, age < life else { continue }
            let point = pointInCanopy(a, seed: seed, index: i, salt: salt)
            let radius = CGFloat(sin(.pi * age / life)) * (3.5 + 2.5 * CGFloat(unit(seed, i, salt &+ 7)))
            addGlint(to: &glints, center: point, radius: radius)
        }
        context.fill(glints, with: .color(GardenRGB(0xFFFBEA).color.opacity(0.95)))
    }

    /// A seeded point inside the canopy's circle (uniform over its area).
    static func pointInCanopy(_ a: TreeCanvasAnchors, seed: UInt64, index: Int, salt: UInt64,
                              spread: CGFloat = 0.85) -> CGPoint {
        let angle = unit(seed, index, salt) * 2 * .pi
        let radius = CGFloat(unit(seed, index, salt &+ 1).squareRoot()) * a.canopyRadius * spread
        return CGPoint(x: a.canopyCenter.x + radius * CGFloat(cos(angle)),
                       y: a.canopyCenter.y + radius * CGFloat(sin(angle)))
    }

    /// A teardrop, pointed at the top.
    static func teardrop(center c: CGPoint, width: CGFloat, height: CGFloat) -> Path {
        var p = Path()
        let r = width / 2
        let bottom = c.y + height / 2
        let circleCenterY = bottom - r
        p.move(to: CGPoint(x: c.x, y: c.y - height / 2))
        p.addQuadCurve(to: CGPoint(x: c.x + r, y: circleCenterY),
                       control: CGPoint(x: c.x + r * 0.9, y: c.y - height * 0.05))
        p.addArc(center: CGPoint(x: c.x, y: circleCenterY), radius: r,
                 startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - height / 2),
                       control: CGPoint(x: c.x - r * 0.9, y: c.y - height * 0.05))
        p.closeSubpath()
        return p
    }

    /// The six rainbow colours, outermost first (C9 #2).
    static let rainbowColors: [GardenRGB] = [
        GardenRGB(0xFF6B6B), GardenRGB(0xFFB86B), GardenRGB(0xFFE66B),
        GardenRGB(0x7EDC8B), GardenRGB(0x6BB8FF), GardenRGB(0xB48BFF)
    ]

    /// The rainbow's radius: clear of the canopy (centred on the trunk base,
    /// it passes 10 pt outside the canopy's circle) but inside the band.
    static func rainbowRadius(_ a: TreeCanvasAnchors) -> CGFloat {
        let clear = (a.trunkBase.y - a.canopyCenter.y) + a.canopyRadius + 10
        return max(a.canopyRadius, min(clear, a.trunkBase.y - 6))
    }

    /// Six 2.2 pt arcs from 200° to 340° around the trunk base. With
    /// `darkness` above 0.5 it is a single silver moonbow at 35% of `alpha`'s
    /// scale instead (`alpha` is the day rainbow's opacity).
    static func drawRainbow(in context: GraphicsContext, anchors a: TreeCanvasAnchors, alpha: Double,
                            darkness: Double) {
        guard alpha > 0.005 else { return }
        let center = a.trunkBase
        let outer = rainbowRadius(a)
        let style = StrokeStyle(lineWidth: 2.2, lineCap: .round)
        if darkness > 0.5 {
            var arc = Path()
            arc.addArc(center: center, radius: outer - 6, startAngle: .degrees(200), endAngle: .degrees(340),
                       clockwise: false)
            context.stroke(arc, with: .color(GardenRGB(0xE6ECF5).color.opacity(alpha * 0.35 / 0.55)),
                           style: StrokeStyle(lineWidth: 3, lineCap: .round))
            return
        }
        for (i, rgb) in rainbowColors.enumerated() {
            var arc = Path()
            arc.addArc(center: center, radius: outer - CGFloat(i) * 2.2, startAngle: .degrees(200),
                       endAngle: .degrees(340), clockwise: false)
            context.stroke(arc, with: .color(rgb.color.opacity(alpha)), style: style)
        }
    }

    /// The effect's water: `#8FD3FF` 90% by day, `#CFE3FF` at night.
    static func waterColor(_ sky: GardenSkyState) -> GardenRGB {
        GardenRGB(0x8FD3FF).mixed(with: GardenRGB(0xCFE3FF), sky.darkness)
    }

    /// A soft darkening of the soil bed while it drinks; the tree canvas's
    /// own wet soil takes over once the effect ends.
    static func drawSoakingSoil(in context: GraphicsContext, anchors a: TreeCanvasAnchors, moisture: Double) {
        guard moisture > 0.01 else { return }
        let rect = a.soilRect.insetBy(dx: -2, dy: -1)
        context.fill(Path(ellipseIn: rect),
                     with: .radialGradient(Gradient(colors: [GardenRGB(0x5A3E2B).color.opacity(0.45 * moisture),
                                                             GardenRGB(0x5A3E2B).color.opacity(0)]),
                                           center: CGPoint(x: rect.midX, y: rect.midY),
                                           startRadius: 0, endRadius: rect.width / 2))
    }
}

// MARK: - Analytic particle math

nonisolated extension WateringEffectPainter {

    /// A deterministic value in 0..<1 for (seed, particle, property):
    /// SplitMix64 over the three, so every particle and every property of it
    /// has its own stable random number with no stored state.
    static func unit(_ seed: UInt64, _ index: Int, _ salt: UInt64) -> Double {
        var z = seed &+ UInt64(truncatingIfNeeded: index) &* 0x9E37_79B9_7F4A_7C15
        z = z &+ (salt &+ 1) &* 0xD1B5_4A32_D192_ED03
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(UInt64(1) << 53)
    }

    /// `unit` scaled to lo...hi.
    static func value(_ seed: UInt64, _ index: Int, _ salt: UInt64, _ lo: Double, _ hi: Double) -> Double {
        lo + (hi - lo) * unit(seed, index, salt)
    }

    /// p(t) = p0 + v·t + ½·g·t² (g pulls down, points per second squared).
    static func ballistic(_ p0: CGPoint, _ v: CGVector, gravity g: CGFloat, age t: Double) -> CGPoint {
        let t = CGFloat(t)
        return CGPoint(x: p0.x + v.dx * t, y: p0.y + v.dy * t + 0.5 * g * t * t)
    }

    /// The time a body launched at `y0` with vertical speed `vy` reaches `y`.
    static func timeToFall(from y0: CGFloat, to y: CGFloat, vy: CGFloat, gravity g: CGFloat) -> Double {
        guard g > 0 else { return vy > 0 ? Double((y - y0) / vy) : .infinity }
        let disc = vy * vy + 2 * g * (y - y0)
        guard disc >= 0 else { return .infinity }
        return Double((-vy + disc.squareRoot()) / g)
    }

    static func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }

    /// 0…1 progress of `t` through start...end.
    static func progress(_ t: Double, _ start: Double, _ end: Double) -> Double {
        clamp01((t - start) / (end - start))
    }

    static func easeOutCubic(_ x: Double) -> Double { let u = 1 - clamp01(x); return 1 - u * u * u }
    static func easeInCubic(_ x: Double) -> Double { let u = clamp01(x); return u * u * u }
    static func easeInOut(_ x: Double) -> Double { 0.5 - 0.5 * cos(.pi * clamp01(x)) }

    /// easeOutBack: overshoots past 1 and settles.
    static func easeOutBack(_ x: Double, overshoot s: Double = 1.70158) -> Double {
        let u = clamp01(x) - 1
        return 1 + (s + 1) * u * u * u + s * u * u
    }

    /// A damped spring's step response from 0 to 1 (SwiftUI's
    /// `.spring(response:dampingFraction:)`), 0 before `t` = 0.
    static func spring(_ t: Double, response: Double, damping: Double) -> Double {
        guard t > 0 else { return 0 }
        let omega = 2 * .pi / response
        let zeta = min(0.999, damping)
        let omegaD = omega * (1 - zeta * zeta).squareRoot()
        let decay = exp(-zeta * omega * t)
        return 1 - decay * (cos(omegaD * t) + (zeta * omega / omegaD) * sin(omegaD * t))
    }

    /// 0 → 1 → 0 over start...end (a fade in and out).
    static func pulse(_ t: Double, _ start: Double, _ end: Double) -> Double {
        let p = (t - start) / (end - start)
        guard p > 0, p < 1 else { return 0 }
        return sin(.pi * p)
    }

    /// Opacity that rises over `fadeIn` from `start` and falls over
    /// `fadeOut` before `end`.
    static func envelope(_ t: Double, start: Double, end: Double, fadeIn: Double, fadeOut: Double) -> Double {
        guard t > start, t < end else { return 0 }
        return min(clamp01((t - start) / fadeIn), clamp01((end - t) / fadeOut))
    }
}
