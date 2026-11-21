//
//  WateringEffects+Sky.swift
//  Coupley
//
//  P8: the sky effects, `rainCloud`, `morningDew`, `moonlitDrizzle` and
//  `rainReturns` (spec C9 #2, #3, #4 and #6). Times below are seconds into
//  the effect; the tree's revival is drawn by the tree canvas.
//
//  Rain is a fixed set of streaks, each falling the same column over and
//  over: streak i's n-th fall starts at start + φᵢ + n·P (P = fall height /
//  speed), so its position is a pure function of the time and the streak
//  count on screen stays constant while it rains.
//

import SwiftUI

nonisolated extension WateringEffectPainter {

    /// tan(8°): rain falls 8° off vertical.
    private static let rainSlant: CGFloat = 0.1405

    /// One falling streak: where it is now, and the age of the previous
    /// fall's landing (for ground ripples).
    private struct StreakState {
        var point: CGPoint?
        var landedAge: Double?
        var landedX: CGFloat
    }

    /// Streak `i` of a rain from `top` to `bottom` at `speed`, spawning
    /// between `start` and `stop`.
    private static func streak(_ i: Int, seed: UInt64, salt: UInt64, time t: Double, start: Double, stop: Double,
                               x: CGFloat, top: CGFloat, bottom: CGFloat, speed: CGFloat) -> StreakState {
        let height = bottom - top
        let landedX = x - rainSlant * height
        guard height > 4 else { return StreakState(point: nil, landedAge: nil, landedX: landedX) }
        let period = Double(height / speed)
        let phase = unit(seed, i, salt) * period
        let n = ((t - start - phase) / period).rounded(.down)
        guard n >= 0 else { return StreakState(point: nil, landedAge: nil, landedX: landedX) }
        let spawn = start + phase + n * period
        let age = t - spawn
        var state = StreakState(point: nil, landedAge: nil, landedX: landedX)
        if spawn <= stop {
            let fall = speed * CGFloat(age)
            state.point = CGPoint(x: x - rainSlant * fall, y: top + fall)
        }
        if n >= 1, spawn - period <= stop { state.landedAge = age }
        return state
    }

    // MARK: - 2. Rain cloud (3.2 s)

    /// A cloud drifts in over the canopy and rains 40 slanted streaks to the
    /// ground (each landing in a small ripple), brightens and drifts away;
    /// a rainbow (a silver moonbow at night) rises behind the tree.
    static func drawRainCloud(in context: GraphicsContext, frame: GardenEffectFrame) {
        let a = frame.anchors, t = frame.elapsed, seed = frame.playback.seed
        let water = waterColor(frame.sky).color

        // 2.0–3.2: the rainbow, 0 → 55% → 0.
        drawRainbow(in: context, anchors: a, alpha: 0.55 * pulse(t, 2.0, 3.2), darkness: frame.sky.darkness)

        let rest = CGPoint(x: a.canopyCenter.x, y: max(34, a.canopyCenter.y - a.canopyRadius - 22))
        let enter = easeOutCubic(t / 0.6)
        let leave = easeInCubic(progress(t, 2.0, 2.6))
        let cloudX = -70 + (rest.x + 70) * CGFloat(enter) + (frame.size.width + 140 - rest.x) * CGFloat(leave)
        let cloud = CGPoint(x: cloudX, y: rest.y)

        // 0.6–2.2: 40 streaks from the cloud's base to the ground line.
        var streaks = Path(), ripples = Path()
        for i in 0..<40 {
            let x = rest.x + CGFloat(value(seed, i, 50, -42, 52))
            let s = streak(i, seed: seed, salt: 51, time: t, start: 0.6, stop: 2.2,
                           x: x, top: rest.y + 10, bottom: a.groundY, speed: 560)
            if let point = s.point {
                addStreak(to: &streaks, at: point, width: 1.1, length: 11, slant: -rainSlant)
            }
            if let age = s.landedAge, age < 0.25 {
                let grow = CGFloat(easeOutCubic(age / 0.25))
                ripples.addEllipse(in: CGRect(x: s.landedX - 3 * grow, y: a.groundY - grow,
                                              width: 6 * grow, height: 2 * grow))
            }
        }
        context.fill(streaks, with: .color(water.opacity(0.55)))
        context.stroke(ripples, with: .color(water.opacity(0.5)), lineWidth: 0.8)

        // The cloud, brightening as it leaves.
        let night = frame.sky.darkness
        let bright = easeInOut(progress(t, 2.0, 2.6))
        let base = GardenRGB(0xFFFFFF).mixed(with: GardenRGB(0xAEB8D6), night)
        let alpha = 0.92 + (0.75 - 0.92) * night
        let glow = pulse(t, 2.0, 2.8)
        if glow > 0 {
            let r: CGFloat = 70
            context.fill(Path(ellipseIn: CGRect(x: cloud.x - r, y: cloud.y - r, width: r * 2, height: r * 2)),
                         with: .radialGradient(Gradient(colors: [Color.white.opacity(0.28 * glow), Color.white.opacity(0)]),
                                               center: cloud, startRadius: 0, endRadius: r))
        }
        drawCloud(in: context, at: cloud,
                  color: base.mixed(with: GardenRGB(0xFFFFFF), bright).color.opacity(min(1, alpha + 0.08 * bright)))
    }

    /// Five circles (r 14–22 pt) on a flat base; `center` is the base's middle.
    private static func drawCloud(in context: GraphicsContext, at center: CGPoint, color: Color) {
        var path = Path()
        let puffs: [(dx: CGFloat, r: CGFloat)] = [(-30, 14), (-13, 19), (6, 22), (25, 17), (40, 14)]
        for puff in puffs {
            let cy = center.y + 10 - puff.r * 0.95
            path.addEllipse(in: CGRect(x: center.x + puff.dx - puff.r, y: cy - puff.r,
                                       width: puff.r * 2, height: puff.r * 2))
        }
        path.addRoundedRect(in: CGRect(x: center.x - 44, y: center.y, width: 98, height: 11),
                            cornerSize: CGSize(width: 5.5, height: 5.5))
        context.fill(path, with: .color(color))
    }

    // MARK: - 3. Morning dew (2.4 s)

    /// A low mist rolls in along the ground, 18 dew beads bead up on the
    /// leaves under three soft god rays from the sun's side, every bead
    /// glints once, and the mist fades.
    static func drawMorningDew(in context: GraphicsContext, frame: GardenEffectFrame) {
        let a = frame.anchors, t = frame.elapsed, seed = frame.playback.seed
        let width = frame.size.width

        // 0–0.6 in, 1.8–2.4 out: three white mist ellipses at 25%.
        let mist = envelope(t, start: 0, end: 2.4, fadeIn: 0.6, fadeOut: 0.6)
        if mist > 0 {
            let roll = (1 - CGFloat(easeOutCubic(t / 0.6))) * width * 0.5
            let banks: [(x: CGFloat, w: CGFloat, h: CGFloat, dy: CGFloat)] = [
                (0.25, 0.55, 22, -4), (0.58, 0.45, 18, -10), (0.82, 0.50, 20, -2)
            ]
            for bank in banks {
                let center = CGPoint(x: width * bank.x - roll, y: a.groundY + bank.dy)
                let w = width * bank.w
                var c = context
                c.translateBy(x: center.x, y: center.y)
                c.scaleBy(x: 1, y: bank.h / w)
                c.fill(Path(ellipseIn: CGRect(x: -w / 2, y: -w / 2, width: w, height: w)),
                       with: .radialGradient(Gradient(colors: [Color.white.opacity(0.25 * mist), Color.white.opacity(0)]),
                                             center: .zero, startRadius: 0, endRadius: w / 2))
            }
        }

        // 0.4–1.6: three god rays from the sun's side, 12%.
        let rays = envelope(t, start: 0.4, end: 1.6, fadeIn: 0.4, fadeOut: 0.4)
        if rays > 0 {
            let sun = frame.sky.sun.map { CGPoint(x: $0.x * width, y: $0.y * frame.size.height) }
                ?? CGPoint(x: width * 0.12, y: frame.size.height * 0.2)
            let toTree = atan2(a.canopyCenter.y - sun.y, a.canopyCenter.x - sun.x)
            let length = hypot(a.canopyCenter.x - sun.x, a.canopyCenter.y - sun.y) + a.canopyRadius * 1.5
            for k in 0..<3 {
                let angle = toTree + (Double(k) - 1) * 0.16
                let spread = 0.05 + 0.02 * Double(k % 2)
                var ray = Path()
                ray.move(to: sun)
                ray.addLine(to: CGPoint(x: sun.x + length * CGFloat(cos(angle - spread)),
                                        y: sun.y + length * CGFloat(sin(angle - spread))))
                ray.addLine(to: CGPoint(x: sun.x + length * CGFloat(cos(angle + spread)),
                                        y: sun.y + length * CGFloat(sin(angle + spread))))
                ray.closeSubpath()
                let end = CGPoint(x: sun.x + length * CGFloat(cos(angle)), y: sun.y + length * CGFloat(sin(angle)))
                context.fill(ray, with: .linearGradient(Gradient(colors: [Color.white.opacity(0.12 * rays),
                                                                          Color.white.opacity(0)]),
                                                        startPoint: sun, endPoint: end))
            }
        }

        // 0.4–1.6: 18 beads bead up 50 ms apart; they fade as the tree's own dew takes over.
        var beads = Path(), highlights = Path(), glints = Path()
        let fade = 1 - progress(t, 2.2, 2.4)
        for k in 0..<18 {
            let born = 0.4 + Double(k) * 0.05
            guard t >= born else { break }
            let point = pointInCanopy(a, seed: seed, index: k, salt: 60, spread: 0.9)
            let r = 1.8 * CGFloat(easeOutBack(progress(t, born, born + 0.15)))
            beads.addEllipse(in: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2))
            highlights.addEllipse(in: CGRect(x: point.x - r * 0.55 - 0.6, y: point.y - r * 0.55 - 0.6,
                                             width: 1.2, height: 1.2))
            // 1.8–2.4: each bead glints once.
            let glintAge = t - (1.8 + Double(k) * 0.02)
            if glintAge >= 0, glintAge < 0.22 {
                addGlint(to: &glints, center: point, radius: 4.5 * CGFloat(sin(.pi * glintAge / 0.22)))
            }
        }
        context.fill(beads, with: .color(GardenRGB(0xF4FBFF).color.opacity(0.85 * fade)))
        context.fill(highlights, with: .color(Color.white.opacity(fade)))
        context.fill(glints, with: .color(GardenRGB(0xFFFBEA).color.opacity(0.95)))
    }

    // MARK: - 4. Moonlit drizzle (2.8 s)

    /// 26 fine silver streaks fall over the tree; then ten fireflies wake in
    /// the grass and float up, blinking.
    static func drawMoonlitDrizzle(in context: GraphicsContext, frame: GardenEffectFrame) {
        let a = frame.anchors, t = frame.elapsed, seed = frame.playback.seed

        // 0–2.0: 26 silver streaks (0.8 × 8 pt, 380 pt/s, 45%).
        var streaks = Path()
        let top = max(0, a.canopyCenter.y - a.canopyRadius - 50)
        for i in 0..<26 {
            let x = a.canopyCenter.x + CGFloat(value(seed, i, 70, -1.6, 1.6)) * a.canopyRadius
            let s = streak(i, seed: seed, salt: 71, time: t, start: 0, stop: 2.0,
                           x: x, top: top, bottom: a.groundY, speed: 380)
            if let point = s.point {
                addStreak(to: &streaks, at: point, width: 0.8, length: 8, slant: -rainSlant)
            }
        }
        context.fill(streaks, with: .color(GardenRGB(0xDCE6F5).color.opacity(0.45)))

        // 1.6–2.8: ten fireflies.
        guard t >= 1.6 else { return }
        var cores = Path()
        for k in 0..<10 {
            let born = 1.6 + Double(k) * 0.05
            let age = t - born
            guard age >= 0 else { break }
            let phase = unit(seed, k, 72) * 2 * .pi
            let x0 = a.trunkBase.x + CGFloat(value(seed, k, 73, -0.5, 0.5)) * a.unit
            let y0 = a.groundY - CGFloat(value(seed, k, 74, 0, 10))
            let point = CGPoint(x: x0 + 5 * CGFloat(sin(2 * .pi * 0.9 * age + phase)), y: y0 - 12 * CGFloat(age))
            let blink = 0.55 + 0.45 * sin(2 * .pi * 2.2 * age + phase)
            let alpha = blink * envelope(t, start: born, end: 2.8, fadeIn: 0.25, fadeOut: 0.3)
            guard alpha > 0.01 else { continue }
            let glow: CGFloat = 7
            context.fill(Path(ellipseIn: CGRect(x: point.x - glow, y: point.y - glow, width: glow * 2, height: glow * 2)),
                         with: .radialGradient(Gradient(colors: [GardenRGB(0xE9FF9A).color.opacity(0.5 * alpha),
                                                                 GardenRGB(0xE9FF9A).color.opacity(0)]),
                                               center: point, startRadius: 0, endRadius: glow))
            cores.addEllipse(in: CGRect(x: point.x - 1.4, y: point.y - 1.4, width: 2.8, height: 2.8))
        }
        context.fill(cores, with: .color(GardenRGB(0xF6FFB8).color.opacity(0.95)))
    }

    // MARK: - 6. The rain returns (3.2 s)

    /// After a week without water: the sky dims, a warm rain falls over the
    /// whole band, then the sky clears and a rainbow fades in and out.
    static func drawRainReturns(in context: GraphicsContext, frame: GardenEffectFrame) {
        let a = frame.anchors, t = frame.elapsed, seed = frame.playback.seed
        let rect = CGRect(origin: .zero, size: frame.size)

        // 0–0.6 dims to 25%; 2.0–3.2 clears.
        let dim = 0.25 * easeInOut(t / 0.6) * (1 - easeInOut(progress(t, 2.0, 3.2)))
        context.fill(Path(rect), with: .color(GardenRGB(0x3A4A5E).color.opacity(dim)))

        // 2.0–3.2: the rainbow to 40%, then out.
        drawRainbow(in: context, anchors: a, alpha: 0.40 * pulse(t, 2.0, 3.2), darkness: frame.sky.darkness)

        // 0.6–2.0: 60 warm streaks (260 pt/s) across the band.
        var streaks = Path()
        let warm = waterColor(frame.sky).mixed(with: GardenRGB(0xFFE2B8), 0.25)
        for i in 0..<60 {
            let x = CGFloat(value(seed, i, 80, 0, 1.08)) * frame.size.width
            let s = streak(i, seed: seed, salt: 81, time: t, start: 0.6, stop: 2.0,
                           x: x, top: -10, bottom: a.groundY + 6, speed: 260)
            if let point = s.point {
                addStreak(to: &streaks, at: point, width: 1, length: 10, slant: -rainSlant)
            }
        }
        context.fill(streaks, with: .color(warm.color.opacity(0.5)))
    }
}
