//
//  CityLightsScene.swift
//  Coupley
//
//  Our Garden, P5 (Scenes I): City Lights (C4 scene 3; cafés, restaurants,
//  bars, theatres, hotels, first dates). A rooftop terrace above a skyline,
//  string lights overhead; the tree stands in a wooden planter at
//  (0.60, 0.80), its front face drawn over the trunk base.
//

import CoreGraphics
import SwiftUI

nonisolated struct CityLightsScene: GardenScenePainting {
    init() {}

    var scene: GardenSceneID { .cityLights }

    private typealias Kit = GardenSceneKit

    private struct Building {
        var rect: CGRect
        var antenna: Bool
        var stepped: Bool
    }

    /// Six closer buildings: left edge, right edge and top, as band fractions.
    private static let closeBuildings: [(CGFloat, CGFloat, CGFloat)] = [
        (-0.02, 0.13, 0.50), (0.13, 0.24, 0.58), (0.24, 0.33, 0.66),
        (0.74, 0.85, 0.54), (0.85, 0.95, 0.47), (0.95, 1.03, 0.60)
    ]
    private static let planter = (left: CGFloat(0.49), right: CGFloat(0.71), top: CGFloat(0.80), bottom: CGFloat(0.90))
    private static let parapetTop: CGFloat = 0.88
    private static let wireFrom = CGPoint(x: 0, y: 0.30), wireTo = CGPoint(x: 1, y: 0.26)
    private static let wireSag: CGFloat = 0.10
    private static let bulbCount = 11

    // MARK: Skyline (seeded by the scene, shared by the far layer and the toggling window)

    /// 14 seeded buildings on base 0.66 spanning the far layer's full width;
    /// two carry antennas, one has a stepped top.
    private static func skyline(in size: CGSize) -> [Building] {
        var rng = GardenSceneRandom(seed: GardenSceneStyle.staticSeed(for: .cityLights))
        let span = Kit.farSpan(in: size)
        let widths = (0..<14).map { _ in rng.next(0.05...0.10) as CGFloat }
        let heights = (0..<14).map { _ in rng.next(0.12...0.38) as CGFloat }
        let stretch = (span.upperBound - span.lowerBound) / (widths.reduce(0, +) * size.width)
        let tallest = heights.indices.sorted { heights[$0] > heights[$1] }
        let base = size.height * 0.66
        var x = span.lowerBound
        var buildings: [Building] = []
        for i in 0..<14 {
            let width = widths[i] * size.width * stretch, height = heights[i] * size.height
            buildings.append(Building(rect: CGRect(x: x, y: base - height, width: width, height: height + size.height * 0.08),
                                      antenna: i == tallest[0] || i == tallest[2], stepped: i == tallest[1]))
            x += width
        }
        return buildings
    }

    /// The window grid of a building: 2.5 × 3.5 pt cells on a 5 × 7 pt pitch.
    private static func windowCells(in rect: CGRect, base: CGFloat) -> [CGRect] {
        var cells: [CGRect] = []
        var y = rect.minY + 4
        while y + 3.5 < base - 3 {
            var x = rect.minX + 2.5
            while x + 2.5 < rect.maxX - 2 {
                cells.append(CGRect(x: x, y: y, width: 2.5, height: 3.5))
                x += 5
            }
            y += 7
        }
        return cells
    }

    /// The one skyline window that switches on and off at night (ambient);
    /// the static art leaves it dark.
    private static func togglingWindow(in size: CGSize) -> CGRect? {
        let buildings = skyline(in: size)
        guard let tall = buildings.indices.max(by: { buildings[$0].rect.height < buildings[$1].rect.height }) else { return nil }
        let cells = windowCells(in: buildings[tall].rect, base: size.height * 0.66)
        return cells.isEmpty ? nil : cells[min(cells.count - 1, 5)]
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
        let night = variant == .night
        let haze = Kit.rgb(0xA6B6C9, 0x1A2236, variant)
        let base = size.height * 0.66
        let span = Kit.farSpan(in: size)
        context.fill(Path(CGRect(x: span.lowerBound, y: base, width: span.upperBound - span.lowerBound, height: size.height - base)),
                     with: .color(haze.color))

        var rng = GardenSceneRandom(seed: Kit.seed(GardenSceneStyle.staticSeed(for: scene), 0x817D))
        let toggling = Self.togglingWindow(in: size)
        var lit = Path(), panes = Path(), roofs = Path(), masts = Path()
        for (i, building) in Self.skyline(in: size).enumerated() {
            let r = building.rect
            var shape = Path(r)
            if building.stepped {
                shape.addRect(CGRect(x: r.minX + r.width * 0.15, y: r.minY - r.height * 0.10, width: r.width * 0.70, height: r.height * 0.10 + 1))
                shape.addRect(CGRect(x: r.minX + r.width * 0.32, y: r.minY - r.height * 0.17, width: r.width * 0.36, height: r.height * 0.07 + 1))
                roofs.addRect(CGRect(x: r.minX + r.width * 0.32, y: r.minY - r.height * 0.17, width: r.width * 0.36, height: 2))
            }
            roofs.addRect(CGRect(x: r.minX, y: r.minY, width: r.width, height: 2))
            if building.antenna {
                masts.addRect(CGRect(x: r.midX - 0.5, y: r.minY - size.height * 0.06, width: 1, height: size.height * 0.06))
                masts.addEllipse(in: CGRect(x: r.midX - 1.2, y: r.minY - size.height * 0.06 - 1.2, width: 2.4, height: 2.4))
            }
            // Alternate shades so neighbours read as separate towers.
            let shade = Kit.scaled(haze, i.isMultiple(of: 2) ? 1 : (night ? 1.12 : 0.95))
            context.fill(shape, with: .color(shade.color))
            for cell in Self.windowCells(in: r, base: base) where cell != toggling {
                if night {
                    if rng.next() < 0.35 { lit.addRect(cell) }
                } else {
                    panes.addRect(cell)
                }
            }
        }
        context.fill(masts, with: .color(Kit.scaled(haze, night ? 1.3 : 0.85).color))
        if night {
            context.fill(lit, with: .color(GardenRGB(0xFFD27A).color.opacity(0.9)))
        } else {
            context.fill(panes, with: .color(GardenRGB(0x8798AE).color.opacity(0.35)))
        }
        if style.season.hasSnow {
            context.fill(roofs, with: .color(Kit.color(0xEEF3F8, 0x9AA7C0, variant)))
        }
    }

    private func drawNear(in context: GraphicsContext, size: CGSize, style: GardenSceneStyle) {
        let variant = style.variant
        let night = variant == .night
        var rng = GardenSceneRandom(seed: Kit.seed(GardenSceneStyle.staticSeed(for: scene), 0x4EA2))
        let wall = Kit.rgb(0x8797AD, 0x141B2C, variant)
        var lit = Path(), panes = Path(), roofs = Path()
        for (i, b) in Self.closeBuildings.enumerated() {
            let rect = CGRect(x: size.width * b.0, y: size.height * b.2, width: size.width * (b.1 - b.0), height: size.height * (0.86 - b.2))
            context.fill(Path(rect), with: .color(Kit.scaled(wall, i.isMultiple(of: 2) ? 1 : 0.92).color))
            roofs.addRect(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 2.5))
            var y = rect.minY + 6
            while y + 4.5 < rect.maxY - 4 {
                var x = rect.minX + 4
                while x + 3 < rect.maxX - 3 {
                    let cell = CGRect(x: x, y: y, width: 3, height: 4.5)
                    if night {
                        if rng.next() < 0.18 { lit.addRect(cell) }
                    } else {
                        panes.addRect(cell)
                    }
                    x += 7
                }
                y += 9
            }
        }
        if night {
            context.fill(lit, with: .color(GardenRGB(0xFFD27A).color.opacity(0.85)))
        } else {
            context.fill(panes, with: .color(GardenRGB(0x6F7F96).color.opacity(0.5)))
        }
        if style.season.hasSnow { context.fill(roofs, with: .color(Kit.color(0xEEF3F8, 0x9AA7C0, variant))) }
        drawWaterTower(in: context, size: size, variant: variant)

        // The terrace floor behind the parapet.
        context.fill(Path(CGRect(x: 0, y: size.height * 0.82, width: size.width, height: size.height * 0.10)),
                     with: .color(Kit.color(0xB5A493, 0x26232D, variant)))

        // A bench silhouette at (0.25, 0.86).
        let bench = Kit.color(0x6B5A4E, 0x1E1A24, variant)
        var seat = Path()
        let left = size.width * 0.21, width = size.width * 0.08
        seat.addRect(CGRect(x: left, y: size.height * 0.826, width: width, height: 2))
        seat.addRect(CGRect(x: left, y: size.height * 0.846, width: width, height: 2))
        for x in [left + 1, left + width - 2.5] {
            seat.addRect(CGRect(x: x, y: size.height * 0.826, width: 1.5, height: size.height * 0.05))
        }
        context.fill(seat, with: .color(bench))

        // The planter's back rim and soil, behind the trunk.
        let p = Self.planter
        context.fill(Path(CGRect(x: size.width * p.left, y: size.height * p.top - 3, width: size.width * (p.right - p.left), height: 4)),
                     with: .color(Kit.color(0xB07A4E, 0x3A2A22, variant)))
        context.fill(Path(CGRect(x: size.width * p.left + 2, y: size.height * p.top - 1, width: size.width * (p.right - p.left) - 4, height: 3)),
                     with: .color(Kit.color(0x5A3E2B, 0x1E1612, variant)))
    }

    /// A water tower on the second close building's roof.
    private func drawWaterTower(in context: GraphicsContext, size: CGSize, variant: GardenSkyVariant) {
        let roof = size.height * Self.closeBuildings[1].2
        let left = size.width * 0.165, right = size.width * 0.205
        var tower = Path()
        tower.addRect(CGRect(x: left, y: roof - size.height * 0.075, width: right - left, height: size.height * 0.045))
        tower.move(to: CGPoint(x: left - 2, y: roof - size.height * 0.075))
        tower.addLine(to: CGPoint(x: (left + right) / 2, y: roof - size.height * 0.105))
        tower.addLine(to: CGPoint(x: right + 2, y: roof - size.height * 0.075))
        tower.closeSubpath()
        for x in [left + 1, right - 2.2] {
            tower.addRect(CGRect(x: x, y: roof - size.height * 0.03, width: 1.2, height: size.height * 0.03))
        }
        context.fill(tower, with: .color(Kit.color(0x6B5A4E, 0x1E1A22, variant)))
    }

    private func drawFront(in context: GraphicsContext, size: CGSize, style: GardenSceneStyle) {
        let variant = style.variant
        let snowy = style.season.hasSnow
        let p = Self.planter
        let face = CGRect(x: size.width * p.left, y: size.height * p.top, width: size.width * (p.right - p.left),
                          height: size.height * (p.bottom - p.top))
        context.fill(Path(face), with: .color(Kit.color(0x9C6B43, 0x3A2A22, variant)))
        var planks = Path()
        for y in [CGFloat(0.825), 0.85, 0.875] {
            planks.addRect(CGRect(x: face.minX, y: size.height * y, width: face.width, height: 1))
        }
        context.fill(planks, with: .color(Kit.color(0x7E5434, 0x2A1F1A, variant)))
        let lip = Path(CGRect(x: face.minX - 2, y: face.minY - 1, width: face.width + 4, height: 3.5))
        context.fill(lip, with: .color(Kit.color(0xB07A4E, 0x4A3426, variant)))
        if snowy {
            context.fill(Path(roundedRect: CGRect(x: face.minX - 2, y: face.minY - 2.5, width: face.width + 4, height: 2.5),
                              cornerRadius: 1.2),
                         with: .color(Kit.color(0xEEF3F8, 0x9AA7C0, variant)))
        }

        // The parapet with its coping line.
        let top = size.height * Self.parapetTop
        context.fill(Path(CGRect(x: 0, y: top, width: size.width, height: size.height - top)),
                     with: .color(Kit.color(0xC9B8A6, 0x2D2A35, variant)))
        var joints = Path()
        var x: CGFloat = 14
        while x < size.width {
            joints.addRect(CGRect(x: x, y: top + 4, width: 0.8, height: size.height - top - 4))
            x += 28
        }
        context.fill(joints, with: .color(Kit.color(0xB3A291, 0x26232E, variant)))
        let coping = Path(CGRect(x: 0, y: top - 1, width: size.width, height: 4))
        context.fill(coping, with: .color(Kit.color(0xDCCDBD, 0x3A3644, variant)))
        context.fill(Path(CGRect(x: 0, y: top + 3, width: size.width, height: 0.8)),
                     with: .color(Kit.color(0xA8988A, 0x1F1C27, variant)))
        if snowy {
            context.fill(Path(roundedRect: CGRect(x: 0, y: top - 3.5, width: size.width, height: 3), cornerRadius: 1.5),
                         with: .color(Kit.color(0xEEF3F8, 0x9AA7C0, variant)))
        }
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
            if state.sky.darkness > 0.5, let window = Self.togglingWindow(in: size),
               Int(((time ?? 0) / 4.2).rounded(.down)).isMultiple(of: 2) {
                context.fill(Path(window), with: .color(GardenRGB(0xFFD27A).color.opacity(0.9)))
            }
            drawStringLights(in: context, size: size, state: state, time: time)
        case .front:
            // A rooftop has no grass, so no fireflies; spring petals, autumn leaves and snow blow across.
            Kit.drawSeasonParticles(in: context, size: size, state: state, maxCount: state.season == .summer ? 0 : 24)
        }
    }

    private func bulbs(in size: CGSize) -> [CGPoint] {
        Kit.catenary(from: Kit.point(Self.wireFrom.x, Self.wireFrom.y, in: size), to: Kit.point(Self.wireTo.x, Self.wireTo.y, in: size),
                     sag: size.height * Self.wireSag, count: Self.bulbCount)
    }

    /// The wire and its eleven bulbs: unlit cream by day; from golden hour
    /// lit gold with an 8 pt glow, each twinkling (0.75–1.0 at 0.8 Hz) on its
    /// own phase. One fill per lit bulb.
    private func drawStringLights(in context: GraphicsContext, size: CGSize, state: GardenAmbientState, time: TimeInterval?) {
        let wire = Kit.catenaryPath(from: Kit.point(Self.wireFrom.x, Self.wireFrom.y, in: size),
                                    to: Kit.point(Self.wireTo.x, Self.wireTo.y, in: size), sag: size.height * Self.wireSag)
        context.stroke(wire, with: .color(Kit.blend(0x3A3A44, 0x0E1018, darkness: state.sky.darkness).color.opacity(0.6)),
                       lineWidth: 0.8)
        let lit = min(1, max(0, (state.sky.darkness - 0.05) / 0.10))
        let points = bulbs(in: size)
        guard lit > 0.01 else {
            var unlit = Path()
            for p in points { unlit.addEllipse(in: CGRect(x: p.x - 2.4, y: p.y - 2.4 + 2, width: 4.8, height: 4.8)) }
            context.fill(unlit, with: .color(GardenRGB(0xFFF3D6).color.opacity(0.6)))
            return
        }
        var rng = GardenSceneRandom(seed: Kit.seed(state.seed, 0xB01B))
        for p in points {
            let phase = rng.next(0...(2 * Double.pi))
            let twinkle = time.map { 0.75 + 0.25 * (0.5 + 0.5 * sin(2 * .pi * 0.8 * $0 + phase)) } ?? 1
            drawBulb(in: context, at: CGPoint(x: p.x, y: p.y + 2), lit: lit, alpha: twinkle, glow: 8)
        }
    }

    private func drawBulb(in context: GraphicsContext, at center: CGPoint, lit: Double, alpha: Double, glow: CGFloat) {
        let core = GardenRGB(0xFFF3D6).mixed(with: GardenRGB(0xFFD27A), lit).color
        let halo = GardenRGB(0xFFD27A).color
        let radius = 2.4 + glow * CGFloat(lit)
        let edge = 2.4 / radius
        let gradient = Gradient(stops: [
            .init(color: core.opacity(alpha), location: 0),
            .init(color: core.opacity(alpha), location: edge),
            .init(color: halo.opacity(0.45 * lit * alpha), location: min(1, edge + 0.04)),
            .init(color: halo.opacity(0), location: 1)
        ])
        context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                     with: .radialGradient(gradient, center: center, startRadius: 0, endRadius: radius))
    }

    // MARK: Watering accent

    /// The string lights flicker on, bulb by bulb, left to right.
    func drawWateringAccent(in context: GraphicsContext, size: CGSize, state: GardenAmbientState, progress: Double) {
        guard size.width > 0, size.height > 0 else { return }
        let p = min(1, max(0, progress))
        for (i, bulb) in bulbs(in: size).enumerated() {
            let since = p - 0.06 * Double(i)
            guard since > 0 else { break }
            // Two quick flickers as each bulb catches, then steady, easing out at the end.
            let flicker = since < 0.08 ? (Int(since / 0.02).isMultiple(of: 2) ? 1.0 : 0.35) : 1.0
            drawBulb(in: context, at: CGPoint(x: bulb.x, y: bulb.y + 2), lit: 1, alpha: flicker * (1 - 0.6 * max(0, p - 0.7) / 0.3),
                     glow: 10)
        }
    }
}

#Preview("City Lights · day") {
    GardenSceneSketch(scene: .cityLights, localHour: 13, season: .spring)
        .frame(width: 351, height: 208)
        .border(Color.gray.opacity(0.4))
}

#Preview("City Lights · night") {
    GardenSceneSketch(scene: .cityLights, localHour: 21, season: .autumn)
        .frame(width: 351, height: 208)
        .border(Color.gray.opacity(0.4))
}
