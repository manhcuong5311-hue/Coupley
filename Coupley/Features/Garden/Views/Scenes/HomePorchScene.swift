//
//  HomePorchScene.swift
//  Coupley
//
//  Our Garden, P6 (Scenes II): Home (C4 scene 8). Neighbourhood roofs on
//  the horizon; a little house on the left with a curtained window, a
//  porch light and two steps; a mailbox with its flag up, a picket fence,
//  a flower bed and the lawn knoll. Chimney smoke in winter and at night,
//  and a window that flickers gently after dark.
//
//  Shared helpers (ScenesIIBand, ScenesII) live in LanternTownScene.swift.
//

import CoreGraphics
import Foundation
import SwiftUI

nonisolated struct HomePorchScene: GardenScenePainting {
    init() {}

    var scene: GardenSceneID { .homePorch }

    // MARK: Layout (band fractions, C4)

    private static let apex = CGPoint(x: 0.64, y: 0.86)
    private static let knollHalfWidth: CGFloat = 0.30
    private static let horizon: CGFloat = 0.60
    /// The front window's frame (its curtains and glass sit inside).
    private static let window = (x0: CGFloat(0.055), y0: CGFloat(0.62), x1: CGFloat(0.155), y1: CGFloat(0.74))
    private static let chimneyTop = CGPoint(x: 0.24, y: 0.388)
    private static let porchLight = CGPoint(x: 0.272, y: 0.705)
    /// Scene life besides the sky: three smoke puffs and the window's light.
    private static let particleBudget = ScenesII.particleBudget(sceneLife: 4)

    private static var staticSeed: UInt64 { GardenSceneStyle.staticSeed(for: .homePorch) }

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
            // Chimney smoke in winter and at night.
            let wintry = state.season == .winter || state.season == .mildWinter
            let amount = wintry ? 1 : ScenesII.smoothstep(0.4, 0.8, state.sky.darkness)
            ScenesII.drawSmoke(in: context, band: ScenesIIBand(size), origin: Self.chimneyTop, clock: GardenSceneKit.motionTime(state),
                               seed: state.seed, color: GardenSceneKit.blend(0xF4F2EE, 0x9AA3B5, darkness: state.sky.darkness),
                               opacity: 0.45 * amount)
        case .front:
            Self.drawWindowLight(in: context, band: ScenesIIBand(size), state: state)
            GardenSceneKit.drawSeasonParticles(in: context, size: size, state: state, maxCount: Self.particleBudget)
        }
    }

    /// The porch light blinks on and off once.
    func drawWateringAccent(in context: GraphicsContext, size: CGSize, state: GardenAmbientState, progress: Double) {
        let band = ScenesIIBand(size)
        let p = min(1, max(0, progress))
        let on = ScenesII.smoothstep(0.15, 0.25, p) * (1 - ScenesII.smoothstep(0.55, 0.65, p))
        guard on > 0.01 else { return }
        let bulb = band.point(Self.porchLight.x, Self.porchLight.y)
        GardenSceneKit.drawGlow(in: context, center: bulb, radius: band.pt(18), color: GardenRGB(0xFFE7A8), opacity: 0.6 * on)
        let radius = band.pt(2.5)
        context.fill(Path(ellipseIn: CGRect(x: bulb.x - radius, y: bulb.y - radius, width: radius * 2, height: radius * 2)),
                     with: .color(GardenRGB(0xFFF4D0).color.opacity(on)))
    }

    // MARK: Far: neighbourhood roofs

    private static func drawFar(in context: GraphicsContext, band: ScenesIIBand, style: GardenSceneStyle) {
        let variant = style.variant
        var rng = GardenSceneRandom(seed: GardenSceneKit.seed(staticSeed, 3))
        var houses = Path(), trees = Path()
        var x: CGFloat = -0.22
        while x < 1.22 {
            let width: CGFloat = rng.next(0.09...0.15), rise: CGFloat = rng.next(0.05...0.09), wall: CGFloat = rng.next(0...0.025)
            let hasChimney = rng.next() < 0.4
            let hasTree = rng.next() < 0.35
            let eave = horizon - wall
            if hasChimney {
                houses.addRect(band.rect(x + width * 0.68, eave - rise * 0.85, x + width * 0.68 + 0.012, eave - rise * 0.2))
            }
            houses.addRect(band.rect(x + 0.008, eave - 0.002, x + width - 0.008, horizon + 0.01))
            houses.addLines([band.point(x, eave), band.point(x + width / 2, eave - rise), band.point(x + width, eave)])
            houses.closeSubpath()
            if hasTree {
                let center = band.point(x + width + 0.012, horizon - 0.03)
                let radius = band.height * 0.045
                trees.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            }
            x += width * rng.next(0.7...1)
        }
        let leaf = ScenesII.distant(GardenSceneKit.rgb(0xA9BFA0, 0x1C2A2E, variant), style, amount: 0.6)
        context.fill(trees, with: .color(leaf.color.opacity(variant == .day ? 0.6 : 1)))

        // One flat silhouette: overlapping roofs must not darken each other,
        // so they are painted opaque in a layer that is faded as a whole.
        var silhouettes = context
        silhouettes.opacity = variant == .day ? 0.7 : 1
        silhouettes.drawLayer { layer in
            layer.fill(houses, with: .color(GardenSceneKit.color(0xC7B9A8, 0x232838, variant)))
            if style.season.hasSnow {
                GardenSceneKit.drawSnow(on: houses, depth: band.pt(2), in: layer, variant: variant)
            }
        }
    }

    // MARK: Near: lawn, fence, house, garden bed, mailbox, knoll

    private static func drawNear(in context: GraphicsContext, band: ScenesIIBand, style: GardenSceneStyle) {
        let variant = style.variant
        ScenesII.fillGround(Path(band.rect(0, horizon, 1, 1.02)), in: context, band: band,
                            top: GardenSceneKit.rgb(0x7DB46C, 0x1C3424, variant),
                            bottom: GardenSceneKit.rgb(0x6AA65A, 0x172C1E, variant),
                            from: horizon, to: 1, style: style)
        GardenSceneKit.drawGroundDetails(in: context, rect: band.rect(0.40, 0.66, 0.70, 0.82), season: style.season,
                                         variant: variant, seed: staticSeed)
        drawFence(in: context, band: band, style: style)
        drawHouse(in: context, band: band, style: style)
        drawGardenBed(in: context, band: band, style: style)
        drawMailbox(in: context, band: band, style: style)

        let knoll = GardenSceneKit.knoll(in: band.size, apex: apex, halfWidth: knollHalfWidth)
        fillKnoll(knoll, in: context, band: band, style: style)
        let rim = style.season.hasSnow ? ScenesII.snowTop(variant)
            : GardenSceneKit.ground(GardenSceneKit.rgb(0x9FD08A, 0x2A4A30, variant), season: style.season, variant: variant)
        GardenSceneKit.drawRim(on: knoll, thickness: band.pt(1), color: rim, in: context)
    }

    private static func fillKnoll(_ path: Path, in context: GraphicsContext, band: ScenesIIBand, style: GardenSceneStyle) {
        ScenesII.fillGround(path, in: context, band: band,
                            top: GardenSceneKit.rgb(0x88BF76, 0x1F3828, style.variant),
                            bottom: GardenSceneKit.rgb(0x6AA65A, 0x172C1E, style.variant),
                            from: apex.y, to: 1, style: style)
    }

    /// A white picket fence on the right, behind the tree.
    private static func drawFence(in context: GraphicsContext, band: ScenesIIBand, style: GardenSceneStyle) {
        let variant = style.variant
        let paint = GardenSceneKit.rgb(0xF5F1EA, 0x3A3F52, variant)
        let base: CGFloat = 0.775, height: CGFloat = 0.075
        var rails = Path(), pickets = Path(), shadows = Path()
        for level: CGFloat in [0.35, 0.75] {
            rails.addRect(band.rect(0.72, base - height * level, 1.0, base - height * level + 0.008))
        }
        var x: CGFloat = 0.725
        while x < 1 {
            let shoulder = base - height + 0.012
            pickets.addLines([band.point(x, base), band.point(x, shoulder), band.point(x + 0.0055, base - height),
                              band.point(x + 0.011, shoulder), band.point(x + 0.011, base)])
            pickets.closeSubpath()
            shadows.move(to: band.point(x + 0.011, shoulder))
            shadows.addLine(to: band.point(x + 0.011, base))
            x += 0.02
        }
        context.fill(rails, with: .color(GardenSceneKit.scaled(paint, 0.9).color))
        context.fill(pickets, with: .color(paint.color))
        context.stroke(shadows, with: .color(GardenSceneKit.rgb(0xD9D2C6, 0x2A2E3E, variant).color.opacity(0.8)), lineWidth: band.pt(0.6))
        if style.season.hasSnow {
            GardenSceneKit.drawSnow(on: pickets, depth: band.pt(1.6), in: context, variant: variant)
        }
    }

    /// The house at the left (x 0–0.34, y 0.40–0.86).
    private static func drawHouse(in context: GraphicsContext, band: ScenesIIBand, style: GardenSceneStyle) {
        let variant = style.variant
        let wall = GardenSceneKit.rgb(0xEBD9C2, 0x3A3442, variant)
        let trim = GardenSceneKit.rgb(0xF7F1E6, 0x4A4452, variant)

        // The chimney rises behind the roof's right slope.
        var chimney = Path(band.rect(0.225, 0.395, 0.255, 0.48))
        chimney.addRect(band.rect(0.22, 0.388, 0.26, 0.397))
        context.fill(chimney, with: .color(GardenSceneKit.color(0x9A5A4A, 0x2E2026, variant)))

        // The wall and its gable end, with horizontal siding.
        var body = Path(band.rect(0.02, 0.53, 0.30, 0.86))
        body.addLines([band.point(0.02, 0.531), band.point(0.16, 0.41), band.point(0.30, 0.531)])
        body.closeSubpath()
        context.fill(body, with: .color(wall.color))
        var siding = Path()
        var y = band.y(0.43)
        while y < band.y(0.86) {
            siding.move(to: CGPoint(x: band.x(0.02), y: y))
            siding.addLine(to: CGPoint(x: band.x(0.30), y: y))
            y += band.pt(4)
        }
        var sided = context
        sided.clip(to: body)
        sided.stroke(siding, with: .color(GardenSceneKit.scaled(wall, 0.85).color.opacity(0.35)), lineWidth: band.pt(0.5))

        // The roof: one thick band along both slopes.
        var ridgeLine = Path()
        ridgeLine.addLines([band.point(-0.005, 0.548), band.point(0.16, 0.405), band.point(0.325, 0.548)])
        let roof = ridgeLine.strokedPath(StrokeStyle(lineWidth: band.pt(7), lineCap: .butt, lineJoin: .miter))
        context.fill(roof, with: .color(GardenSceneKit.color(0xA3574A, 0x3A2228, variant)))

        // A round attic window in the gable.
        let attic = band.point(0.16, 0.47)
        let atticRect = CGRect(x: attic.x - band.pt(3.5), y: attic.y - band.pt(3.5), width: band.pt(7), height: band.pt(7))
        context.fill(Path(ellipseIn: atticRect), with: .color(GardenSceneKit.color(0xBFD6E2, 0xFFC873, variant)))
        context.stroke(Path(ellipseIn: atticRect), with: .color(trim.color), lineWidth: band.pt(1.2))

        drawWindow(in: context, band: band, style: style, trim: trim)

        // The door, its frame, panels and knob; the porch light beside it.
        context.fill(Path(band.rect(0.185, 0.685, 0.255, 0.86)), with: .color(trim.color))
        let door = band.rect(0.192, 0.692, 0.248, 0.86)
        let doorColor = GardenSceneKit.rgb(0x6E4B3A, 0x241A16, variant)
        context.fill(Path(door), with: .color(doorColor.color))
        let (upperPanel, lowerPanel) = door.insetBy(dx: door.width * 0.2, dy: 0).divided(atDistance: door.height * 0.45, from: .minYEdge)
        var panels = Path()
        panels.addRect(upperPanel.insetBy(dx: 0, dy: band.pt(3)))
        panels.addRect(lowerPanel.insetBy(dx: 0, dy: band.pt(3)))
        context.stroke(panels, with: .color(doorColor.mixed(with: GardenRGB(0xFFFFFF), 0.2).color.opacity(0.4)), lineWidth: band.pt(0.6))
        let knob = band.point(0.240, 0.78)
        context.fill(Path(ellipseIn: CGRect(x: knob.x - band.pt(1.3), y: knob.y - band.pt(1.3), width: band.pt(2.6), height: band.pt(2.6))),
                     with: .color(GardenSceneKit.color(0xD9B45A, 0x6A5A3A, variant)))
        let light = band.point(porchLight.x, porchLight.y)
        if variant == .night {
            GardenSceneKit.drawGlow(in: context, center: light, radius: band.pt(8), color: GardenRGB(0xFFD58A), opacity: 0.4)
        }
        let lantern = Path(roundedRect: CGRect(x: light.x - band.pt(1.75), y: light.y - band.pt(2.5), width: band.pt(3.5), height: band.pt(5)),
                           cornerRadius: band.pt(0.8))
        context.fill(lantern, with: .color(GardenSceneKit.color(0xE8E2D2, 0xFFD58A, variant)))
        context.stroke(lantern, with: .color(GardenSceneKit.color(0x3C3F45, 0x1A1C22, variant)), lineWidth: band.pt(0.8))

        // Two porch steps.
        let stepColor = GardenSceneKit.rgb(0xC9B7A2, 0x3A3436, variant)
        var steps = Path()
        for rect in [band.rect(0.175, 0.86, 0.265, 0.885), band.rect(0.165, 0.885, 0.275, 0.91)] {
            steps.addRect(rect)
            context.fill(Path(rect), with: .color(stepColor.color))
            context.fill(Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: band.pt(1))),
                         with: .color(stepColor.mixed(with: GardenRGB(0xFFFFFF), 0.3).color))
        }

        if style.season.hasSnow {
            GardenSceneKit.drawSnow(on: roof, depth: band.pt(2.6), in: context, variant: variant)
            GardenSceneKit.drawSnow(on: chimney, depth: band.pt(1.8), in: context, variant: variant)
            GardenSceneKit.drawSnow(on: steps, depth: band.pt(1.4), in: context, variant: variant)
        }
    }

    /// The front window: frame, glass, curtains tied back, mullions and sill.
    private static func drawWindow(in context: GraphicsContext, band: ScenesIIBand, style: GardenSceneStyle, trim: GardenRGB) {
        let variant = style.variant
        let frame = band.rect(window.x0, window.y0, window.x1, window.y1)
        context.fill(Path(frame), with: .color(trim.color))
        let glass = frame.insetBy(dx: band.pt(2), dy: band.pt(2))
        context.fill(Path(glass), with: .color(GardenSceneKit.color(0xBFD6E2, 0xFFC873, variant)))

        let cloth = GardenSceneKit.color(0xF6E7C8, 0xE7A95A, variant)
        for leading in [true, false] {
            let edge = leading ? glass.minX : glass.maxX
            let reach = glass.width * (leading ? 0.32 : -0.32)
            var curtain = Path()
            curtain.move(to: CGPoint(x: edge, y: glass.minY))
            curtain.addLine(to: CGPoint(x: edge + reach, y: glass.minY))
            curtain.addQuadCurve(to: CGPoint(x: edge + reach * 0.4, y: glass.minY + glass.height * 0.58),
                                 control: CGPoint(x: edge + reach * 0.9, y: glass.minY + glass.height * 0.4))
            curtain.addQuadCurve(to: CGPoint(x: edge + reach * 0.55, y: glass.maxY),
                                 control: CGPoint(x: edge + reach * 0.3, y: glass.minY + glass.height * 0.8))
            curtain.addLine(to: CGPoint(x: edge, y: glass.maxY))
            curtain.closeSubpath()
            context.fill(curtain, with: .color(cloth))
        }
        var mullions = Path()
        mullions.move(to: CGPoint(x: glass.midX, y: glass.minY))
        mullions.addLine(to: CGPoint(x: glass.midX, y: glass.maxY))
        mullions.move(to: CGPoint(x: glass.minX, y: glass.midY))
        mullions.addLine(to: CGPoint(x: glass.maxX, y: glass.midY))
        context.stroke(mullions, with: .color(trim.color), lineWidth: band.pt(1))
        let sill = Path(band.rect(window.x0 - 0.006, window.y1, window.x1 + 0.006, window.y1 + 0.01))
        context.fill(sill, with: .color(trim.color))
        if style.season.hasSnow {
            GardenSceneKit.drawSnow(on: sill, depth: band.pt(1.4), in: context, variant: variant)
        }
    }

    /// The season's flowers: a palette and how many bloom (none under snow).
    private static func flowers(_ season: GardenSceneSeason) -> (colors: [UInt32], count: Int) {
        switch season {
        case .spring, .summer:        return ([0xF7A8C4, 0xFFE27A, 0xFFFFFF, 0xE85D75], 12)
        case .autumn:                 return ([0xE08A3C, 0xC9653A, 0xD8A23C], 9)
        case .mildWinter, .drySeason: return ([0xF7A8C4, 0xFFFFFF], 5)
        case .winter:                 return ([], 0)
        }
    }

    /// The garden bed under the window: soil, then foliage and the season's
    /// flowers, or snow.
    private static func drawGardenBed(in context: GraphicsContext, band: ScenesIIBand, style: GardenSceneStyle) {
        let bed = band.rect(0.025, 0.855, 0.165, 0.89)
        let soil = Path(roundedRect: bed, cornerRadius: band.pt(3))
        context.fill(soil, with: .color(GardenSceneKit.color(0x8B6A4E, 0x2E241C, style.variant)))
        if style.season.hasSnow {
            GardenSceneKit.drawSnow(on: soil, depth: band.pt(2.4), in: context, variant: style.variant)
        } else {
            drawFlowers(along: bed.insetBy(dx: band.pt(3), dy: 0), baseline: bed.minY + band.pt(1.5), salt: 29,
                        in: context, band: band, style: style)
        }
    }

    /// Foliage and flower heads along `span` at `baseline` (band points).
    private static func drawFlowers(along span: CGRect, baseline: CGFloat, salt: UInt64, in context: GraphicsContext,
                                    band: ScenesIIBand, style: GardenSceneStyle) {
        let palette = flowers(style.season)
        guard palette.count > 0 else { return }
        let dim = style.variant == .night ? 0.45 : 1
        var rng = GardenSceneRandom(seed: GardenSceneKit.seed(staticSeed, salt))
        var foliage = Path()
        for _ in 0..<palette.count + 4 {
            let center = CGPoint(x: span.minX + CGFloat(rng.next()) * span.width, y: baseline - band.pt(rng.next(0.5...2)))
            foliage.addEllipse(in: CGRect(x: center.x - band.pt(2.4), y: center.y - band.pt(1.6), width: band.pt(4.8), height: band.pt(3.2)))
        }
        context.fill(foliage, with: .color(ScenesII.grass(0x5E9A4E, 0x1A2E22, style).color))
        for index in 0..<palette.count {
            let center = CGPoint(x: span.minX + (CGFloat(index) + rng.next(0.1...0.9)) / CGFloat(palette.count) * span.width,
                                 y: baseline - band.pt(rng.next(2.5...4.5)))
            let radius = band.pt(rng.next(1.2...1.9))
            let tint = GardenSceneKit.scaled(GardenRGB(palette.colors[rng.index(palette.colors.count)]), dim)
            context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                         with: .color(tint.color))
        }
    }

    /// A mailbox at x 0.36 with its red flag up.
    private static func drawMailbox(in context: GraphicsContext, band: ScenesIIBand, style: GardenSceneStyle) {
        let variant = style.variant
        var post = Path()
        post.move(to: band.point(0.36, 0.80))
        post.addLine(to: band.point(0.36, 0.88))
        context.stroke(post, with: .color(GardenSceneKit.color(0x6E4B3A, 0x241A16, variant)), lineWidth: band.pt(2))
        let rect = band.rect(0.343, 0.775, 0.377, 0.80)
        let box = Path(roundedRect: rect, cornerSize: CGSize(width: rect.height * 0.45, height: rect.height * 0.45))
        context.fill(box, with: .color(GardenSceneKit.color(0x4A6FA5, 0x22304A, variant)))
        var pole = Path()
        pole.move(to: band.point(0.379, 0.795))
        pole.addLine(to: band.point(0.379, 0.765))
        context.stroke(pole, with: .color(GardenSceneKit.color(0x3C3F45, 0x1A1C22, variant)), lineWidth: band.pt(0.8))
        context.fill(Path(band.rect(0.379, 0.765, 0.391, 0.777)), with: .color(GardenSceneKit.color(0xD9534F, 0x5A2826, variant)))
        if style.season.hasSnow {
            GardenSceneKit.drawSnow(on: box, depth: band.pt(1.8), in: context, variant: variant)
        }
    }

    // MARK: Front: the knoll's lip, grass, the flower-bed edge

    private static func drawFront(in context: GraphicsContext, band: ScenesIIBand, style: GardenSceneStyle) {
        let variant = style.variant
        fillKnoll(GardenSceneKit.knoll(in: band.size, apex: ScenesII.lipApex(apex), halfWidth: knollHalfWidth),
                  in: context, band: band, style: style)

        // Grass along the bottom (the bed edge covers its left part) and
        // tufts tucked over the trunk's base.
        var grass = GardenSceneKit.frontGrass(in: band.size, blades: 32, seed: GardenSceneKit.seed(staticSeed, 31))
        let tufts: [(CGFloat, CGFloat, CGFloat)] = [(0.605, 0.872, 9), (0.68, 0.872, 9), (0.645, 0.884, 6)]
        for (index, (x, y, height)) in tufts.enumerated() {
            grass.addPath(GardenSceneKit.tuft(at: band.point(x, y), width: band.pt(8), height: band.pt(height), blades: 6,
                                              seed: GardenSceneKit.seed(staticSeed, 32 + UInt64(index))))
        }
        context.fill(grass, with: .color(ScenesII.grass(0x5E9A4E, 0x183020, style).color))

        // The flower-bed edge along the bottom-left: flowers behind a row of
        // tilted edging bricks.
        drawFlowers(along: band.rect(0, 0.95, 0.42, 0.97), baseline: band.y(0.975), salt: 37, in: context, band: band, style: style)
        let brick = GardenSceneKit.rgb(0xB5654B, 0x3A2328, variant)
        var bricks = Path()
        var x = band.x(-0.01)
        var tilt: CGFloat = 1
        while x < band.x(0.42) {
            let size = CGSize(width: band.pt(9), height: band.pt(5))
            let turn = CGAffineTransform(translationX: x + size.width / 2, y: band.y(0.972) + size.height / 2).rotated(by: tilt * 0.07)
            bricks.addPath(Path(roundedRect: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height),
                                cornerRadius: band.pt(1)).applying(turn))
            x += band.pt(10)
            tilt = -tilt
        }
        context.fill(bricks, with: .color(brick.color))
        context.stroke(bricks, with: .color(GardenSceneKit.scaled(brick, 0.7).color), lineWidth: band.pt(0.6))
        if style.season.hasSnow {
            GardenSceneKit.drawSnow(on: bricks, depth: band.pt(1.6), in: context, variant: variant)
        }
    }

    // MARK: Ambient: the window after dark

    /// Lamplight in the front window from golden hour, flickering gently
    /// (0.9–1.0 at 0.3 Hz). Drawn in the front pass because the window
    /// belongs to the near layer.
    private static func drawWindowLight(in context: GraphicsContext, band: ScenesIIBand, state: GardenAmbientState) {
        let on = ScenesII.lightsOn(state.sky)
        guard on > 0.01 else { return }
        let phase = ScenesII.phase(seed: state.seed, salt: 0x3A11, index: 0)
        let flicker = 0.9 + 0.1 * ScenesII.pulse(GardenSceneKit.motionTime(state), hz: 0.3, phase: phase)
        let frame = band.rect(window.x0, window.y0, window.x1, window.y1)
        GardenSceneKit.drawGlow(in: context, center: CGPoint(x: frame.midX, y: frame.midY), radius: band.pt(26),
                                color: GardenRGB(0xFFC873), opacity: 0.35 * on * flicker)
    }
}

#Preview("Home · day") {
    GardenSceneSketch(scene: .homePorch, localHour: 11, season: .summer)
        .frame(width: 351, height: 208)
        .border(Color.gray.opacity(0.4))
}

#Preview("Home · night") {
    GardenSceneSketch(scene: .homePorch, localHour: 20.5, season: .winter)
        .frame(width: 351, height: 208)
        .border(Color.gray.opacity(0.4))
}
