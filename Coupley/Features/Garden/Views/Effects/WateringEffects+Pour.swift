//
//  WateringEffects+Pour.swift
//  Coupley
//
//  P8: the pouring effects, `can` and `together` (spec C9 #1 and #5).
//  Times below are seconds into the effect (after the golden first drop,
//  when there is one); the tree's revival is drawn by the tree canvas from
//  `GardenEffect.reviveOffset`, not here.
//

import SwiftUI

nonisolated extension WateringEffectPainter {

    /// The can's tilt while pouring: −38°.
    static let pourTilt = -38 * Double.pi / 180
    /// Drops leave the rose at 26 per second.
    static let dropsPerSecond = 26.0

    /// A can about a sixth of the tree canvas wide (≈ 29 pt in the hero).
    static func pouringCanSize(_ a: TreeCanvasAnchors) -> CGFloat {
        max(22, a.unit * 0.16)
    }

    /// Where a tilted can's centre goes so that its rose sits at `rose`.
    static func canCenter(forRose rose: CGPoint, size: CGFloat, angle: Double, mirrored: Bool) -> CGPoint {
        let offset = canRose(position: .zero, size: size, angle: angle, mirrored: mirrored)
        return CGPoint(x: rose.x - offset.x, y: rose.y - offset.y)
    }

    /// The rose over the canopy's right shoulder (45° up its circle), where
    /// the hero's band still has sky above it for the can.
    static func shoulderRose(_ a: TreeCanvasAnchors) -> CGPoint {
        CGPoint(x: a.canopyCenter.x + a.canopyRadius * 0.78, y: a.canopyCenter.y - a.canopyRadius * 0.78 - 4)
    }

    /// Keeps a can of `size` inside the band.
    static func clampCan(_ p: CGPoint, size: CGFloat, in band: CGSize) -> CGPoint {
        let margin = size * 0.6
        return CGPoint(x: min(max(p.x, margin), band.width - margin),
                       y: min(max(p.y, margin), band.height - margin))
    }

    // MARK: - 1. Watering can (2.6 s)

    /// One can slides in from the top-right to the canopy's right shoulder,
    /// tilts, pours 26 drops a second onto the soil (each landing in a small
    /// splash with two bouncing droplets), tilts back and leaves; then eight
    /// glints pop on the canopy.
    static func drawCan(in context: GraphicsContext, frame: GardenEffectFrame) {
        let a = frame.anchors, t = frame.elapsed, seed = frame.playback.seed
        let size = pouringCanSize(a)
        let water = waterColor(frame.sky).color.opacity(0.9)

        let roseTarget = shoulderRose(a)
        let rest = clampCan(canCenter(forRose: roseTarget, size: size, angle: pourTilt, mirrored: false),
                            size: size, in: frame.size)
        let offstage = CGPoint(x: frame.size.width + size, y: -size)

        /// The can's pose at any time (drops read it at their spawn time).
        func pose(_ time: Double) -> (position: CGPoint, angle: Double) {
            let enter = easeOutCubic(time / 0.45)
            let leave = easeInCubic(progress(time, 2.0, 2.45))
            let position = CGPoint(x: offstage.x + (rest.x - offstage.x) * enter + (offstage.x - rest.x) * leave,
                                   y: offstage.y + (rest.y - offstage.y) * enter + (offstage.y - rest.y) * leave)
            let tilt = spring(time - 0.30, response: 0.3, damping: 0.6) * (1 - easeInCubic(progress(time, 2.0, 2.45)))
            return (position, pourTilt * tilt)
        }

        // Soil moisture 0 → 1 over 0.8–2.0, handing over to the tree's soil.
        drawSoakingSoil(in: context, anchors: a,
                        moisture: easeInOut(progress(t, 0.8, 2.0)) * (1 - progress(t, 2.2, 2.6)))

        // The pour, 0.55–2.0: drops, splashes and micro-droplets.
        let soilY = a.soilRect.midY
        let gravity: CGFloat = 900
        var drops = Path(), splashes = Path(), droplets = Path()
        let count = Int((2.0 - 0.55) * dropsPerSecond)
        for k in 0..<count {
            let spawn = 0.55 + Double(k) / dropsPerSecond
            guard t >= spawn else { break }
            let p = pose(spawn)
            let origin = canRose(position: p.position, size: size, angle: p.angle, mirrored: false)
            let v = CGVector(dx: value(seed, k, 1, -180, -120), dy: value(seed, k, 2, 10, 50))
            let landing = timeToFall(from: origin.y, to: soilY, vy: v.dy, gravity: gravity)
            let age = t - spawn
            if age < landing {
                addDrop(to: &drops, at: ballistic(origin, v, gravity: gravity, age: age),
                        velocity: CGVector(dx: v.dx, dy: v.dy + gravity * CGFloat(age)))
                continue
            }
            let since = age - landing
            guard since < 0.35 else { continue }
            let landed = CGPoint(x: origin.x + v.dx * CGFloat(landing), y: soilY)
            let grow = CGFloat(easeOutCubic(since / 0.35))
            splashes.addEllipse(in: CGRect(x: landed.x - 7 * grow, y: landed.y - 2 * grow,
                                           width: 14 * grow, height: 4 * grow))
            for side in 0..<2 {
                let bounce = CGVector(dx: (side == 0 ? -1 : 1) * value(seed, k, 3 + UInt64(side), 30, 60),
                                      dy: -value(seed, k, 5 + UInt64(side), 90, 140))
                let point = ballistic(landed, bounce, gravity: gravity, age: since)
                guard point.y <= landed.y else { continue }
                droplets.addEllipse(in: CGRect(x: point.x - 0.9, y: point.y - 0.9, width: 1.8, height: 1.8))
            }
        }
        context.fill(drops, with: .color(water))
        context.fill(droplets, with: .color(water))
        // One fill for every splash; they fade together as each is short-lived.
        context.fill(splashes, with: .color(water.opacity(0.45)))

        let p = pose(t)
        drawCanSprite(in: context, position: p.position, size: size, angle: p.angle, mirrored: false,
                      opacity: 1 - progress(t, 2.35, 2.45))

        // 2.0–2.6: eight glints, 50 ms apart.
        drawCanopyGlints(in: context, anchors: a, seed: seed, count: 8, time: t,
                         start: 2.0, stagger: 0.05, life: 0.25, salt: 20)
    }

    // MARK: - The ceremony's short pour (C8)

    /// The can is on screen for this long; its last drops land a little later.
    static let shortPourDuration: TimeInterval = 0.6

    /// The planting ceremony's first watering: the `can` effect's pour
    /// compressed into 0.6 s (in, tilt, a few drops, out), its drops landing
    /// in splashes on the soil by 1.0 s. `elapsed` is seconds since it began.
    static func drawShortPour(in context: GraphicsContext, anchors a: TreeCanvasAnchors, band: CGSize,
                              sky: GardenSkyState, elapsed t: Double, seed: UInt64) {
        guard t >= 0, t < 1.0 else { return }
        let size = pouringCanSize(a)
        let water = waterColor(sky).color.opacity(0.9)
        let roseTarget = shoulderRose(a)
        let rest = clampCan(canCenter(forRose: roseTarget, size: size, angle: pourTilt, mirrored: false),
                            size: size, in: band)
        let offstage = CGPoint(x: band.width + size, y: rest.y - size)

        func pose(_ time: Double) -> (position: CGPoint, angle: Double) {
            let travel = easeOutCubic(time / 0.12) - easeInCubic(progress(time, 0.45, shortPourDuration))
            let position = CGPoint(x: offstage.x + (rest.x - offstage.x) * travel,
                                   y: offstage.y + (rest.y - offstage.y) * travel)
            let tilt = spring(time - 0.05, response: 0.2, damping: 0.6) * (1 - easeInCubic(progress(time, 0.42, 0.55)))
            return (position, pourTilt * tilt)
        }

        let soilY = a.soilRect.midY
        let gravity: CGFloat = 900
        var drops = Path(), splashes = Path()
        let count = Int((0.45 - 0.12) * dropsPerSecond)
        for k in 0..<count {
            let spawn = 0.12 + Double(k) / dropsPerSecond
            guard t >= spawn else { break }
            let p = pose(spawn)
            let origin = canRose(position: p.position, size: size, angle: p.angle, mirrored: false)
            let v = CGVector(dx: value(seed, k, 110, -180, -120), dy: value(seed, k, 111, 10, 50))
            let landing = timeToFall(from: origin.y, to: soilY, vy: v.dy, gravity: gravity)
            let age = t - spawn
            if age < landing {
                addDrop(to: &drops, at: ballistic(origin, v, gravity: gravity, age: age),
                        velocity: CGVector(dx: v.dx, dy: v.dy + gravity * CGFloat(age)))
            } else if age - landing < 0.35 {
                let grow = CGFloat(easeOutCubic((age - landing) / 0.35))
                let x = origin.x + v.dx * CGFloat(landing)
                splashes.addEllipse(in: CGRect(x: x - 7 * grow, y: soilY - 2 * grow, width: 14 * grow, height: 4 * grow))
            }
        }
        context.fill(drops, with: .color(water))
        context.fill(splashes, with: .color(water.opacity(0.45)))

        if t < shortPourDuration {
            let p = pose(t)
            drawCanSprite(in: context, position: p.position, size: size, angle: p.angle, mirrored: false,
                          opacity: 1 - progress(t, 0.52, shortPourDuration))
        }
    }

    // MARK: - 5. Watered together (3.4 s)

    /// Two cans enter at once (the partner's from the left, mirrored), tilt,
    /// and pour two arcing streams that meet over the crown at ≈ 1.0 s in a
    /// heart-shaped splash; the cans leave, six hearts float up, and a soft
    /// rainbow rises to 40% and settles at 25% (the rainbow overlay keeps it
    /// for 24 h).
    static func drawTogether(in context: GraphicsContext, frame: GardenEffectFrame) {
        let a = frame.anchors, t = frame.elapsed, seed = frame.playback.seed
        let size = pouringCanSize(a)
        let water = waterColor(frame.sky).color.opacity(0.9)

        // The rainbow sits behind everything the effect draws.
        let rainbow = t < 2.6 ? 0.40 * easeInOut(progress(t, 2.0, 2.6))
                              : 0.40 - 0.15 * easeInOut(progress(t, 2.6, 3.4))
        drawRainbow(in: context, anchors: a, alpha: rainbow, darkness: frame.sky.darkness)

        let crown = CGPoint(x: a.canopyCenter.x, y: a.canopyCenter.y - a.canopyRadius * 0.92)
        let roseY = a.canopyCenter.y - a.canopyRadius * 0.75
        let restRight = clampCan(canCenter(forRose: CGPoint(x: a.canopyCenter.x + a.canopyRadius + 6, y: roseY),
                                           size: size, angle: pourTilt, mirrored: false),
                                 size: size, in: frame.size)
        let restLeft = clampCan(canCenter(forRose: CGPoint(x: a.canopyCenter.x - a.canopyRadius - 6, y: roseY),
                                          size: size, angle: -pourTilt, mirrored: true),
                                size: size, in: frame.size)

        /// A can's pose: `mirrored` is the partner's, from and back to the left.
        func pose(_ time: Double, mirrored: Bool) -> (position: CGPoint, angle: Double) {
            let rest = mirrored ? restLeft : restRight
            let offstage = CGPoint(x: mirrored ? -size : frame.size.width + size, y: -size)
            let enter = easeOutCubic(time / 0.5)
            let leave = easeInCubic(progress(time, 1.8, 2.4))
            let position = CGPoint(x: offstage.x + (rest.x - offstage.x) * (enter - leave),
                                   y: offstage.y + (rest.y - offstage.y) * (enter - leave))
            let tilt = spring(time - 0.4, response: 0.3, damping: 0.6) * (1 - easeInCubic(progress(time, 1.8, 2.2)))
            return (position, (mirrored ? -pourTilt : pourTilt) * tilt)
        }

        // 0.6–1.8: two streams, each drop flying 0.4 s from its rose to the crown.
        let flight = 0.4
        let gravity: CGFloat = 900
        var drops = Path()
        let perCan = Int((1.8 - 0.6) * dropsPerSecond)
        for side in 0..<2 {
            let mirrored = side == 0
            for k in 0..<perCan {
                let spawn = 0.6 + Double(k) / dropsPerSecond
                guard t >= spawn else { break }
                let age = t - spawn
                guard age < flight else { continue }
                let p = pose(spawn, mirrored: mirrored)
                let origin = canRose(position: p.position, size: size, angle: p.angle, mirrored: mirrored)
                let jitter = CGFloat(value(seed, k, 30 + UInt64(side), -3, 3))
                let target = CGPoint(x: crown.x + jitter, y: crown.y)
                let T = CGFloat(flight)
                let v = CGVector(dx: (target.x - origin.x) / T,
                                 dy: (target.y - origin.y - 0.5 * gravity * T * T) / T)
                addDrop(to: &drops, at: ballistic(origin, v, gravity: gravity, age: age),
                        velocity: CGVector(dx: v.dx, dy: v.dy + gravity * CGFloat(age)))
            }
        }
        context.fill(drops, with: .color(water))

        // Where the streams meet: a soft flash, then a glint while they pour.
        let meet = pulse(t, 0.95, 1.35)
        if meet > 0 {
            let r: CGFloat = 22
            context.fill(Path(ellipseIn: CGRect(x: crown.x - r, y: crown.y - r, width: r * 2, height: r * 2)),
                         with: .radialGradient(Gradient(colors: [Color.white.opacity(0.5 * meet), Color.white.opacity(0)]),
                                               center: crown, startRadius: 0, endRadius: r))
        }
        let sparkle = envelope(t, start: 1.0, end: 2.2, fadeIn: 0.1, fadeOut: 0.3)
        if sparkle > 0 {
            var glint = Path()
            addGlint(to: &glint, center: crown, radius: CGFloat(4 + 1.5 * sin(t * 18)) * CGFloat(sparkle))
            context.fill(glint, with: .color(GardenRGB(0xFFFBEA).color.opacity(0.9 * sparkle)))
        }

        // ≈ 1.0 s: 20 droplets launched along the heart curve, speed ∝ radius.
        let heartAge = t - 1.0
        if heartAge >= 0, heartAge < 0.9 {
            var heart = Path()
            for k in 0..<20 {
                let theta = Double(k) / 20 * 2 * .pi
                let s = sin(theta)
                let dx = 16 * s * s * s
                let dy = -(13 * cos(theta) - 5 * cos(2 * theta) - 2 * cos(3 * theta) - cos(4 * theta))
                let v = CGVector(dx: CGFloat(dx * 150 / 17), dy: CGFloat(dy * 150 / 17))
                let point = ballistic(crown, v, gravity: 500, age: heartAge)
                let r: CGFloat = 1.7
                heart.addEllipse(in: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2))
            }
            context.fill(heart, with: .color(water.opacity(1 - heartAge / 0.9)))
        }

        for side in 0..<2 {
            let mirrored = side == 0
            let p = pose(t, mirrored: mirrored)
            drawCanSprite(in: context, position: p.position, size: size, angle: p.angle, mirrored: mirrored,
                          opacity: 1 - progress(t, 2.3, 2.4))
        }

        // 2.0–3.4: six small hearts float up and fade.
        if t >= 2.0 {
            var symbol = context.resolve(Image(systemName: "heart.fill"))
            symbol.shading = .color(GardenRGB(0xFF6B8A).color)
            for k in 0..<6 {
                let spawn = 2.0 + Double(k) * 0.12
                let life = min(1.2, 3.4 - spawn)
                let age = t - spawn
                guard age >= 0, age < life else { continue }
                let x0 = a.canopyCenter.x + CGFloat(value(seed, k, 40, -0.8, 0.8)) * a.canopyRadius
                let y0 = a.canopyCenter.y - CGFloat(value(seed, k, 41, 0.1, 0.6)) * a.canopyRadius
                let side = CGFloat(value(seed, k, 42, 9, 13))
                let center = CGPoint(x: x0 + 5 * CGFloat(sin(2 * .pi * 0.8 * age + Double(k))),
                                     y: y0 - 28 * CGFloat(age))
                var c = context
                c.opacity = envelope(age, start: 0, end: life, fadeIn: 0.2, fadeOut: 0.5)
                c.draw(symbol, in: CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side))
            }
        }
    }
}
