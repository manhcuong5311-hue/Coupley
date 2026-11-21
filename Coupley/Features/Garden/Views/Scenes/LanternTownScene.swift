//
//  LanternTownScene.swift
//  Coupley
//
//  Our Garden, P6 (Scenes II): Lantern Town (C4 scene 5). Ochre townhouses
//  and a two-tier temple across a river, a lacquered arched bridge, a
//  cobbled embankment knoll, and silk lanterns swaying on a line over the
//  water.
//
//  This file also holds the few helpers the four Scenes II painters share
//  on top of GardenSceneKit (band fractions, the seamless ground fill,
//  smoke, the motion budget and clocks): see "Scenes II shared drawing" at
//  the bottom. Coordinates follow GardenSceneKit: every layer and pass
//  draws in band points.
//

import CoreGraphics
import Foundation
import SwiftUI

nonisolated struct LanternTownScene: GardenScenePainting {
    init() {}

    var scene: GardenSceneID { .lanternTown }

    // MARK: Layout (band fractions, C4)

    private static let apex = CGPoint(x: 0.66, y: 0.86)
    private static let knollHalfWidth: CGFloat = 0.34
    private static let horizon: CGFloat = 0.62
    private static let riverTop: CGFloat = 0.645
    private static let quayTop: CGFloat = 0.80
    /// The houses leave this stretch to the temple at x 0.78.
    private static let templeGap: Range<CGFloat> = 0.705..<0.855
    private static let houseWalls: [UInt32] = [0xE9C46A, 0xE8B04F, 0xD99B4A]

    private static let lanternCount = 7
    private static let lanternColors: [UInt32] = [0xE63946, 0xF4A261, 0xE9C46A, 0xE76F51]
    private static let lineStart = CGPoint(x: 0.02, y: 0.22)
    private static let lineEnd = CGPoint(x: 0.98, y: 0.30)
    /// The line's sag at its middle, as a fraction of the band's height.
    private static let lineSag: CGFloat = 0.10
    /// Scene life besides the sky: seven lanterns, their line, the boat and
    /// six reflections.
    private static let particleBudget = ScenesII.particleBudget(sceneLife: 15)

    private static var staticSeed: UInt64 { GardenSceneStyle.staticSeed(for: .lanternTown) }

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
            Self.drawReflections(in: context, band: band, state: state)
            Self.drawBoat(in: context, band: band, state: state)
            Self.drawLanterns(in: context, band: band, state: state)
        case .front:
            if state.season == .spring {
                Self.drawPeachPetals(in: context, band: ScenesIIBand(size), state: state)
            } else {
                GardenSceneKit.drawSeasonParticles(in: context, size: size, state: state, maxCount: Self.particleBudget)
            }
        }
    }

    /// The lanterns brighten in a wave from left to right.
    func drawWateringAccent(in context: GraphicsContext, size: CGSize, state: GardenAmbientState, progress: Double) {
        let band = ScenesIIBand(size)
        let crest = -0.1 + 1.2 * min(1, max(0, progress))
        let anchors = Self.lanternAnchors(band)
        for index in 0..<Self.lanternCount {
            let pose = Self.lanternPose(index, anchors: anchors, state: state)
            let strength = exp(-pow((Double(pose.anchor.x / max(1, band.width)) - crest) / 0.12, 2))
            guard strength > 0.02 else { continue }
            let center = Self.lanternCenter(pose, band: band)
            GardenSceneKit.drawGlow(in: context, center: center, radius: band.pt(22), color: GardenRGB(0xFFE3A0), opacity: 0.7 * strength)
            let body = CGRect(x: center.x - band.pt(4.5), y: center.y - band.pt(6), width: band.pt(9), height: band.pt(12))
            context.fill(Path(ellipseIn: body), with: .color(GardenRGB(0xFFF2C8).color.opacity(0.5 * strength)))
        }
    }

    // MARK: Far: townhouses, temple, river

    private struct House {
        let x: CGFloat
        let width: CGFloat
        let wallHeight: CGFloat
        let wall: UInt32
        let windows: Int
    }

    /// Townhouses 0.11–0.16 W wide on the horizon, laid out from a fixed
    /// origin across the far layer's whole span (seven of them in the band).
    private static let houses: [House] = {
        var rng = GardenSceneRandom(seed: GardenSceneKit.seed(GardenSceneStyle.staticSeed(for: .lanternTown), 1))
        var result: [House] = []
        var x: CGFloat = -0.22
        while x < 1.22 {
            var width: CGFloat = rng.next(0.11...0.16)
            let wallHeight: CGFloat = rng.next(0.10...0.16)
            let wall = houseWalls[rng.index(houseWalls.count)]
            let gap: CGFloat = rng.next(0.002...0.008)
            // A house that would reach into the temple's stretch is cut
            // short at its edge, or skipped past it when too narrow.
            if templeGap.contains(x) || (x < templeGap.lowerBound && x + width > templeGap.lowerBound) {
                width = templeGap.lowerBound - x
                if width < 0.06 {
                    x = templeGap.upperBound
                    continue
                }
            }
            result.append(House(x: x, width: width, wallHeight: wallHeight, wall: wall, windows: width > 0.135 ? 2 : 1))
            x += width + gap
        }
        return result
    }()

    private static func drawFar(in context: GraphicsContext, band: ScenesIIBand, style: GardenSceneStyle) {
        let variant = style.variant
        for house in houses where house.x + house.width > band.minX && house.x < band.maxX {
            drawHouse(house, in: context, band: band, style: style)
        }
        drawTemple(in: context, band: band, style: style)

        // The river, a little greyer under a temperate winter sky.
        var waterTop = GardenSceneKit.rgb(0x3E7C7F, 0x10263A, variant)
        var waterBottom = GardenSceneKit.rgb(0x5E9E99, 0x173246, variant)
        if style.season.hasSnow {
            let ice = GardenSceneKit.rgb(0x9DB4BC, 0x2A3A4A, variant)
            waterTop = waterTop.mixed(with: ice, 0.25)
            waterBottom = waterBottom.mixed(with: ice, 0.25)
        }
        let river = band.rect(band.minX, riverTop, band.maxX, 0.84)
        context.fill(Path(river), with: .linearGradient(Gradient(colors: [waterTop.color, waterBottom.color]),
                                                        startPoint: CGPoint(x: 0, y: river.minY),
                                                        endPoint: CGPoint(x: 0, y: band.y(quayTop))))

        // Reflections of the houses and the temple, fading down the water.
        for house in houses where house.x + house.width > band.minX && house.x < band.maxX {
            let rect = band.rect(house.x + house.width * 0.08, riverTop, house.x + house.width * 0.92,
                                 riverTop + house.wallHeight * 0.55)
            fillReflection(rect, color: GardenSceneKit.rgb(house.wall, 0x3A3346, variant), opacity: 0.24, in: context)
            guard variant == .night else { continue }
            for index in 0..<house.windows {
                let cx = band.x(house.x + house.width * (CGFloat(index) + 0.5) / CGFloat(house.windows))
                let streak = CGRect(x: cx - band.pt(1.5), y: band.y(riverTop + house.wallHeight * 0.32), width: band.pt(3), height: band.pt(6))
                context.fill(Path(roundedRect: streak, cornerRadius: band.pt(1.5)), with: .color(GardenRGB(0xFFC46B).color.opacity(0.3)))
            }
        }
        fillReflection(band.rect(0.728, riverTop, 0.832, riverTop + 0.07),
                       color: GardenSceneKit.rgb(0xB5443A, 0x2C1E28, variant), opacity: 0.2, in: context)

        var rng = GardenSceneRandom(seed: GardenSceneKit.seed(staticSeed, 7))
        var ripples = Path()
        for _ in 0..<16 {
            let x: CGFloat = rng.next(band.minX...band.maxX)
            let y: CGFloat = rng.next((riverTop + 0.015)...(quayTop - 0.01))
            let length: CGFloat = rng.next(0.03...0.09)
            ripples.move(to: band.point(x, y))
            ripples.addLine(to: band.point(x + length, y))
        }
        context.stroke(ripples, with: .color(GardenSceneKit.rgb(0xFFFFFF, 0x5E86A8, variant).color.opacity(0.18)),
                       style: StrokeStyle(lineWidth: band.pt(0.8), lineCap: .round))

        // The embankment wall the houses stand on, with its coping.
        let stone = GardenSceneKit.rgb(0x9C8B72, 0x2E2A2A, variant)
        context.fill(Path(band.rect(band.minX, 0.612, band.maxX, riverTop + 0.004)), with: .color(stone.color))
        var joints = Path()
        var jointX = (band.minX * 30).rounded(.down) / 30
        while jointX <= band.maxX {
            joints.move(to: band.point(jointX, 0.618))
            joints.addLine(to: band.point(jointX, riverTop))
            jointX += 1.0 / 30
        }
        joints.move(to: band.point(band.minX, 0.631))
        joints.addLine(to: band.point(band.maxX, 0.631))
        context.stroke(joints, with: .color(GardenSceneKit.scaled(stone, 0.72).color.opacity(0.45)), lineWidth: band.pt(0.6))
        let coping = Path(band.rect(band.minX, 0.607, band.maxX, 0.616))
        context.fill(coping, with: .color(GardenSceneKit.color(0xB9A78C, 0x3A3534, variant)))
        if style.season.hasSnow {
            GardenSceneKit.drawSnow(on: coping, depth: band.pt(2), in: context, variant: variant)
        }
    }

    private static func fillReflection(_ rect: CGRect, color: GardenRGB, opacity: Double, in context: GraphicsContext) {
        context.fill(Path(rect), with: .linearGradient(Gradient(colors: [color.color.opacity(opacity), color.color.opacity(0)]),
                                                       startPoint: CGPoint(x: rect.midX, y: rect.minY),
                                                       endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
    }

    private static func drawHouse(_ house: House, in context: GraphicsContext, band: ScenesIIBand, style: GardenSceneStyle) {
        let variant = style.variant
        let top = horizon - house.wallHeight
        let x0 = house.x, x1 = house.x + house.width
        context.fill(Path(band.rect(x0, top, x1, horizon)), with: .color(GardenSceneKit.color(house.wall, 0x3A3346, variant)))

        // A shuttered shopfront on the ground floor, lamplit at night.
        let shop = band.rect(x0 + house.width * 0.18, horizon - 0.05, x1 - house.width * 0.18, horizon)
        let shopColor = variant == .day ? GardenRGB(0x7A4E3A).color.opacity(0.55) : GardenRGB(0xFFB55A).color.opacity(0.75)
        context.fill(Path(shop), with: .color(shopColor))

        // A balcony rail between the floors.
        var rail = Path()
        let railY = top + house.wallHeight * 0.48
        rail.move(to: band.point(x0, railY))
        rail.addLine(to: band.point(x1, railY))
        context.stroke(rail, with: .color(GardenSceneKit.rgb(0x7A4E3A, 0x241A22, variant).color.opacity(0.6)), lineWidth: band.pt(1.2))

        // Upper-floor windows: dark wood by day, lamplight at night.
        for index in 0..<house.windows {
            let cx = band.x(x0 + house.width * (CGFloat(index) + 0.5) / CGFloat(house.windows))
            let window = CGRect(x: cx - band.pt(2.8), y: band.y(top + 0.03), width: band.pt(5.6), height: band.pt(7.5))
            if variant == .night {
                GardenSceneKit.drawGlow(in: context, center: CGPoint(x: window.midX, y: window.midY), radius: band.pt(9),
                                        color: GardenRGB(0xFFC46B), opacity: 0.35)
                context.fill(Path(window), with: .color(GardenRGB(0xFFC46B).color))
            } else {
                context.fill(Path(window), with: .color(GardenRGB(0x5A3E30).color.opacity(0.85)))
            }
        }
        drawRoof(x0: x0, x1: x1, y: top, rise: 0.045, overhang: 0.014, ridgeInset: 0.03, in: context, band: band, style: style)
    }

    /// A tiled roof with upturned eaves on a wall top at `y`, from `x0` to `x1`.
    private static func drawRoof(x0: CGFloat, x1: CGFloat, y: CGFloat, rise: CGFloat, overhang: CGFloat, ridgeInset: CGFloat,
                                 in context: GraphicsContext, band: ScenesIIBand, style: GardenSceneStyle) {
        let tipLeft = band.point(x0 - overhang, y - 0.016)
        let tipRight = band.point(x1 + overhang, y - 0.016)
        let ridgeLeft = band.point(x0 + ridgeInset, y - rise)
        let ridgeRight = band.point(x1 - ridgeInset, y - rise)

        // The slopes sweep up from the eaves: flat at first, then steep.
        var roof = Path()
        roof.move(to: tipLeft)
        roof.addQuadCurve(to: band.point(x0 + 0.008, y + 0.006), control: band.point(x0 - overhang * 0.1, y + 0.008))
        roof.addLine(to: band.point(x1 - 0.008, y + 0.006))
        roof.addQuadCurve(to: tipRight, control: band.point(x1 + overhang * 0.1, y + 0.008))
        roof.addQuadCurve(to: ridgeRight, control: band.point(x1 - ridgeInset * 0.35, y - rise * 0.25))
        roof.addLine(to: ridgeLeft)
        roof.addQuadCurve(to: tipLeft, control: band.point(x0 + ridgeInset * 0.35, y - rise * 0.25))
        roof.closeSubpath()

        let tile = GardenSceneKit.rgb(0x7A4E3A, 0x241A22, style.variant)
        context.fill(roof, with: .color(tile.color))
        var rows = Path()
        var x = tipLeft.x
        while x <= tipRight.x {
            rows.move(to: CGPoint(x: x, y: ridgeLeft.y))
            rows.addLine(to: CGPoint(x: x, y: band.y(y + 0.01)))
            x += band.pt(3.2)
        }
        var tiles = context
        tiles.clip(to: roof)
        tiles.stroke(rows, with: .color(GardenSceneKit.scaled(tile, 0.7).color.opacity(0.5)), lineWidth: band.pt(0.6))

        var ridge = Path()
        ridge.move(to: ridgeLeft)
        ridge.addLine(to: ridgeRight)
        context.stroke(ridge, with: .color(GardenSceneKit.scaled(tile, 0.6).color), style: StrokeStyle(lineWidth: band.pt(1.6), lineCap: .round))
        if style.season.hasSnow {
            GardenSceneKit.drawSnow(on: roof, depth: band.pt(2.2), in: context, variant: style.variant)
        }
    }

    /// A lacquered two-tier temple at x 0.78.
    private static func drawTemple(in context: GraphicsContext, band: ScenesIIBand, style: GardenSceneStyle) {
        let variant = style.variant
        let lacquer = GardenSceneKit.color(0xB5443A, 0x2C1E28, variant)
        context.fill(Path(band.rect(0.752, 0.43, 0.808, 0.49)), with: .color(lacquer))
        context.fill(Path(band.rect(0.728, 0.525, 0.832, horizon)), with: .color(lacquer))
        var pillars = Path()
        for x: CGFloat in [0.738, 0.760, 0.800, 0.822] {
            pillars.move(to: band.point(x, 0.53))
            pillars.addLine(to: band.point(x, horizon))
        }
        context.stroke(pillars, with: .color(GardenSceneKit.color(0x7A2A24, 0x1A1218, variant)), lineWidth: band.pt(1.4))
        let doorColor = variant == .day ? GardenRGB(0x5A2A22).color : GardenRGB(0xFFB55A).color.opacity(0.85)
        context.fill(Path(band.rect(0.770, 0.56, 0.790, horizon)), with: .color(doorColor))

        drawRoof(x0: 0.715, x1: 0.845, y: 0.525, rise: 0.05, overhang: 0.024, ridgeInset: 0.03, in: context, band: band, style: style)
        drawRoof(x0: 0.742, x1: 0.818, y: 0.43, rise: 0.045, overhang: 0.02, ridgeInset: 0.02, in: context, band: band, style: style)

        let gold = GardenSceneKit.color(0xE9C46A, 0x6A5A3A, variant)
        var spire = Path()
        spire.move(to: band.point(0.78, 0.385))
        spire.addLine(to: band.point(0.78, 0.362))
        context.stroke(spire, with: .color(gold), lineWidth: band.pt(1))
        let finial = band.point(0.78, 0.362)
        context.fill(Path(ellipseIn: CGRect(x: finial.x - band.pt(2), y: finial.y - band.pt(3), width: band.pt(4), height: band.pt(5))),
                     with: .color(gold))
    }

    // MARK: Near: bridge, quay, knoll

    private static func drawNear(in context: GraphicsContext, band: ScenesIIBand, style: GardenSceneStyle) {
        let variant = style.variant
        drawBridge(in: context, band: band, style: style)

        // The quay: paved stone along the near bank, with its coping edge.
        let quay = GardenSceneKit.rgb(0xA8957A, 0x34302B, variant)
        ScenesII.fillGround(Path(band.rect(0, quayTop, 1, 1.02)), in: context, band: band,
                            top: quay, bottom: GardenSceneKit.rgb(0x96846A, 0x2C2824, variant),
                            from: quayTop, to: 1, style: style, seasonTint: false)
        var flags = Path()
        for (row, y) in [CGFloat(0.87), 0.935].enumerated() {
            flags.move(to: band.point(0, y))
            flags.addLine(to: band.point(1, y))
            var x: CGFloat = row == 0 ? 0.03 : 0.07
            while x < 1 {
                flags.move(to: band.point(x, y - 0.065))
                flags.addLine(to: band.point(x, y))
                x += 0.09
            }
        }
        context.stroke(flags, with: .color(GardenSceneKit.scaled(quay, 0.75).color.opacity(0.35)), lineWidth: band.pt(0.6))
        context.fill(Path(band.rect(0, quayTop - 0.006, 1, quayTop + 0.008)), with: .color(GardenSceneKit.color(0x8E7C64, 0x2A2622, variant)))
        for x: CGFloat in [0.06, 0.22] {
            let post = CGRect(x: band.x(x) - band.pt(2), y: band.y(quayTop) - band.pt(5), width: band.pt(4), height: band.pt(6))
            context.fill(Path(roundedRect: post, cornerRadius: band.pt(1.6)), with: .color(GardenSceneKit.color(0x4A4038, 0x1E1A18, variant)))
        }
        GardenSceneKit.drawGroundDetails(in: context, rect: band.rect(0.02, 0.83, 0.30, 0.98), season: style.season,
                                         variant: variant, seed: staticSeed)

        // The cobbled embankment knoll the tree stands on.
        let knoll = GardenSceneKit.knoll(in: band.size, apex: apex, halfWidth: knollHalfWidth)
        fillKnoll(knoll, in: context, band: band, style: style)
        drawCobbles(in: context, band: band, style: style, clip: knoll)
        GardenSceneKit.drawRim(on: knoll, thickness: band.pt(1), color: GardenSceneKit.rgb(0xCDBDA2, 0x4A433A, variant), in: context)
    }

    private static func fillKnoll(_ path: Path, in context: GraphicsContext, band: ScenesIIBand, style: GardenSceneStyle) {
        ScenesII.fillGround(path, in: context, band: band,
                            top: GardenSceneKit.rgb(0xB8A58A, 0x3E3830, style.variant),
                            bottom: GardenSceneKit.rgb(0xA8957A, 0x34302B, style.variant),
                            from: apex.y, to: 1, style: style, seasonTint: false)
    }

    /// The knoll's cobbles. The near layer clips them to the knoll and the
    /// front layer to its lip: one seeded set, so the two layers meet
    /// without a seam.
    private static func drawCobbles(in context: GraphicsContext, band: ScenesIIBand, style: GardenSceneStyle, clip: Path) {
        var rng = GardenSceneRandom(seed: GardenSceneKit.seed(staticSeed, 11))
        var stones = Path()
        let right = apex.x + knollHalfWidth
        for row in 0..<7 {
            let y = 0.855 + CGFloat(row) * 0.022
            var x: CGFloat = apex.x - knollHalfWidth + rng.next(0...0.01)
            while x < right {
                let width = band.pt(rng.next(4.5...7)), height = band.pt(rng.next(2.4...3.4))
                let center = CGPoint(x: band.x(x), y: band.y(y) + band.pt(rng.next(-0.6...0.6)))
                stones.addRoundedRect(in: CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height),
                                      cornerSize: CGSize(width: height * 0.45, height: height * 0.45))
                x += (width + band.pt(1.4)) / max(1, band.width)
            }
        }
        var cobbled = context
        cobbled.clip(to: clip)
        // Snow lies over the stones: they barely show through it.
        cobbled.opacity = style.season.hasSnow ? 0.3 : 1
        cobbled.fill(stones, with: .color(GardenSceneKit.rgb(0x9E8B70, 0x2E2924, style.variant).color.opacity(0.55)))
        cobbled.stroke(stones, with: .color(GardenSceneKit.rgb(0xCDBDA2, 0x4A433A, style.variant).color.opacity(0.5)), lineWidth: band.pt(0.5))
    }

    /// A point on the quadratic curve a → b with control `c`.
    private static func quad(_ a: CGPoint, _ c: CGPoint, _ b: CGPoint, at t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(x: u * u * a.x + 2 * u * t * c.x + t * t * b.x, y: u * u * a.y + 2 * u * t * c.y + t * t * b.y)
    }

    /// The arched bridge from (0.10, 0.70) to (0.42, 0.70), crown at 0.58.
    private static func drawBridge(in context: GraphicsContext, band: ScenesIIBand, style: GardenSceneStyle) {
        let variant = style.variant
        let lacquer = GardenSceneKit.rgb(0xA0522D, 0x3B2420, variant)
        let start = band.point(0.10, 0.70), crown = band.point(0.26, 0.46), end = band.point(0.42, 0.70)
        var deck = Path()
        deck.move(to: start)
        deck.addQuadCurve(to: end, control: crown)
        deck.addLine(to: band.point(0.405, 0.738))
        deck.addQuadCurve(to: band.point(0.115, 0.738), control: band.point(0.26, 0.50))
        deck.closeSubpath()

        // Its reflection on the water, mirrored about the abutments' foot.
        var mirrored = context
        mirrored.clip(to: Path(band.rect(0, riverTop, 1, quayTop)))
        mirrored.concatenate(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 2 * band.y(0.745)))
        mirrored.fill(deck, with: .color(lacquer.color.opacity(0.22)))

        let stone = GardenSceneKit.color(0x9C8B72, 0x2E2A2A, variant)
        for x0: CGFloat in [0.072, 0.392] {
            context.fill(Path(roundedRect: band.rect(x0, 0.688, x0 + 0.056, 0.748), cornerRadius: band.pt(1.5)), with: .color(stone))
        }
        context.fill(deck, with: .color(lacquer.color))
        var edge = Path()
        edge.move(to: start)
        edge.addQuadCurve(to: end, control: crown)
        context.stroke(edge, with: .color(GardenSceneKit.color(0xC8693F, 0x5A3328, variant)), lineWidth: band.pt(1))
        if style.season.hasSnow {
            GardenSceneKit.drawSnow(on: deck, depth: band.pt(2), in: context, variant: variant)
        }

        // The railing: posts on the deck, a rail riding 9 pt above it.
        let lift = band.pt(9)
        let deckPoints = (0...12).map { quad(start, crown, end, at: 0.04 + 0.92 * CGFloat($0) / 12) }
        let railPoints = deckPoints.map { CGPoint(x: $0.x, y: $0.y - lift) }
        var posts = Path()
        for (index, point) in deckPoints.enumerated() where index.isMultiple(of: 2) {
            posts.move(to: point)
            posts.addLine(to: railPoints[index])
        }
        context.stroke(posts, with: .color(GardenSceneKit.scaled(lacquer, 0.85).color), lineWidth: band.pt(1.2))
        var rail = Path()
        rail.addLines(railPoints)
        context.stroke(rail, with: .color(lacquer.color), style: StrokeStyle(lineWidth: band.pt(1.6), lineCap: .round, lineJoin: .round))
    }

    // MARK: Front: the knoll's lip, tufts, edge stones

    private static func drawFront(in context: GraphicsContext, band: ScenesIIBand, style: GardenSceneStyle) {
        let variant = style.variant
        let lip = GardenSceneKit.knoll(in: band.size, apex: ScenesII.lipApex(apex), halfWidth: knollHalfWidth)
        fillKnoll(lip, in: context, band: band, style: style)
        drawCobbles(in: context, band: band, style: style, clip: lip)

        var tufts = Path()
        let roots: [(CGPoint, CGFloat)] = [
            (CGPoint(x: 0.605, y: 0.874), 10), (CGPoint(x: 0.665, y: 0.884), 7), (CGPoint(x: 0.718, y: 0.872), 10),
            (CGPoint(x: 0.035, y: 0.955), 9), (CGPoint(x: 0.945, y: 0.952), 9)
        ]
        for (index, (root, height)) in roots.enumerated() {
            tufts.addPath(GardenSceneKit.tuft(at: band.point(root.x, root.y), width: band.pt(8), height: band.pt(height), blades: 6,
                                              seed: GardenSceneKit.seed(staticSeed, 17 + UInt64(index))))
        }
        context.fill(tufts, with: .color(ScenesII.grass(0x8FA85E, 0x2E3A26, style).color))

        // A row of rounded edge stones along the bottom of the band.
        var rng = GardenSceneRandom(seed: GardenSceneKit.seed(staticSeed, 13))
        let stone = GardenSceneKit.rgb(0x9C8B72, 0x2E2A2A, variant)
        var stones = Path()
        var x = band.x(-0.01)
        while x < band.x(1.01) {
            let width = band.pt(rng.next(10...16)), height = band.pt(rng.next(7...9))
            stones.addRoundedRect(in: CGRect(x: x, y: band.y(1) - height, width: width, height: height + band.pt(2)),
                                  cornerSize: CGSize(width: height * 0.4, height: height * 0.4))
            x += width + band.pt(1.2)
        }
        context.fill(stones, with: .color(stone.color))
        context.stroke(stones, with: .color(GardenSceneKit.scaled(stone, 0.65).color), lineWidth: band.pt(0.8))
        if style.season.hasSnow {
            GardenSceneKit.drawSnow(on: stones, depth: band.pt(1.8), in: context, variant: variant)
        }
    }

    // MARK: Ambient: lanterns, boat, reflections, peach petals

    /// The lantern line's points: both ends, then the seven lanterns.
    private static func lanternAnchors(_ band: ScenesIIBand) -> [CGPoint] {
        GardenSceneKit.catenary(from: band.point(lineStart.x, lineStart.y), to: band.point(lineEnd.x, lineEnd.y),
                                sag: lineSag * band.height, count: lanternCount + 2)
    }

    /// Where lantern `index` hangs and how far it swings (±4°, each on its
    /// own phase).
    private static func lanternPose(_ index: Int, anchors: [CGPoint], state: GardenAmbientState) -> (anchor: CGPoint, angle: Double) {
        let phase = ScenesII.phase(seed: state.seed, salt: 0x1A47, index: index)
        let angle = 4 * Double.pi / 180 * ScenesII.wave(GardenSceneKit.motionTime(state), hz: 0.3, phase: phase)
        return (anchors[index + 1], angle)
    }

    /// The middle of a lantern's silk body, 10 pt down its swinging cord.
    private static func lanternCenter(_ pose: (anchor: CGPoint, angle: Double), band: ScenesIIBand) -> CGPoint {
        let reach = band.pt(10)
        return CGPoint(x: pose.anchor.x - CGFloat(sin(pose.angle)) * reach, y: pose.anchor.y + CGFloat(cos(pose.angle)) * reach)
    }

    /// Seven silk lanterns on a line, glowing from golden hour.
    private static func drawLanterns(in context: GraphicsContext, band: ScenesIIBand, state: GardenAmbientState) {
        let lit = ScenesII.lightsOn(state.sky)
        let ink = GardenSceneKit.blend(0x3A2A2A, 0x140F12, darkness: state.sky.darkness)
        let line = GardenSceneKit.catenaryPath(from: band.point(lineStart.x, lineStart.y), to: band.point(lineEnd.x, lineEnd.y),
                                               sag: lineSag * band.height)
        context.stroke(line, with: .color(ink.color.opacity(0.6)), lineWidth: band.pt(0.8))

        let anchors = lanternAnchors(band)
        for index in 0..<lanternCount {
            let pose = lanternPose(index, anchors: anchors, state: state)
            GardenSceneKit.drawGlow(in: context, center: lanternCenter(pose, band: band), radius: band.pt(16),
                                    color: GardenRGB(0xFFB55A), opacity: 0.45 * lit)
            var lantern = context
            lantern.translateBy(x: pose.anchor.x, y: pose.anchor.y)
            lantern.rotate(by: .radians(pose.angle))
            drawLantern(in: lantern, band: band, silk: GardenRGB(lanternColors[index % lanternColors.count]), ink: ink,
                        lit: lit, darkness: state.sky.darkness)
        }
    }

    /// One lantern hanging from the origin: cord, caps, a silk body lit from
    /// within, ribs and a tassel.
    private static func drawLantern(in context: GraphicsContext, band: ScenesIIBand, silk: GardenRGB, ink: GardenRGB,
                                    lit: Double, darkness: Double) {
        var cord = Path()
        cord.move(to: .zero)
        cord.addLine(to: CGPoint(x: 0, y: band.pt(3)))
        context.stroke(cord, with: .color(ink.color), lineWidth: band.pt(0.7))

        let shade = silk.mixed(with: GardenSceneKit.scaled(silk, 0.35), darkness * (1 - lit))
        let core = shade.mixed(with: GardenRGB(0xFFE3B0), 0.55 * lit)
        let body = CGRect(x: -band.pt(4.5), y: band.pt(4), width: band.pt(9), height: band.pt(12))
        context.fill(Path(ellipseIn: body), with: .radialGradient(Gradient(colors: [core.color, shade.color]),
                                                                  center: CGPoint(x: 0, y: body.midY),
                                                                  startRadius: 0, endRadius: band.pt(6)))
        var ribs = Path(ellipseIn: body.insetBy(dx: band.pt(2.4), dy: 0))
        ribs.move(to: CGPoint(x: 0, y: body.minY))
        ribs.addLine(to: CGPoint(x: 0, y: body.maxY))
        context.stroke(ribs, with: .color(GardenSceneKit.scaled(shade, 0.7).color.opacity(0.5)), lineWidth: band.pt(0.5))
        context.fill(Path(CGRect(x: -band.pt(2.6), y: band.pt(3), width: band.pt(5.2), height: band.pt(1.6))), with: .color(ink.color))
        context.fill(Path(CGRect(x: -band.pt(2.2), y: body.maxY - band.pt(0.4), width: band.pt(4.4), height: band.pt(1.4))),
                     with: .color(ink.color))
        var tassel = Path()
        tassel.move(to: CGPoint(x: 0, y: body.maxY + band.pt(1)))
        tassel.addLine(to: CGPoint(x: 0, y: body.maxY + band.pt(4)))
        context.stroke(tassel, with: .color(shade.color.opacity(0.8)), lineWidth: band.pt(0.8))
    }

    /// Six lantern reflections shimmering on the river (seen through the
    /// bridge's arch where it crosses them).
    private static func drawReflections(in context: GraphicsContext, band: ScenesIIBand, state: GardenAmbientState) {
        let lit = ScenesII.lightsOn(state.sky)
        let clock = GardenSceneKit.motionTime(state)
        let anchors = lanternAnchors(band)
        for index in 0..<6 {
            let phase = ScenesII.phase(seed: state.seed, salt: 0x2EF1, index: index)
            let shimmer = 0.65 + 0.35 * ScenesII.wave(clock, hz: 0.9, phase: phase)
            let jitter = band.pt(1.2) * CGFloat(ScenesII.wave(clock, hz: 0.7, phase: phase + 0.3))
            let color = GardenRGB(lanternColors[index % lanternColors.count]).mixed(with: GardenRGB(0xFFB55A), lit)
            let streak = CGRect(x: anchors[index + 1].x - band.pt(1.2) + jitter, y: band.y(0.685 + 0.03 * CGFloat(index % 3)),
                                width: band.pt(2.4), height: band.pt(8))
            context.fill(Path(roundedRect: streak, cornerRadius: band.pt(1.2)),
                         with: .color(color.color.opacity(0.35 * shimmer * (0.35 + 0.65 * lit))))
        }
    }

    /// A crescent boat at (0.55, 0.74), bobbing ±1.5 pt; a bow lantern at night.
    private static func drawBoat(in context: GraphicsContext, band: ScenesIIBand, state: GardenAmbientState) {
        let clock = GardenSceneKit.motionTime(state)
        let phase = ScenesII.phase(seed: state.seed, salt: 0xB0A7, index: 0)
        let bob = band.pt(1.5) * CGFloat(ScenesII.wave(clock, hz: 0.45, phase: phase))
        let rock = 2 * Double.pi / 180 * ScenesII.wave(clock, hz: 0.45, phase: phase + 0.2)
        let darkness = state.sky.darkness
        let waterline = band.y(0.74)
        let s = band.pt(1)

        var ripple = Path()
        ripple.move(to: CGPoint(x: band.x(0.55) - 16 * s, y: waterline + 5 * s))
        ripple.addLine(to: CGPoint(x: band.x(0.55) + 16 * s, y: waterline + 5 * s))
        context.stroke(ripple, with: .color(GardenSceneKit.blend(0xFFFFFF, 0x5E86A8, darkness: darkness).color.opacity(0.3)),
                       style: StrokeStyle(lineWidth: band.pt(0.8), lineCap: .round))

        var boat = context
        boat.translateBy(x: band.x(0.55), y: waterline + bob)
        boat.rotate(by: .radians(rock))
        var canopy = Path()
        canopy.move(to: CGPoint(x: -7 * s, y: -1 * s))
        canopy.addQuadCurve(to: CGPoint(x: 7 * s, y: -1 * s), control: CGPoint(x: 0, y: -14 * s))
        canopy.closeSubpath()
        boat.fill(canopy, with: .color(GardenSceneKit.blend(0x8C6A4A, 0x2A2018, darkness: darkness).color))
        var hull = Path()
        hull.move(to: CGPoint(x: -19 * s, y: -4 * s))
        hull.addQuadCurve(to: CGPoint(x: 19 * s, y: -4 * s), control: CGPoint(x: 0, y: 1 * s))
        hull.addQuadCurve(to: CGPoint(x: -19 * s, y: -4 * s), control: CGPoint(x: 0, y: 9 * s))
        hull.closeSubpath()
        boat.fill(hull, with: .color(GardenSceneKit.blend(0x5A3A2A, 0x1E1612, darkness: darkness).color))

        let lit = ScenesII.lightsOn(state.sky)
        if lit > 0.01 {
            let bow = CGPoint(x: 15 * s, y: -8 * s)
            GardenSceneKit.drawGlow(in: boat, center: bow, radius: 7 * s, color: GardenRGB(0xFFB55A), opacity: 0.6 * lit)
            boat.fill(Path(ellipseIn: CGRect(x: bow.x - 1.4 * s, y: bow.y - 1.4 * s, width: 2.8 * s, height: 2.8 * s)),
                      with: .color(GardenRGB(0xFFD08A).color.opacity(lit)))
        }
    }

    /// Spring here drifts peach-blossom petals (C4) in place of the kit's
    /// cherry pink: up to 8, falling 14 pt/s with a ±6 pt sway.
    private static func drawPeachPetals(in context: GraphicsContext, band: ScenesIIBand, state: GardenAmbientState) {
        let clock = GardenSceneKit.motionTime(state)
        let elapsed = clock ?? 0
        let span = Double(band.height + band.pt(20))
        let width = Double(max(1, band.width))
        let petal = GardenRGB(0xF7A8C4).mixed(with: GardenRGB(0x8A5A70), state.sky.darkness * 0.6)
        for index in 0..<min(8, particleBudget) {
            let a = ScenesII.phase(seed: state.seed, salt: 0x9E7A, index: index)
            let b = ScenesII.phase(seed: state.seed, salt: 0x9E7B, index: index)
            let fall = (a * span + elapsed * Double(band.pt(14))).truncatingRemainder(dividingBy: span)
            let drift = (b * width + elapsed * Double(band.pt(4))).truncatingRemainder(dividingBy: width)
            let x = CGFloat(drift) + band.pt(6) * CGFloat(ScenesII.wave(clock, hz: 0.35, phase: a))
            let y = CGFloat(fall) - band.pt(10)
            let turn = 2 * Double.pi * (b + (elapsed * 0.2).truncatingRemainder(dividingBy: 1))
            let shape = Path(ellipseIn: CGRect(x: -band.pt(1.7), y: -band.pt(1.1), width: band.pt(3.4), height: band.pt(2.2)))
                .applying(CGAffineTransform(translationX: x, y: y).rotated(by: CGFloat(turn)))
            context.fill(shape, with: .color(petal.color.opacity(0.85)))
        }
    }
}

#Preview("Lantern Town · day") {
    GardenSceneSketch(scene: .lanternTown, localHour: 10, season: .spring)
        .frame(width: 351, height: 208)
        .border(Color.gray.opacity(0.4))
}

#Preview("Lantern Town · night") {
    GardenSceneSketch(scene: .lanternTown, localHour: 21, season: .summer)
        .frame(width: 351, height: 208)
        .border(Color.gray.opacity(0.4))
}

// MARK: - Scenes II shared drawing

/// C4 positions are fractions of the band's width and height; painters
/// draw in band points (GardenSceneKit's convention). On the far layer the
/// art must also cover the parallax bleed, so `minX…maxX` spans
/// GardenSceneKit.farSpan (−0.175…1.175); elsewhere it is the band, 0…1.
nonisolated struct ScenesIIBand {
    let size: CGSize
    let minX: CGFloat
    let maxX: CGFloat

    init(_ size: CGSize, layer: GardenBackdropLayer? = nil) {
        self.size = size
        if layer == .far, size.width > 0 {
            let span = GardenSceneKit.farSpan(in: size)
            minX = span.lowerBound / size.width
            maxX = span.upperBound / size.width
        } else {
            minX = 0
            maxX = 1
        }
    }

    var width: CGFloat { size.width }
    var height: CGFloat { size.height }

    func x(_ fraction: CGFloat) -> CGFloat { fraction * size.width }
    func y(_ fraction: CGFloat) -> CGFloat { fraction * size.height }
    func point(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint { CGPoint(x: x(fx), y: y(fy)) }

    /// The rectangle between two corners given as band fractions.
    func rect(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> CGRect {
        CGRect(x: x(x0), y: y(y0), width: (x1 - x0) * size.width, height: (y1 - y0) * size.height)
    }

    /// C4's point sizes are for the 208 pt band; they shrink with the 176
    /// and 168 pt bands so a prop keeps its place against the landscape.
    func pt(_ value: CGFloat) -> CGFloat { value * size.height / 208 }
}

/// What the Scenes II painters share beyond GardenSceneKit.
nonisolated enum ScenesII {
    // MARK: Ground

    /// The front layer redraws the knoll with its apex this far lower
    /// (fraction of H): the lip hides the trunk's last few points, so the
    /// tree stands in the ground rather than on it.
    static func lipApex(_ apex: CGPoint) -> CGPoint {
        CGPoint(x: apex.x, y: apex.y + 0.018)
    }

    /// Fills a ground region with a vertical gradient between band rows `y0`
    /// and `y1`: C3's season tint (GardenSceneKit.ground) unless
    /// `seasonTint` is false (stone, or a fill that already is the season),
    /// and in winter snow over the top 40%. Unlike a fill over the path's
    /// own bounds, the gradient is anchored in band rows, so a near-layer
    /// knoll and its front-layer lip meet without a seam.
    static func fillGround(_ path: Path, in context: GraphicsContext, band: ScenesIIBand, top: GardenRGB, bottom: GardenRGB,
                           from y0: CGFloat, to y1: CGFloat, style: GardenSceneStyle, seasonTint: Bool = true) {
        let upper = seasonTint ? GardenSceneKit.ground(top, season: style.season, variant: style.variant) : top
        let lower = seasonTint ? GardenSceneKit.ground(bottom, season: style.season, variant: style.variant) : bottom
        let stops: [Gradient.Stop]
        if style.season.hasSnow {
            stops = [Gradient.Stop(color: snowTop(style.variant).color, location: 0),
                     Gradient.Stop(color: snowBottom(style.variant).color, location: 0.36),
                     Gradient.Stop(color: upper.mixed(with: lower, 0.4).color, location: 0.44),
                     Gradient.Stop(color: lower.color, location: 1)]
        } else {
            stops = [Gradient.Stop(color: upper.color, location: 0), Gradient.Stop(color: lower.color, location: 1)]
        }
        context.fill(path, with: .linearGradient(Gradient(stops: stops),
                                                 startPoint: CGPoint(x: 0, y: band.y(y0)),
                                                 endPoint: CGPoint(x: 0, y: band.y(y1))))
    }

    /// Grass and tufts: the season's ground tint, frosted under snow.
    static func grass(_ day: UInt32, _ night: UInt32, _ style: GardenSceneStyle) -> GardenRGB {
        let blade = GardenSceneKit.ground(GardenSceneKit.rgb(day, night, style.variant), season: style.season, variant: style.variant)
        return style.season.hasSnow ? blade.mixed(with: snowBottom(style.variant), 0.35) : blade
    }

    /// Distant land takes only part of the season's tint.
    static func distant(_ color: GardenRGB, _ style: GardenSceneStyle, amount: Double) -> GardenRGB {
        color.mixed(with: GardenSceneKit.ground(color, season: style.season, variant: style.variant), amount)
    }

    static func snowTop(_ variant: GardenSkyVariant) -> GardenRGB { GardenSceneKit.rgb(0xEEF3F8, 0x9AA7C0, variant) }
    static func snowBottom(_ variant: GardenSkyVariant) -> GardenRGB { GardenSceneKit.rgb(0xDCE6EF, 0x7D8AA6, variant) }

    // MARK: Ambient

    /// C11: at most 30 moving primitives per scene. The sky pass takes six
    /// (sun or moon, twinkling stars, clouds); `sceneLife` is the scene's
    /// own; season particles get the rest.
    static func particleBudget(sceneLife: Int) -> Int {
        max(0, 30 - 6 - sceneLife)
    }

    /// Sun or moon, stars and clouds (C3), the same in every scene.
    static func drawSky(in context: GraphicsContext, size: CGSize, state: GardenAmbientState) {
        let time = GardenSceneKit.motionTime(state)
        GardenSceneKit.drawCelestial(in: context, size: size, sky: state.sky, time: time)
        GardenSceneKit.drawClouds(in: context, size: size, sky: state.sky, time: time, seed: state.seed)
    }

    /// A stateless draw in [0, 1) for element `index` of an ambient stream:
    /// per-tree phases without replaying a generator every frame.
    static func phase(seed: UInt64, salt: UInt64, index: Int) -> Double {
        var rng = GardenSceneRandom(seed: GardenSceneKit.seed(GardenSceneKit.seed(seed, salt), UInt64(index) &+ 1))
        return rng.next()
    }

    /// 0 by day; lanterns and lit windows come on from golden hour and are
    /// full by dusk.
    static func lightsOn(_ sky: GardenSkyState) -> Double {
        smoothstep(0.05, 0.35, sky.darkness)
    }

    /// sin(2π(hz·t + phase)) for sways and bobs; 0, the rest pose, without
    /// a clock (Reduce Motion).
    static func wave(_ clock: TimeInterval?, hz: Double, phase: Double) -> Double {
        guard let clock else { return 0 }
        return sin(2 * .pi * ((clock * hz).truncatingRemainder(dividingBy: 1) + phase))
    }

    /// 0…1 for shimmers and flickers; a steady 0.5 without a clock.
    static func pulse(_ clock: TimeInterval?, hz: Double, phase: Double) -> Double {
        0.5 + 0.5 * wave(clock, hz: hz, phase: phase)
    }

    static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let t = min(1, max(0, (x - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }

    /// Three soft puffs rising and widening from `origin` (band fractions),
    /// one every two seconds, each living six; at rest without a clock.
    static func drawSmoke(in context: GraphicsContext, band: ScenesIIBand, origin: CGPoint, clock: TimeInterval?, seed: UInt64,
                          color: GardenRGB, opacity: Double) {
        guard opacity > 0.01 else { return }
        let life = 6.0
        for index in 0..<3 {
            let age: Double
            if let clock {
                age = (clock / life + Double(index) / 3).truncatingRemainder(dividingBy: 1)
            } else {
                age = Double(index) / 3 + 0.12
            }
            let drift = phase(seed: seed, salt: 0x5A0E, index: index)
            let center = CGPoint(x: band.x(origin.x) + band.pt(CGFloat((4 + 6 * drift) * age)) + band.pt(2) * CGFloat(sin(age * 5 + drift * 6)),
                                 y: band.y(origin.y) - band.pt(34) * CGFloat(age))
            GardenSceneKit.drawGlow(in: context, center: center, radius: band.pt(3 + 6 * CGFloat(age)), color: color,
                                    opacity: opacity * min(1, age / 0.12) * (1 - age))
        }
    }
}
