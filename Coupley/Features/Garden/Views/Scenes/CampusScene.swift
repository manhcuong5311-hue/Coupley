//
//  CampusScene.swift
//  Coupley
//
//  Our Garden, P6 (Scenes II): Campus (C4 scene 7). A brick hall with six
//  arched windows and a clock tower, two round trees, two lamp posts, and a
//  lawn knoll with a bench and two tiny books. The clock's hands show the
//  place's time; they are drawn in the behind pass, so the cached layers
//  stay static.
//
//  Shared helpers (ScenesIIBand, ScenesII) live in LanternTownScene.swift.
//

import CoreGraphics
import Foundation
import SwiftUI

nonisolated struct CampusScene: GardenScenePainting {
    init() {}

    var scene: GardenSceneID { .campus }

    // MARK: Layout (band fractions, C4)

    private static let apex = CGPoint(x: 0.64, y: 0.86)
    private static let knollHalfWidth: CGFloat = 0.30
    private static let horizon: CGFloat = 0.62
    private static let clockCenter = CGPoint(x: 0.30, y: 0.30)
    /// The clock face's radius in points (C4: r 7 pt).
    private static let clockRadius: CGFloat = 7
    /// The bell hangs in the belfry under the tower's pyramid roof.
    private static let bell = CGPoint(x: 0.30, y: 0.238)
    /// Each lamp post's foot.
    private static let lamps: [CGPoint] = [CGPoint(x: 0.13, y: 0.80), CGPoint(x: 0.535, y: 0.75)]
    private static let lampHeight: CGFloat = 0.16
    private static let windowCenters: [CGFloat] = [0.095, 0.16, 0.225, 0.385, 0.46, 0.535]
    /// Scene life besides the sky: two clock hands and two lamp glows.
    private static let particleBudget = ScenesII.particleBudget(sceneLife: 4)

    private static var staticSeed: UInt64 { GardenSceneStyle.staticSeed(for: .campus) }

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
            Self.drawLampGlows(in: context, band: band, state: state)
            Self.drawClockHands(in: context, band: band, state: state)
        case .front:
            GardenSceneKit.drawSeasonParticles(in: context, size: size, state: state, maxCount: Self.particleBudget)
        }
    }

    /// The tower bell rings: two arcs expand from the belfry on each side.
    func drawWateringAccent(in context: GraphicsContext, size: CGSize, state: GardenAmbientState, progress: Double) {
        let band = ScenesIIBand(size)
        let p = min(1, max(0, progress))
        let center = band.point(Self.bell.x, Self.bell.y)
        let ink = GardenSceneKit.blend(0xFFFFFF, 0xFFF4D6, darkness: state.sky.darkness).color
        for ring in 0..<2 {
            let u = (p - 0.15 * Double(ring)) / 0.7
            guard u > 0, u < 1 else { continue }
            let radius = band.pt(6 + 22 * CGFloat(u))
            for start in [150.0, -30.0] {
                var arc = Path()
                arc.addRelativeArc(center: center, radius: radius, startAngle: .degrees(start), delta: .degrees(60))
                context.stroke(arc, with: .color(ink.opacity(0.75 * (1 - u))), style: StrokeStyle(lineWidth: band.pt(1.6), lineCap: .round))
            }
        }
    }

    // MARK: Far: tree line, brick hall, clock tower

    private static func drawFar(in context: GraphicsContext, band: ScenesIIBand, style: GardenSceneStyle) {
        let variant = style.variant
        drawTreeLine(in: context, band: band, style: style)

        let brick = GardenSceneKit.rgb(0xB5654B, 0x3A2328, variant)
        let stone = GardenSceneKit.rgb(0xE8DCC8, 0x4A3A40, variant)
        let slate = GardenSceneKit.rgb(0x5B4A55, 0x241C24, variant)

        // The hall's slate roof, then its brick body, cornice and plinth.
        var roof = Path()
        roof.addLines([band.point(0.06, 0.425), band.point(0.09, 0.392), band.point(0.58, 0.392), band.point(0.61, 0.425)])
        roof.closeSubpath()
        context.fill(roof, with: .color(slate.color))
        let hall = band.rect(0.05, 0.42, 0.62, horizon + 0.006)
        context.fill(Path(hall), with: .color(brick.color))
        drawBrickwork(in: hall, context: context, band: band, brick: brick)
        let cornice = Path(band.rect(0.045, 0.415, 0.625, 0.43))
        context.fill(cornice, with: .color(stone.color))
        context.fill(Path(band.rect(0.05, 0.60, 0.62, horizon + 0.006)), with: .color(GardenSceneKit.color(0xD9CBB4, 0x33262C, variant)))

        // Six arched windows, lamplit at night, and the arched door under the tower.
        let frame = GardenSceneKit.rgb(0x5A3A34, 0x241418, variant)
        for x in windowCenters {
            let window = arch(centerX: x, bottom: 0.585, width: 0.036, height: 0.085, band: band)
            let bounds = window.boundingRect
            if variant == .night {
                GardenSceneKit.drawGlow(in: context, center: CGPoint(x: bounds.midX, y: bounds.midY), radius: band.pt(10),
                                        color: GardenRGB(0xFFD58A), opacity: 0.3)
                context.fill(window, with: .color(GardenRGB(0xFFD58A).color))
            } else {
                context.fill(window, with: .color(GardenRGB(0xC9D8E0).color))
            }
            var mullions = Path()
            mullions.move(to: CGPoint(x: bounds.midX, y: bounds.minY))
            mullions.addLine(to: CGPoint(x: bounds.midX, y: bounds.maxY))
            mullions.move(to: CGPoint(x: bounds.minX, y: bounds.minY + bounds.width / 2))
            mullions.addLine(to: CGPoint(x: bounds.maxX, y: bounds.minY + bounds.width / 2))
            context.stroke(window, with: .color(frame.color), lineWidth: band.pt(0.8))
            context.stroke(mullions, with: .color(frame.color), lineWidth: band.pt(0.6))
            context.fill(Path(CGRect(x: bounds.minX - band.pt(1), y: bounds.maxY, width: bounds.width + band.pt(2), height: band.pt(1.5))),
                         with: .color(stone.color))
        }
        let door = arch(centerX: clockCenter.x, bottom: horizon + 0.006, width: 0.045, height: 0.095, band: band)
        context.fill(door, with: .color(variant == .day ? frame.color : GardenRGB(0xFFC77A).color.opacity(0.85)))

        if style.season.hasSnow {
            GardenSceneKit.drawSnow(on: roof, depth: band.pt(2.2), in: context, variant: variant)
            GardenSceneKit.drawSnow(on: cornice, depth: band.pt(1.6), in: context, variant: variant)
        }
        drawTower(in: context, band: band, style: style, brick: brick, stone: stone, slate: slate)
    }

    /// Soft round crowns along the horizon, across the whole far canvas.
    private static func drawTreeLine(in context: GraphicsContext, band: ScenesIIBand, style: GardenSceneStyle) {
        var rng = GardenSceneRandom(seed: GardenSceneKit.seed(staticSeed, 5))
        var crowns = Path()
        var x: CGFloat = -0.22
        while x < 1.22 {
            let radius: CGFloat = rng.next(0.035...0.06)
            let center = band.point(x, horizon - radius * 0.5)
            let r = radius * band.height
            crowns.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
            x += rng.next(0.03...0.06)
        }
        crowns.addRect(band.rect(band.minX, horizon - 0.02, band.maxX, horizon + 0.01))
        var leaf = ScenesII.distant(GardenSceneKit.rgb(0x9CC39A, 0x18291F, style.variant), style, amount: 0.6)
        if style.season.hasSnow { leaf = leaf.mixed(with: ScenesII.snowBottom(style.variant), 0.5) }
        context.fill(crowns, with: .color(leaf.color.opacity(style.variant == .day ? 0.8 : 1)))
    }

    /// Mortar courses every 3 pt and staggered joints every 7 pt.
    private static func drawBrickwork(in rect: CGRect, context: GraphicsContext, band: ScenesIIBand, brick: GardenRGB) {
        var mortar = Path()
        let course = band.pt(3), length = band.pt(7)
        var y = rect.minY + course
        var row = 0
        while y < rect.maxY {
            mortar.move(to: CGPoint(x: rect.minX, y: y))
            mortar.addLine(to: CGPoint(x: rect.maxX, y: y))
            var x = rect.minX + (row.isMultiple(of: 2) ? 0 : length / 2)
            while x < rect.maxX {
                mortar.move(to: CGPoint(x: x, y: y - course))
                mortar.addLine(to: CGPoint(x: x, y: y))
                x += length
            }
            y += course
            row += 1
        }
        var clipped = context
        clipped.clip(to: Path(rect))
        clipped.stroke(mortar, with: .color(brick.mixed(with: GardenRGB(0xF0D8C8), 0.35).color.opacity(0.3)), lineWidth: band.pt(0.5))
    }

    /// A round-topped opening: the arch is two quad curves (small enough
    /// that they read as a semicircle).
    private static func arch(centerX: CGFloat, bottom: CGFloat, width: CGFloat, height: CGFloat, band: ScenesIIBand) -> Path {
        let rect = band.rect(centerX - width / 2, bottom - height, centerX + width / 2, bottom)
        let radius = rect.width / 2
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }

    /// The clock tower at x 0.30 (0.07 W wide, top 0.18): brick shaft with
    /// stone quoins, the clock face (its hands are ambient), the belfry, a
    /// pyramid roof and a finial.
    private static func drawTower(in context: GraphicsContext, band: ScenesIIBand, style: GardenSceneStyle,
                                  brick: GardenRGB, stone: GardenRGB, slate: GardenRGB) {
        let variant = style.variant
        let shaft = band.rect(0.265, 0.255, 0.335, 0.425)
        let shaftBrick = brick.mixed(with: GardenRGB(0xFFFFFF), variant == .day ? 0.08 : 0.03)
        context.fill(Path(shaft), with: .color(shaftBrick.color))
        drawBrickwork(in: shaft, context: context, band: band, brick: shaftBrick)
        let quoin = band.pt(2)
        context.fill(Path(CGRect(x: shaft.minX, y: shaft.minY, width: quoin, height: shaft.height)), with: .color(stone.color))
        context.fill(Path(CGRect(x: shaft.maxX - quoin, y: shaft.minY, width: quoin, height: shaft.height)), with: .color(stone.color))

        let face = band.point(clockCenter.x, clockCenter.y)
        let radius = band.pt(clockRadius)
        let faceRect = CGRect(x: face.x - radius, y: face.y - radius, width: radius * 2, height: radius * 2)
        if variant == .night {
            GardenSceneKit.drawGlow(in: context, center: face, radius: radius * 2, color: GardenRGB(0xFFE9B0), opacity: 0.35)
        }
        context.fill(Path(ellipseIn: faceRect), with: .color(GardenSceneKit.color(0xF6F1E1, 0xFFE9B0, variant)))
        context.stroke(Path(ellipseIn: faceRect), with: .color(slate.color), lineWidth: band.pt(1.2))
        var ticks = Path()
        for hour in 0..<12 {
            let angle = Double(hour) / 12 * 2 * .pi
            let direction = CGPoint(x: CGFloat(cos(angle)), y: CGFloat(sin(angle)))
            ticks.move(to: CGPoint(x: face.x + direction.x * radius * 0.74, y: face.y + direction.y * radius * 0.74))
            ticks.addLine(to: CGPoint(x: face.x + direction.x * radius * 0.9, y: face.y + direction.y * radius * 0.9))
        }
        context.stroke(ticks, with: .color(slate.color), lineWidth: band.pt(0.6))

        // The belfry: a stone band with an open arch and the bell inside.
        context.fill(Path(band.rect(0.26, 0.226, 0.34, 0.258)), with: .color(stone.color))
        context.fill(arch(centerX: bell.x, bottom: 0.254, width: 0.03, height: 0.026, band: band),
                     with: .color(GardenSceneKit.color(0x3A2A30, 0x120C10, variant)))
        let bellPoint = band.point(bell.x, bell.y)
        var bellShape = Path()
        bellShape.move(to: CGPoint(x: bellPoint.x - band.pt(2.4), y: bellPoint.y + band.pt(2.2)))
        bellShape.addQuadCurve(to: CGPoint(x: bellPoint.x + band.pt(2.4), y: bellPoint.y + band.pt(2.2)),
                               control: CGPoint(x: bellPoint.x, y: bellPoint.y - band.pt(4.4)))
        bellShape.closeSubpath()
        let gold = GardenSceneKit.color(0xC9A04A, 0x5A4A2A, variant)
        context.fill(bellShape, with: .color(gold))

        var roof = Path()
        roof.addLines([band.point(0.258, 0.228), band.point(0.30, 0.18), band.point(0.342, 0.228)])
        roof.closeSubpath()
        context.fill(roof, with: .color(slate.color))
        if style.season.hasSnow {
            GardenSceneKit.drawSnow(on: roof, depth: band.pt(2.2), in: context, variant: variant)
        }
        var finial = Path()
        finial.move(to: band.point(0.30, 0.18))
        finial.addLine(to: band.point(0.30, 0.165))
        context.stroke(finial, with: .color(slate.color), lineWidth: band.pt(1))
        let tip = band.point(0.30, 0.165)
        context.fill(Path(ellipseIn: CGRect(x: tip.x - band.pt(1.3), y: tip.y - band.pt(1.3), width: band.pt(2.6), height: band.pt(2.6))),
                     with: .color(gold))
    }

    // MARK: Near: lawn, path, trees, lamps, bench, knoll

    private static func drawNear(in context: GraphicsContext, band: ScenesIIBand, style: GardenSceneStyle) {
        let variant = style.variant
        ScenesII.fillGround(Path(band.rect(0, horizon, 1, 1.02)), in: context, band: band,
                            top: GardenSceneKit.rgb(0x79B566, 0x1C3424, variant),
                            bottom: GardenSceneKit.rgb(0x6AA65A, 0x172C1E, variant),
                            from: horizon, to: 1, style: style)
        GardenSceneKit.drawGroundDetails(in: context, rect: band.rect(0.56, 0.72, 0.98, 0.84), season: style.season,
                                         variant: variant, seed: staticSeed)

        // Steps down from the door, then stepping stones across the lawn.
        let step = GardenSceneKit.color(0xD9CBB4, 0x3A3436, variant)
        context.fill(Path(band.rect(0.28, horizon, 0.32, horizon + 0.008)), with: .color(step))
        context.fill(Path(band.rect(0.275, horizon + 0.008, 0.325, horizon + 0.016)), with: .color(step))
        var stones = Path()
        for index in 0..<7 {
            let t = CGFloat(index) / 6
            let center = band.point(0.30 - 0.15 * t - 0.03 * sin(.pi * t), 0.645 + 0.33 * pow(t, 1.15))
            let width = band.pt(6 + 10 * t), height = band.pt(2.4 + 3.6 * t)
            stones.addEllipse(in: CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height))
        }
        var paving = GardenSceneKit.rgb(0xCFC8BA, 0x3A3E3A, variant)
        if style.season.hasSnow { paving = paving.mixed(with: ScenesII.snowTop(variant), 0.6) }
        context.fill(stones, with: .color(paving.color))

        drawRoundTree(at: CGPoint(x: 0.75, y: 0.705), scale: 1, in: context, band: band, style: style)
        drawRoundTree(at: CGPoint(x: 0.90, y: 0.69), scale: 0.85, in: context, band: band, style: style)
        for lamp in lamps { drawLampPost(lamp, in: context, band: band, style: style) }
        drawBench(in: context, band: band, style: style)

        let knoll = GardenSceneKit.knoll(in: band.size, apex: apex, halfWidth: knollHalfWidth)
        fillKnoll(knoll, in: context, band: band, style: style)
        let rim = style.season.hasSnow ? ScenesII.snowTop(variant)
            : GardenSceneKit.ground(GardenSceneKit.rgb(0x9FD08A, 0x2A4A30, variant), season: style.season, variant: variant)
        GardenSceneKit.drawRim(on: knoll, thickness: band.pt(1), color: rim, in: context)
    }

    private static func fillKnoll(_ path: Path, in context: GraphicsContext, band: ScenesIIBand, style: GardenSceneStyle) {
        ScenesII.fillGround(path, in: context, band: band,
                            top: GardenSceneKit.rgb(0x84BE6E, 0x1F3828, style.variant),
                            bottom: GardenSceneKit.rgb(0x6AA65A, 0x172C1E, style.variant),
                            from: apex.y, to: 1, style: style)
    }

    /// A round tree on the lawn: green, autumn orange, or bare and snowy in
    /// a temperate winter.
    private static func drawRoundTree(at base: CGPoint, scale: CGFloat, in context: GraphicsContext, band: ScenesIIBand,
                                      style: GardenSceneStyle) {
        let variant = style.variant
        let bark = GardenSceneKit.rgb(0x6B4F3A, 0x1E1A16, variant)
        let root = band.point(base.x, base.y)
        let unit = band.height * scale
        let trunkTop = CGPoint(x: root.x, y: root.y - 0.07 * unit)
        var trunk = Path()
        trunk.move(to: root)
        trunk.addLine(to: trunkTop)
        context.stroke(trunk, with: .color(bark.color), style: StrokeStyle(lineWidth: band.pt(3.2 * scale), lineCap: .round))

        if style.season.hasSnow {
            var branches = Path(), snow = Path()
            let limbs: [(CGFloat, CGFloat)] = [(-0.06, -0.08), (-0.03, -0.11), (0, -0.13), (0.035, -0.11), (0.06, -0.075)]
            for (dx, dy) in limbs {
                let end = CGPoint(x: trunkTop.x + dx * unit, y: trunkTop.y + dy * unit)
                branches.move(to: trunkTop)
                branches.addQuadCurve(to: end, control: CGPoint(x: trunkTop.x + dx * unit * 0.3, y: trunkTop.y + dy * unit * 0.7))
                let mid = CGPoint(x: trunkTop.x + dx * unit * 0.6, y: trunkTop.y + dy * unit * 0.6)
                branches.move(to: mid)
                branches.addLine(to: CGPoint(x: mid.x + dx * unit * 0.4 + band.pt(2), y: mid.y - band.pt(4) * scale))
                snow.move(to: CGPoint(x: mid.x, y: mid.y - band.pt(0.8)))
                snow.addLine(to: CGPoint(x: end.x, y: end.y - band.pt(0.8)))
            }
            context.stroke(branches, with: .color(bark.color), style: StrokeStyle(lineWidth: band.pt(1.2 * scale), lineCap: .round))
            context.stroke(snow, with: .color(ScenesII.snowTop(variant).color), style: StrokeStyle(lineWidth: band.pt(1), lineCap: .round))
            return
        }

        let leaf: GardenRGB
        let light: GardenRGB
        if style.season == .autumn {
            leaf = GardenSceneKit.rgb(0xD9893B, 0x3A2A1A, variant)
            light = GardenSceneKit.rgb(0xE8A65A, 0x4A3620, variant)
        } else {
            leaf = GardenSceneKit.ground(GardenSceneKit.rgb(0x6DA36A, 0x1D3326, variant), season: style.season, variant: variant)
            light = GardenSceneKit.ground(GardenSceneKit.rgb(0x86B983, 0x26402E, variant), season: style.season, variant: variant)
        }
        var crown = Path()
        let blobs: [(CGFloat, CGFloat, CGFloat)] = [(0, -0.11, 0.07), (-0.045, -0.085, 0.05), (0.045, -0.085, 0.05), (0, -0.155, 0.05)]
        for (dx, dy, r) in blobs {
            let center = CGPoint(x: trunkTop.x + dx * unit, y: trunkTop.y + dy * unit)
            crown.addEllipse(in: CGRect(x: center.x - r * unit, y: center.y - r * unit, width: r * unit * 2, height: r * unit * 2))
        }
        context.fill(crown, with: .color(leaf.color))
        let highlight = CGPoint(x: trunkTop.x - 0.02 * unit, y: trunkTop.y - 0.13 * unit)
        let radius = 0.04 * unit
        context.fill(Path(ellipseIn: CGRect(x: highlight.x - radius, y: highlight.y - radius, width: radius * 2, height: radius * 2)),
                     with: .color(light.color.opacity(0.6)))
    }

    /// Where a lamp's lantern sits (the head of the post), in band points.
    private static func lampHead(_ lamp: CGPoint, band: ScenesIIBand) -> CGPoint {
        CGPoint(x: band.x(lamp.x), y: band.y(lamp.y - lampHeight) - band.pt(3))
    }

    private static func drawLampPost(_ lamp: CGPoint, in context: GraphicsContext, band: ScenesIIBand, style: GardenSceneStyle) {
        let variant = style.variant
        let iron = GardenSceneKit.color(0x3C3F45, 0x1A1C22, variant)
        let base = band.point(lamp.x, lamp.y)
        var post = Path()
        post.move(to: base)
        post.addLine(to: band.point(lamp.x, lamp.y - lampHeight))
        context.stroke(post, with: .color(iron), lineWidth: band.pt(1.8))
        context.fill(Path(CGRect(x: base.x - band.pt(2.2), y: base.y - band.pt(2), width: band.pt(4.4), height: band.pt(2))), with: .color(iron))

        let head = lampHead(lamp, band: band)
        let glass = CGRect(x: head.x - band.pt(2.4), y: head.y - band.pt(3), width: band.pt(4.8), height: band.pt(6))
        context.fill(Path(glass), with: .color(GardenSceneKit.color(0xE8E4D8, 0xFFE1A0, variant)))
        context.stroke(Path(glass), with: .color(iron), lineWidth: band.pt(0.8))
        var hood = Path()
        hood.addLines([CGPoint(x: glass.minX - band.pt(1.2), y: glass.minY), CGPoint(x: head.x, y: glass.minY - band.pt(3)),
                       CGPoint(x: glass.maxX + band.pt(1.2), y: glass.minY)])
        hood.closeSubpath()
        context.fill(hood, with: .color(iron))
        if style.season.hasSnow {
            GardenSceneKit.drawSnow(on: hood, depth: band.pt(1.5), in: context, variant: variant)
        }
    }

    /// A bench on the lawn left of the knoll, two tiny books on its seat.
    private static func drawBench(in context: GraphicsContext, band: ScenesIIBand, style: GardenSceneStyle) {
        let variant = style.variant
        var frame = Path()
        for (x, inward) in [(CGFloat(0.412), CGFloat(1)), (0.488, -1)] {
            frame.move(to: band.point(x, 0.745))
            frame.addLine(to: band.point(x, 0.80))
            frame.move(to: band.point(x + 0.004 * inward, 0.779))
            frame.addLine(to: band.point(x + 0.006 * inward, 0.80))
        }
        context.stroke(frame, with: .color(GardenSceneKit.color(0x3C3F45, 0x1A1C22, variant)), lineWidth: band.pt(1.1))
        var planks = Path()
        for (y0, y1) in [(CGFloat(0.748), CGFloat(0.754)), (0.758, 0.764), (0.772, 0.779)] {
            planks.addRect(band.rect(0.405, y0, 0.495, y1))
        }
        context.fill(planks, with: .color(GardenSceneKit.color(0x8C6B4A, 0x2E241C, variant)))
        context.fill(Path(band.rect(0.425, 0.7655, 0.442, 0.772)), with: .color(GardenSceneKit.color(0xC8553D, 0x4A2420, variant)))
        context.fill(Path(band.rect(0.428, 0.761, 0.440, 0.7655)), with: .color(GardenSceneKit.color(0x3E6E9E, 0x1E3048, variant)))
        if style.season.hasSnow {
            GardenSceneKit.drawSnow(on: planks, depth: band.pt(1.4), in: context, variant: variant)
        }
    }

    // MARK: Front: the knoll's lip and the lawn edge

    private static func drawFront(in context: GraphicsContext, band: ScenesIIBand, style: GardenSceneStyle) {
        fillKnoll(GardenSceneKit.knoll(in: band.size, apex: ScenesII.lipApex(apex), halfWidth: knollHalfWidth),
                  in: context, band: band, style: style)
        // The lawn edge (36 blades) and tufts tucked over the trunk's base.
        var grass = GardenSceneKit.frontGrass(in: band.size, blades: 36, seed: GardenSceneKit.seed(staticSeed, 23))
        let tufts: [(CGFloat, CGFloat, CGFloat)] = [(0.605, 0.872, 9), (0.68, 0.872, 9), (0.645, 0.884, 6)]
        for (index, (x, y, height)) in tufts.enumerated() {
            grass.addPath(GardenSceneKit.tuft(at: band.point(x, y), width: band.pt(8), height: band.pt(height), blades: 6,
                                              seed: GardenSceneKit.seed(staticSeed, 24 + UInt64(index))))
        }
        context.fill(grass, with: .color(ScenesII.grass(0x5E9A4E, 0x183020, style).color))
    }

    // MARK: Ambient: clock hands, lamp glows

    /// Minutes past the hour at the place (GardenSkyState.localMinute), so
    /// half- and quarter-hour time zones read right too.
    private static func minute(_ state: GardenAmbientState) -> Double {
        Double(state.sky.localMinute)
    }

    /// The clock's two hands at the place's local time (also under Reduce
    /// Motion: the time is information, not motion).
    private static func drawClockHands(in context: GraphicsContext, band: ScenesIIBand, state: GardenAmbientState) {
        let minutes = minute(state)
        let hours = Double(state.sky.localHour % 12) + minutes / 60
        let center = band.point(clockCenter.x, clockCenter.y)
        let radius = band.pt(clockRadius)
        let ink = GardenSceneKit.blend(0x3A2E33, 0x2A2024, darkness: state.sky.darkness).color
        func hand(_ turn: Double, length: CGFloat, width: CGFloat) {
            let angle = turn * 2 * .pi - .pi / 2
            var path = Path()
            path.move(to: center)
            path.addLine(to: CGPoint(x: center.x + CGFloat(cos(angle)) * radius * length, y: center.y + CGFloat(sin(angle)) * radius * length))
            context.stroke(path, with: .color(ink), style: StrokeStyle(lineWidth: band.pt(width), lineCap: .round))
        }
        hand(hours / 12, length: 0.5, width: 1.4)
        hand(minutes / 60, length: 0.78, width: 1)
        context.fill(Path(ellipseIn: CGRect(x: center.x - band.pt(0.9), y: center.y - band.pt(0.9), width: band.pt(1.8), height: band.pt(1.8))),
                     with: .color(ink))
    }

    /// The lamps glow at dusk and night.
    private static func drawLampGlows(in context: GraphicsContext, band: ScenesIIBand, state: GardenAmbientState) {
        let lit = ScenesII.smoothstep(0.25, 0.6, state.sky.darkness)
        guard lit > 0.01 else { return }
        for lamp in lamps {
            GardenSceneKit.drawGlow(in: context, center: lampHead(lamp, band: band), radius: band.pt(18), color: GardenRGB(0xFFE1A0), opacity: 0.5 * lit)
        }
    }
}

#Preview("Campus · day") {
    GardenSceneSketch(scene: .campus, localHour: 15, season: .autumn)
        .frame(width: 351, height: 208)
        .border(Color.gray.opacity(0.4))
}

#Preview("Campus · night") {
    GardenSceneSketch(scene: .campus, localHour: 22, season: .winter)
        .frame(width: 351, height: 208)
        .border(Color.gray.opacity(0.4))
}
