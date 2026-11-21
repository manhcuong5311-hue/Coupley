//
//  MountainLakeScene.swift
//  Coupley
//
//  Our Garden, P5 (Scenes I): Mountain Lake (C4 scene 4; national parks,
//  hiking, skiing, climbing, campgrounds). Three snow-capped peaks above
//  rows of pines and a still lake that mirrors them, a dock and rocks on the
//  near shore; the tree stands on the shore knoll at (0.66, 0.86).
//

import CoreGraphics
import SwiftUI

nonisolated struct MountainLakeScene: GardenScenePainting {
    init() {}

    var scene: GardenSceneID { .mountainLake }

    private typealias Kit = GardenSceneKit

    private static let peaks = [CGPoint(x: 0.18, y: 0.20), CGPoint(x: 0.46, y: 0.14), CGPoint(x: 0.80, y: 0.24)]
    private static let mountainBase: CGFloat = 0.56
    private static let lakeTop: CGFloat = 0.60
    /// High under the dock at the left (0.84), low under the knoll (≈ 0.93),
    /// so the dock rests on it and the knoll rises out of it.
    private static let shore = (base: CGFloat(0.93), amplitude: CGFloat(0.09), frequency: CGFloat(0.75), phase: CGFloat(1.194))
    private static let knollHalfWidth: CGFloat = 0.30

    private var apex: CGPoint { scene.info.layout.knollApex }

    /// The range's silhouette: three peaks with concave flanks, closed along
    /// the band's bottom, across the far layer's full width.
    private static func range(in size: CGSize) -> Path {
        let span = Kit.farSpan(in: size)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { Kit.point(x, y, in: size) }
        let left = CGPoint(x: span.lowerBound, y: size.height * 0.48)
        let right = CGPoint(x: span.upperBound, y: size.height * 0.46)
        let ridge = [left, p(peaks[0].x, peaks[0].y), p(0.32, 0.40), p(peaks[1].x, peaks[1].y),
                     p(0.63, 0.42), p(peaks[2].x, peaks[2].y), right]
        var path = Path()
        path.move(to: CGPoint(x: span.lowerBound, y: size.height))
        path.addLine(to: left)
        for (a, b) in zip(ridge, ridge.dropFirst()) {
            // Scooped flanks: the control sits near the lower end's level.
            let (high, low) = a.y < b.y ? (a, b) : (b, a)
            let control = CGPoint(x: high.x * 0.35 + low.x * 0.65, y: high.y * 0.25 + low.y * 0.75)
            path.addQuadCurve(to: b, control: control)
        }
        path.addLine(to: CGPoint(x: span.upperBound, y: size.height))
        path.closeSubpath()
        return path
    }

    /// The snow on each peak: its top `share` of the height, with a jagged edge.
    private static func snowCaps(on range: Path, in size: CGSize, share: CGFloat) -> Path {
        var rng = GardenSceneRandom(seed: Kit.seed(GardenSceneStyle.staticSeed(for: .mountainLake), 0x5C0))
        var region = Path()
        for peak in peaks {
            let line = peak.y + share * (mountainBase - peak.y)
            let left = peak.x - 0.24, right = peak.x + 0.24
            region.move(to: Kit.point(left, peak.y - 0.06, in: size))
            region.addLine(to: Kit.point(right, peak.y - 0.06, in: size))
            region.addLine(to: Kit.point(right, line, in: size))
            var x = right
            var down = true
            while x > left {
                x -= 0.022
                region.addLine(to: Kit.point(x, line + (down ? 0.016 : -0.004) + CGFloat(rng.next(-0.005...0.005)), in: size))
                down.toggle()
            }
            region.closeSubpath()
        }
        return range.intersection(region)
    }

    // MARK: Static layers

    func drawLayer(_ layer: GardenBackdropLayer, in context: GraphicsContext, size: CGSize, style: GardenSceneStyle) {
        guard size.width > 0, size.height > 0 else { return }
        switch layer {
        case .far:   drawMountains(in: context, size: size, style: style)
        case .near:  drawNear(in: context, size: size, style: style)
        case .front: drawFront(in: context, size: size, style: style)
        }
    }

    /// The peaks, their shaded east flanks and their snow caps.
    private func drawMountains(in context: GraphicsContext, size: CGSize, style: GardenSceneStyle) {
        let variant = style.variant
        let rock = Kit.rgb(0x8A9BB0, 0x222B40, variant)
        let range = Self.range(in: size)
        context.fill(range, with: .color(rock.color))
        var shadows = Path()
        for peak in Self.peaks {
            shadows.move(to: Kit.point(peak.x, peak.y, in: size))
            shadows.addLine(to: Kit.point(peak.x + 0.22, Self.lakeTop + 0.02, in: size))
            shadows.addLine(to: Kit.point(peak.x + 0.03, Self.lakeTop + 0.02, in: size))
            shadows.closeSubpath()
        }
        context.fill(shadows.intersection(range), with: .color(Kit.scaled(rock, 0.86).color))
        let caps = Self.snowCaps(on: range, in: size, share: style.season.hasSnow ? 0.55 : 0.35)
        context.fill(caps, with: .color(Kit.color(0xF4F7FA, 0x9AA7C0, variant)))
    }

    private func drawNear(in context: GraphicsContext, size: CGSize, style: GardenSceneStyle) {
        let variant = style.variant, season = style.season
        let snowy = season.hasSnow
        let staticSeed = GardenSceneStyle.staticSeed(for: scene)

        // The far shore under the pines.
        context.fill(Path(CGRect(x: 0, y: size.height * 0.555, width: size.width, height: size.height * 0.06)),
                     with: .color(Kit.ground(Kit.rgb(0x3E6B4F, 0x122620, variant), season: season, variant: variant).color))

        drawLake(in: context, size: size, style: style)
        drawPines(in: context, size: size, style: style)

        // The near shore and the knoll.
        let s = Self.shore
        let shore = Kit.hills(in: size, base: s.base, amplitude: s.amplitude, frequency: s.frequency, phase: s.phase)
        let knoll = Kit.knoll(in: size, apex: apex, halfWidth: Self.knollHalfWidth)
        let grass = Kit.ground(Kit.rgb(0x5F8F57, 0x18301F, variant), season: season, variant: variant)
        context.fill(shore, with: .color(Kit.scaled(grass, 0.92).color))
        context.fill(knoll, with: .color(grass.color))
        if !snowy { Kit.drawRim(on: knoll, thickness: 2.5, color: Kit.scaled(grass, variant == .day ? 1.2 : 1.4), in: context) }
        if snowy {
            Kit.drawSnow(on: shore, depth: size.height * 0.05, in: context, variant: variant)
            Kit.drawSnow(on: knoll, depth: size.height * 0.06, in: context, variant: variant)
        }

        drawDock(in: context, size: size, variant: variant)

        // Three grey rocks.
        let stone = Kit.rgb(0x9AA0A6, 0x2C3138, variant)
        for (x, y, r) in [(CGFloat(0.40), CGFloat(0.865), CGFloat(6)), (0.455, 0.88, 4), (0.93, 0.93, 5)] {
            let c = Kit.point(x, y, in: size)
            context.fill(Path(ellipseIn: CGRect(x: c.x - r * 1.3, y: c.y - r, width: r * 2.6, height: r * 1.6)),
                         with: .color(stone.color))
            context.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.8, y: c.y - r * 0.9, width: r * 1.2, height: r * 0.5)),
                         with: .color(Kit.scaled(stone, snowy ? 1.35 : 1.15).color))
        }
        Kit.drawGroundDetails(in: context, rect: CGRect(x: size.width * 0.02, y: size.height * 0.90,
                                                        width: size.width * 0.96, height: size.height * 0.08),
                              season: season, variant: variant, seed: staticSeed)
    }

    /// The lake from 0.60 (running on under the near shore), holding a 30%
    /// mirror of the peaks; frozen with cracks in winter.
    private func drawLake(in context: GraphicsContext, size: CGSize, style: GardenSceneStyle) {
        let variant = style.variant
        let frozen = style.season.hasSnow
        let lake = CGRect(x: 0, y: size.height * Self.lakeTop, width: size.width, height: size.height * (0.90 - Self.lakeTop))
        if frozen {
            Kit.fillVertical(Path(lake), in: context, top: Kit.rgb(0xDDE8EF, 0x3A4A5E, variant), bottom: Kit.rgb(0xC9D6E2, 0x2E3C4E, variant))
        } else {
            Kit.fillVertical(Path(lake), in: context, top: Kit.rgb(0x5E9CB8, 0x0F2638, variant), bottom: Kit.rgb(0x8CC2D4, 0x17344A, variant))
        }
        var mirror = context
        mirror.clip(to: Path(lake))
        mirror.opacity = frozen ? 0.12 : 0.24
        mirror.translateBy(x: 0, y: 2 * size.height * Self.lakeTop)
        mirror.scaleBy(x: 1, y: -1)
        mirror.drawLayer { drawMountains(in: $0, size: size, style: style) }

        if frozen {
            var rng = GardenSceneRandom(seed: Kit.seed(GardenSceneStyle.staticSeed(for: scene), 0xC2AC))
            var cracks = Path()
            for _ in 0..<4 {
                var point = CGPoint(x: size.width * rng.next(0.05...0.45), y: size.height * rng.next(0.64...0.78))
                cracks.move(to: point)
                for _ in 0..<3 {
                    point = CGPoint(x: point.x + rng.next(6...16), y: point.y + rng.next(-3...3))
                    cracks.addLine(to: point)
                }
            }
            context.stroke(cracks, with: .color(.white.opacity(variant == .day ? 0.6 : 0.25)), lineWidth: 0.7)
        }
    }

    /// Two rows of pines on the far shore (24 + 18); in autumn 30% are gold
    /// larches, in winter their tips carry snow.
    private func drawPines(in context: GraphicsContext, size: CGSize, style: GardenSceneStyle) {
        let variant = style.variant
        var rng = GardenSceneRandom(seed: Kit.seed(GardenSceneStyle.staticSeed(for: scene), 0x9135))
        var shades = [Path(), Path(), Path()], snow = Path()
        let colors = [Kit.color(0x2F5D4A, 0x10231C, variant), Kit.color(0x3C6E57, 0x132A22, variant),
                      Kit.color(0xD8A23C, 0x3A3020, variant)]
        for (count, base, heights) in [(24, CGFloat(0.607), CGFloat(0.05)...CGFloat(0.07)), (18, 0.622, 0.07...0.10)] {
            let step = 1.04 / CGFloat(count)
            for i in 0..<count {
                let x = size.width * (-0.02 + (CGFloat(i) + rng.next(0.1...0.9)) * step)
                let height = size.height * rng.next(heights)
                let half = height * 0.24
                let y = size.height * base
                var pine = Path()
                pine.move(to: CGPoint(x: x - half, y: y))
                pine.addLine(to: CGPoint(x: x, y: y - height))
                pine.addLine(to: CGPoint(x: x + half, y: y))
                pine.closeSubpath()
                let larch = style.season == .autumn && rng.next() < 0.3
                shades[larch ? 2 : i % 2].addPath(pine)
                if style.season.hasSnow {
                    snow.move(to: CGPoint(x: x - half * 0.35, y: y - height * 0.65))
                    snow.addLine(to: CGPoint(x: x, y: y - height))
                    snow.addLine(to: CGPoint(x: x + half * 0.35, y: y - height * 0.65))
                    snow.closeSubpath()
                }
            }
        }
        for (path, color) in zip(shades, colors) where !path.isEmpty {
            context.fill(path, with: .color(color))
        }
        if !snow.isEmpty { context.fill(snow, with: .color(Kit.color(0xF4F7FA, 0x9AA7C0, variant))) }
    }

    /// A dock of five planks from (0.08, 0.86) out to (0.30, 0.80), on three posts.
    private func drawDock(in context: GraphicsContext, size: CGSize, variant: GardenSkyVariant) {
        let start = Kit.point(0.08, 0.86, in: size), end = Kit.point(0.30, 0.80, in: size)
        func along(_ t: CGFloat) -> CGPoint {
            CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
        }
        var posts = Path()
        for t in [CGFloat(0.2), 0.55, 0.9] {
            let p = along(t)
            posts.addRect(CGRect(x: p.x - 1, y: p.y, width: 2, height: 7))
        }
        context.fill(posts, with: .color(Kit.color(0x6E5238, 0x2C2219, variant)))
        var planks = Path()
        for i in 0..<5 {
            let a = along(CGFloat(i) / 5 + 0.01), b = along(CGFloat(i + 1) / 5 - 0.01)
            planks.move(to: CGPoint(x: a.x, y: a.y - 1.8))
            planks.addLine(to: CGPoint(x: b.x, y: b.y - 1.8))
            planks.addLine(to: CGPoint(x: b.x, y: b.y + 1.8))
            planks.addLine(to: CGPoint(x: a.x, y: a.y + 1.8))
            planks.closeSubpath()
        }
        context.fill(planks, with: .color(Kit.color(0x8C6B4A, 0x3B2E24, variant)))
    }

    /// Alpine grass and a rock edge along the bottom, tufts by the trunk.
    private func drawFront(in context: GraphicsContext, size: CGSize, style: GardenSceneStyle) {
        let variant = style.variant
        let seed = GardenSceneStyle.staticSeed(for: scene)
        var blade = Kit.ground(Kit.rgb(0x4F7F4A, 0x16291C, variant), season: style.season, variant: variant)
        if style.season.hasSnow { blade = blade.mixed(with: Kit.rgb(0xDCE6EF, 0x7D8AA6, variant), 0.45) }
        var grass = Kit.frontGrass(in: size, blades: 32, seed: Kit.seed(seed, 0xB1))
        for (i, dx) in [CGFloat(-0.075), 0.08].enumerated() {
            let x = apex.x + dx
            let top = Kit.knollTop(atX: x, apex: apex, halfWidth: Self.knollHalfWidth) ?? apex.y
            grass.addPath(Kit.tuft(at: Kit.point(x, top + 0.012, in: size), width: 13, height: 8, blades: 6,
                                   seed: Kit.seed(seed, UInt64(0x70 + i))))
        }
        context.fill(grass, with: .color(blade.color))

        let stone = Kit.rgb(0x8E959C, 0x262B31, variant)
        var stones = Path(), highlights = Path()
        for (x, w, h) in [(CGFloat(0.03), CGFloat(14), CGFloat(7)), (0.13, 10, 5), (0.47, 16, 8), (0.84, 12, 6), (0.96, 15, 7)] {
            let rect = CGRect(x: size.width * x - w / 2, y: size.height - h * 0.8, width: w, height: h)
            stones.addRoundedRect(in: rect, cornerSize: CGSize(width: h * 0.45, height: h * 0.45))
            highlights.addRoundedRect(in: CGRect(x: rect.minX + w * 0.2, y: rect.minY + 1, width: w * 0.45, height: 1.6),
                                      cornerSize: CGSize(width: 0.8, height: 0.8))
        }
        context.fill(stones, with: .color(stone.color))
        context.fill(highlights, with: .color(Kit.scaled(stone, style.season.hasSnow ? 1.45 : 1.2).color))
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
            drawPeakCloud(in: context, size: size, state: state, time: time)
        case .front:
            if !state.season.hasSnow { drawShimmer(in: context, size: size, state: state, time: time) }
            Kit.drawSeasonParticles(in: context, size: size, state: state, maxCount: 24)
        }
    }

    /// One cloud drifting slowly across the peaks, in front of the far layer.
    private func drawPeakCloud(in context: GraphicsContext, size: CGSize, state: GardenAmbientState, time: TimeInterval?) {
        var rng = GardenSceneRandom(seed: Kit.seed(state.seed, 0xC10E))
        let width: CGFloat = 64
        let lap = size.width + width * 2
        let x = (CGFloat(rng.next()) * lap + 3 * CGFloat(time ?? 0)).truncatingRemainder(dividingBy: lap) - width
        let tone = Kit.blend(0xFFFFFF, 0x9AA5C7, darkness: state.sky.darkness)
        let alpha = 0.7 - 0.4 * state.sky.darkness
        context.fill(Kit.cloud(x: x, baseY: size.height * 0.27, width: width), with: .color(tone.color.opacity(alpha)))
    }

    /// Six shimmer lines on the open water left of the tree, in two phase groups.
    private func drawShimmer(in context: GraphicsContext, size: CGSize, state: GardenAmbientState, time: TimeInterval?) {
        var rng = GardenSceneRandom(seed: Kit.seed(state.seed, 0x5419))
        let t = time ?? 0
        var groups = [Path(), Path()]
        for i in 0..<6 {
            let x = size.width * rng.next(0.04...0.36) + CGFloat(4 * sin(0.6 * t + Double(i)))
            let y = size.height * rng.next(0.64...0.77)
            groups[i % 2].addRect(CGRect(x: x, y: y, width: rng.next(10...22), height: 0.9))
        }
        let tone = Kit.blend(0xFFFFFF, 0xCFE3FF, darkness: state.sky.darkness).color
        for (i, group) in groups.enumerated() {
            let pulse = time == nil ? 0.35 : 0.3 + 0.15 * sin(1.3 * t + Double(i) * .pi)
            context.fill(group, with: .color(tone.opacity(pulse * (1 - 0.4 * state.sky.darkness))))
        }
    }

    // MARK: Watering accent

    /// A fish jumps out of the lake in an arc, with a ripple ring where it
    /// leaves the water and another where it dives back in.
    func drawWateringAccent(in context: GraphicsContext, size: CGSize, state: GardenAmbientState, progress: Double) {
        guard size.width > 0, size.height > 0 else { return }
        let p = min(1, max(0, progress))
        let water = Kit.blend(0xFFFFFF, 0xCFE3FF, darkness: state.sky.darkness).color
        let entry = Kit.point(0.26, 0.72, in: size), exit = Kit.point(0.34, 0.72, in: size)

        func ripple(at center: CGPoint, _ q: Double) {
            guard (0...1).contains(q) else { return }
            var rings = Path()
            for scale in [1.0, 0.55] {
                let r = CGFloat(2 + 14 * q * scale)
                rings.addEllipse(in: CGRect(x: center.x - r, y: center.y - r * 0.35, width: r * 2, height: r * 0.7))
            }
            context.stroke(rings, with: .color(water.opacity(0.6 * (1 - q))), lineWidth: 1)
        }
        ripple(at: entry, p / 0.5)
        ripple(at: exit, (p - 0.75) / 0.25)

        let u = (p - 0.1) / 0.7
        guard (0...1).contains(u) else { return }
        let x = entry.x + (exit.x - entry.x) * CGFloat(u)
        let y = entry.y - size.height * 0.09 * CGFloat(4 * u * (1 - u))
        let angle = atan2(-Double(size.height) * 0.09 * 4 * (1 - 2 * u), Double(exit.x - entry.x))
        var fish = Path(ellipseIn: CGRect(x: -3.5, y: -1.3, width: 7, height: 2.6))
        fish.move(to: CGPoint(x: -3, y: 0))
        fish.addLine(to: CGPoint(x: -6, y: -2))
        fish.addLine(to: CGPoint(x: -6, y: 2))
        fish.closeSubpath()
        context.fill(fish.applying(CGAffineTransform(translationX: x, y: y).rotated(by: CGFloat(angle))),
                     with: .color(Kit.blend(0xC9D6E2, 0x9AA7C0, darkness: state.sky.darkness).color))
    }
}

#Preview("Mountain Lake · day") {
    GardenSceneSketch(scene: .mountainLake, localHour: 9, season: .autumn)
        .frame(width: 351, height: 208)
        .border(Color.gray.opacity(0.4))
}

#Preview("Mountain Lake · night") {
    GardenSceneSketch(scene: .mountainLake, localHour: 23, season: .winter)
        .frame(width: 351, height: 208)
        .border(Color.gray.opacity(0.4))
}
