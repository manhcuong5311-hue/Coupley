//
//  RelationshipTreeCanvas.swift
//  Coupley
//
//  The hero of the Time Tree feature. A procedurally drawn tree that
//  grows alongside the relationship: trunk thickens, branches multiply,
//  leaves fill in, blossoms appear, golden fruits ripen, and a crown
//  ring lights up for mature couples.
//
//  Implementation notes:
//   - SwiftUI `Canvas` for the geometry (zero UIImageView weight).
//   - `TimelineView(.animation)` drives a continuous phase value that
//     powers the gentle sway, leaf flutter, and ambient glow pulse.
//     This is intentionally subtle — we want it to feel alive, not
//     animated-for-the-sake-of-it.
//   - Tree topology is deterministic: branch positions, leaf positions,
//     blossom positions are seeded from the days-together value so the
//     same tree grows the same way every render — no flicker.
//   - Memory stars float around the tree, one per visible memory. Their
//     orbits are gentle ellipses with seeded phase offsets so the
//     constellation feels custom to the couple.
//

import SwiftUI

// MARK: - Public View

struct RelationshipTreeCanvas: View {

    let stage: TreeGrowthStage
    let season: TreeSeason
    let daysTogether: Int
    /// Memories drive the floating star count and their seeded positions.
    let memoryCount: Int
    /// Whether to draw the persistent crown ring above the canopy.
    /// (Per-anniversary celebration crowns are a separate overlay.)
    let crownActive: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas(rendersAsynchronously: true) { ctx, size in
                draw(in: ctx, size: size, time: t)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - Drawing entry point

    private func draw(in ctx: GraphicsContext, size: CGSize, time: TimeInterval) {
        var ctx = ctx
        let center = CGPoint(x: size.width / 2, y: size.height)
        let height = size.height

        // Soft ambient glow behind the tree
        drawAmbientGlow(ctx: &ctx, size: size, time: time)

        // Crown ring (the persistent one — long-lived couples)
        if crownActive {
            drawCrownRing(ctx: &ctx, size: size, time: time)
        }

        // Trunk + branches + canopy + decorations
        drawTrunkAndBranches(ctx: &ctx, size: size, center: center, height: height, time: time)
        drawCanopy(ctx: &ctx, size: size, center: center, time: time)
        drawBlossoms(ctx: &ctx, size: size, center: center, time: time)
        drawFruits(ctx: &ctx, size: size, center: center, time: time)

        // Floating memory stars
        drawMemoryStars(ctx: &ctx, size: size, time: time)
    }

    // MARK: - Ambient Glow

    private func drawAmbientGlow(ctx: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let pulse = (sin(time * 0.6) + 1) / 2     // 0…1
        let alpha = 0.10 + pulse * 0.08

        let glowRect = CGRect(
            x: size.width * 0.05,
            y: size.height * 0.10,
            width: size.width * 0.90,
            height: size.height * 0.80
        )
        let path = Path(ellipseIn: glowRect)
        ctx.addFilter(.blur(radius: 40))
        ctx.fill(path, with: .color(Color(red: 1.0, green: 0.78, blue: 0.65).opacity(alpha)))
        ctx.addFilter(.blur(radius: 0)) // reset
    }

    // MARK: - Crown ring

    private func drawCrownRing(ctx: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let cx = size.width / 2
        let cy = size.height * 0.18
        let radius = size.width * 0.34

        // Soft halo
        let halo = Path(ellipseIn: CGRect(
            x: cx - radius * 1.15,
            y: cy - radius * 0.55,
            width: radius * 2.3,
            height: radius * 1.10
        ))
        ctx.fill(halo, with: .color(Color(red: 1.0, green: 0.85, blue: 0.45).opacity(0.10)))

        // Crown arch
        var arch = Path()
        let archRect = CGRect(
            x: cx - radius,
            y: cy - radius * 0.45,
            width: radius * 2,
            height: radius * 0.9
        )
        arch.addArc(
            center: CGPoint(x: archRect.midX, y: archRect.midY),
            radius: radius,
            startAngle: .degrees(200),
            endAngle: .degrees(340),
            clockwise: false
        )
        ctx.stroke(
            arch,
            with: .linearGradient(
                Gradient(colors: [
                    Color(red: 1.0, green: 0.85, blue: 0.40).opacity(0.85),
                    Color(red: 0.95, green: 0.55, blue: 0.30).opacity(0.85)
                ]),
                startPoint: CGPoint(x: archRect.minX, y: archRect.midY),
                endPoint: CGPoint(x: archRect.maxX, y: archRect.midY)
            ),
            lineWidth: 2
        )

        // Crown points
        let pointCount = 5
        for i in 0..<pointCount {
            let progress = CGFloat(i) / CGFloat(pointCount - 1)
            let angle = .pi - (progress * .pi * 0.8 + .pi * 0.1)
            let px = cx + radius * cos(angle)
            let py = cy - radius * sin(angle) * 0.8
            let twinkle = (sin(time * 1.2 + Double(i) * 0.7) + 1) / 2
            let pointHeight: CGFloat = 8 + CGFloat(twinkle) * 4

            var point = Path()
            point.move(to: CGPoint(x: px, y: py))
            point.addLine(to: CGPoint(x: px - 4, y: py + 4))
            point.addLine(to: CGPoint(x: px + 4, y: py + 4))
            point.closeSubpath()
            ctx.fill(point, with: .color(Color(red: 1.0, green: 0.85, blue: 0.45).opacity(0.95)))

            // Vertical spike from crown tip
            var spike = Path()
            spike.move(to: CGPoint(x: px, y: py))
            spike.addLine(to: CGPoint(x: px, y: py - pointHeight))
            ctx.stroke(
                spike,
                with: .color(Color(red: 1.0, green: 0.85, blue: 0.45).opacity(0.85)),
                lineWidth: 2
            )

            // Twinkle dot at the tip
            let dotSize: CGFloat = 3 + CGFloat(twinkle) * 2
            let dot = Path(ellipseIn: CGRect(
                x: px - dotSize / 2,
                y: py - pointHeight - dotSize / 2,
                width: dotSize,
                height: dotSize
            ))
            ctx.fill(dot, with: .color(Color(red: 1.0, green: 0.95, blue: 0.70).opacity(0.95)))
        }
    }

    // MARK: - Trunk + branches

    private func drawTrunkAndBranches(
        ctx: inout GraphicsContext,
        size: CGSize,
        center: CGPoint,
        height: CGFloat,
        time: TimeInterval
    ) {
        let trunkScale = stage.trunkScale
        let trunkHeight = height * 0.55 * trunkScale
        let trunkWidth: CGFloat = max(8, 22 * trunkScale)

        let trunkBase = CGPoint(x: center.x, y: height * 0.95)
        let trunkTop  = CGPoint(x: center.x, y: trunkBase.y - trunkHeight)

        // Subtle sway angle (radians) — branches at the top sway more
        // than the trunk base.
        let sway = sin(time * 0.5) * 0.025

        // Trunk path — gentle curve from base to top.
        var trunk = Path()
        let cx = trunkBase.x + sin(time * 0.3) * 1.2
        trunk.move(to: CGPoint(x: trunkBase.x - trunkWidth / 2, y: trunkBase.y))
        trunk.addQuadCurve(
            to: CGPoint(x: trunkTop.x - trunkWidth * 0.3, y: trunkTop.y),
            control: CGPoint(x: cx - trunkWidth, y: trunkBase.y - trunkHeight * 0.4)
        )
        trunk.addLine(to: CGPoint(x: trunkTop.x + trunkWidth * 0.3, y: trunkTop.y))
        trunk.addQuadCurve(
            to: CGPoint(x: trunkBase.x + trunkWidth / 2, y: trunkBase.y),
            control: CGPoint(x: cx + trunkWidth, y: trunkBase.y - trunkHeight * 0.4)
        )
        trunk.closeSubpath()

        ctx.fill(
            trunk,
            with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.32, green: 0.22, blue: 0.16),
                    Color(red: 0.48, green: 0.34, blue: 0.24)
                ]),
                startPoint: CGPoint(x: trunkBase.x, y: trunkBase.y),
                endPoint: CGPoint(x: trunkTop.x, y: trunkTop.y)
            )
        )

        // Highlight stroke on the right side for dimensionality
        var highlight = Path()
        highlight.move(to: CGPoint(x: trunkBase.x + trunkWidth * 0.35, y: trunkBase.y - trunkHeight * 0.05))
        highlight.addQuadCurve(
            to: CGPoint(x: trunkTop.x + trunkWidth * 0.2, y: trunkTop.y + trunkHeight * 0.05),
            control: CGPoint(x: trunkBase.x + trunkWidth * 0.6, y: trunkBase.y - trunkHeight * 0.5)
        )
        ctx.stroke(highlight, with: .color(Color.white.opacity(0.10)), lineWidth: 2)

        // Branches — symmetric pairs that fan out from the upper portion
        // of the trunk. Branch count is determined by the stage.
        let branchCount = stage.branchCount
        guard branchCount > 0 else { return }

        for i in 0..<branchCount {
            let progress = branchCount == 1 ? 0.5 : Double(i) / Double(branchCount - 1)
            let yOffset = trunkHeight * (0.18 + progress * 0.78)
            let attachment = CGPoint(x: trunkTop.x, y: trunkBase.y - yOffset)

            // Alternate left / right
            let leftSide = (i % 2 == 0)
            let direction: CGFloat = leftSide ? -1 : 1

            // Branch length tapers — middle branches are longest
            let centerDistance = abs(progress - 0.5) * 2 // 0…1
            let baseLength = trunkHeight * 0.65 * (1 - centerDistance * 0.4) * trunkScale
            let branchLen = baseLength + CGFloat(i % 3) * 6
            let lift = CGFloat(0.4 + progress * 0.4)
            let endPoint = CGPoint(
                x: attachment.x + direction * branchLen + sin(time * 0.4 + Double(i)) * 1.5,
                y: attachment.y - branchLen * lift + cos(time * 0.45 + Double(i)) * 1.2
            )

            var branch = Path()
            branch.move(to: attachment)
            let cp1 = CGPoint(
                x: attachment.x + direction * branchLen * 0.3,
                y: attachment.y - branchLen * lift * 0.2
            )
            let cp2 = CGPoint(
                x: attachment.x + direction * branchLen * 0.7,
                y: attachment.y - branchLen * lift * 0.7
            )
            branch.addCurve(to: endPoint, control1: cp1, control2: cp2)

            let widthAtBase: CGFloat = max(2, trunkWidth * 0.45 * trunkScale)
            ctx.stroke(
                branch,
                with: .color(Color(red: 0.40, green: 0.28, blue: 0.20)),
                style: StrokeStyle(lineWidth: widthAtBase, lineCap: .round, lineJoin: .round)
            )

            // Sub-branch on more mature stages
            if stage >= .young {
                var sub = Path()
                let mid = CGPoint(
                    x: attachment.x + direction * branchLen * 0.55,
                    y: attachment.y - branchLen * lift * 0.55
                )
                sub.move(to: mid)
                let subEnd = CGPoint(
                    x: mid.x + direction * branchLen * 0.35,
                    y: mid.y - branchLen * 0.25
                )
                sub.addQuadCurve(
                    to: subEnd,
                    control: CGPoint(x: mid.x + direction * branchLen * 0.15, y: mid.y - branchLen * 0.05)
                )
                ctx.stroke(
                    sub,
                    with: .color(Color(red: 0.36, green: 0.25, blue: 0.18)),
                    style: StrokeStyle(lineWidth: max(1.5, widthAtBase * 0.55), lineCap: .round)
                )
            }

            _ = sway   // suppress unused (reserved for future canopy sway)
        }
    }

    // MARK: - Canopy (leaves)

    private func drawCanopy(
        ctx: inout GraphicsContext,
        size: CGSize,
        center: CGPoint,
        time: TimeInterval
    ) {
        let fullness = stage.canopyFullness
        guard fullness > 0 else { return }

        let canopyCenter = CGPoint(x: center.x, y: size.height * 0.45)
        let canopyRadius = size.width * 0.36 * (0.55 + fullness * 0.45)

        // Base soft canopy fill — large blurred ellipse for the silhouette.
        let baseRect = CGRect(
            x: canopyCenter.x - canopyRadius,
            y: canopyCenter.y - canopyRadius * 0.85,
            width: canopyRadius * 2,
            height: canopyRadius * 1.7
        )
        var blurred = ctx
        blurred.addFilter(.blur(radius: 18))
        blurred.fill(
            Path(ellipseIn: baseRect),
            with: .linearGradient(
                Gradient(colors: [
                    season.canopyColors.top.opacity(0.55),
                    season.canopyColors.bottom.opacity(0.45)
                ]),
                startPoint: CGPoint(x: baseRect.midX, y: baseRect.minY),
                endPoint: CGPoint(x: baseRect.midX, y: baseRect.maxY)
            )
        )

        // Crisp leaf clusters — many small ovals scattered through the
        // canopy region. Seeded from days together so a couple's tree
        // looks the same every render.
        let leafCount = Int(80 * fullness) + 6
        var rng = SeededRNG(seed: UInt64(daysTogether) &* 17 &+ 11)
        for i in 0..<leafCount {
            let angle = rng.nextDouble() * .pi * 2
            let dist  = CGFloat(rng.nextDouble()) * canopyRadius * 0.95
            let x = canopyCenter.x + cos(angle) * dist
            let y = canopyCenter.y + sin(angle) * dist * 0.85

            // Leaf flutter — small per-leaf phase
            let flutter = sin(time * (0.6 + rng.nextDouble() * 0.4) + Double(i)) * 1.4
            let leafSize: CGFloat = CGFloat(2.5 + rng.nextDouble() * 4.0)
            let leafRect = CGRect(
                x: x - leafSize / 2,
                y: y - leafSize / 2 + CGFloat(flutter),
                width: leafSize,
                height: leafSize * 1.4
            )

            // Leaf color picks between the two stops with a small jitter
            let mix = CGFloat(rng.nextDouble())
            let leafColor = blendColors(season.canopyColors.top, season.canopyColors.bottom, by: mix)

            ctx.fill(Path(ellipseIn: leafRect), with: .color(leafColor.opacity(0.85)))
        }
    }

    // MARK: - Blossoms

    private func drawBlossoms(
        ctx: inout GraphicsContext,
        size: CGSize,
        center: CGPoint,
        time: TimeInterval
    ) {
        guard stage.blossomCount > 0 else { return }

        let canopyCenter = CGPoint(x: center.x, y: size.height * 0.45)
        let canopyRadius = size.width * 0.36 * (0.55 + stage.canopyFullness * 0.45)

        var rng = SeededRNG(seed: UInt64(daysTogether) &* 31 &+ 7)

        for i in 0..<stage.blossomCount {
            let angle = rng.nextDouble() * .pi * 2
            let dist = CGFloat(0.4 + rng.nextDouble() * 0.55) * canopyRadius
            let x = canopyCenter.x + cos(angle) * dist
            let y = canopyCenter.y + sin(angle) * dist * 0.9

            let pulse = (sin(time * 0.9 + Double(i) * 1.3) + 1) / 2
            let radius: CGFloat = 4.5 + CGFloat(pulse) * 1.4

            // 5-petal blossom — soft pink for spring/summer, warmer for autumn
            let petalColor: Color = {
                switch season {
                case .spring: return Color(red: 1.0,  green: 0.78, blue: 0.86)
                case .summer: return Color(red: 1.0,  green: 0.72, blue: 0.78)
                case .autumn: return Color(red: 1.0,  green: 0.82, blue: 0.55)
                case .winter: return Color(red: 0.92, green: 0.94, blue: 1.00)
                }
            }()

            for p in 0..<5 {
                let pa = Double(p) * (.pi * 2 / 5) + time * 0.12
                let px = x + cos(pa) * radius * 0.9
                let py = y + sin(pa) * radius * 0.9
                let petal = Path(ellipseIn: CGRect(
                    x: px - radius * 0.55,
                    y: py - radius * 0.55,
                    width: radius * 1.1,
                    height: radius * 1.1
                ))
                ctx.fill(petal, with: .color(petalColor.opacity(0.85)))
            }

            // Center
            let core = Path(ellipseIn: CGRect(
                x: x - radius * 0.35,
                y: y - radius * 0.35,
                width: radius * 0.7,
                height: radius * 0.7
            ))
            ctx.fill(core, with: .color(Color(red: 1.0, green: 0.85, blue: 0.30).opacity(0.95)))
        }
    }

    // MARK: - Fruits

    private func drawFruits(
        ctx: inout GraphicsContext,
        size: CGSize,
        center: CGPoint,
        time: TimeInterval
    ) {
        guard stage.fruitCount > 0 else { return }

        let canopyCenter = CGPoint(x: center.x, y: size.height * 0.45)
        let canopyRadius = size.width * 0.36 * (0.55 + stage.canopyFullness * 0.45)

        var rng = SeededRNG(seed: UInt64(daysTogether) &* 53 &+ 41)

        for i in 0..<stage.fruitCount {
            let angle = rng.nextDouble() * .pi * 2
            let dist = CGFloat(0.5 + rng.nextDouble() * 0.4) * canopyRadius
            let baseX = canopyCenter.x + cos(angle) * dist
            let baseY = canopyCenter.y + sin(angle) * dist * 0.9

            // Gentle hang sway
            let swayY = sin(time * 0.4 + Double(i)) * 0.8
            let fruitRadius: CGFloat = 5.5 + CGFloat(rng.nextDouble() * 2.0)

            // Stem
            var stem = Path()
            stem.move(to: CGPoint(x: baseX, y: baseY - fruitRadius - 3))
            stem.addLine(to: CGPoint(x: baseX, y: baseY - fruitRadius + 1))
            ctx.stroke(stem, with: .color(Color(red: 0.35, green: 0.25, blue: 0.18)), lineWidth: 1.5)

            // Fruit body — golden
            let fruitRect = CGRect(
                x: baseX - fruitRadius,
                y: baseY - fruitRadius + CGFloat(swayY),
                width: fruitRadius * 2,
                height: fruitRadius * 2
            )
            ctx.fill(
                Path(ellipseIn: fruitRect),
                with: .radialGradient(
                    Gradient(colors: [
                        Color(red: 1.0, green: 0.92, blue: 0.55),
                        Color(red: 0.95, green: 0.65, blue: 0.20)
                    ]),
                    center: CGPoint(x: fruitRect.midX - fruitRadius * 0.2, y: fruitRect.midY - fruitRadius * 0.3),
                    startRadius: 1,
                    endRadius: fruitRadius * 1.1
                )
            )

            // Highlight
            let highlight = Path(ellipseIn: CGRect(
                x: fruitRect.midX - fruitRadius * 0.6,
                y: fruitRect.midY - fruitRadius * 0.6,
                width: fruitRadius * 0.5,
                height: fruitRadius * 0.4
            ))
            ctx.fill(highlight, with: .color(.white.opacity(0.55)))
        }
    }

    // MARK: - Memory stars

    private func drawMemoryStars(ctx: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        guard memoryCount > 0 else { return }

        let cap = min(memoryCount, 24)  // visual cap to keep canvas readable
        var rng = SeededRNG(seed: UInt64(memoryCount) &* 977 &+ 13)

        let cx = size.width / 2
        let cy = size.height * 0.42

        for i in 0..<cap {
            // Each star follows a gentle elliptical orbit with seeded
            // radius, eccentricity, phase, and speed.
            let baseAngle = rng.nextDouble() * .pi * 2
            let speed = 0.10 + rng.nextDouble() * 0.18
            let radiusX = size.width * CGFloat(0.30 + rng.nextDouble() * 0.20)
            let radiusY = size.height * CGFloat(0.18 + rng.nextDouble() * 0.14)
            let phase = baseAngle + time * speed

            let x = cx + cos(phase) * radiusX
            let y = cy + sin(phase) * radiusY * 0.9 - size.height * 0.08

            let twinkle = (sin(time * 1.3 + Double(i) * 0.9) + 1) / 2
            let starSize: CGFloat = 1.6 + CGFloat(twinkle) * 1.6

            // Glow
            let glowSize = starSize * 4
            let glow = Path(ellipseIn: CGRect(
                x: x - glowSize / 2, y: y - glowSize / 2,
                width: glowSize, height: glowSize
            ))
            ctx.fill(glow, with: .color(Color(red: 1.0, green: 0.92, blue: 0.78).opacity(0.18)))

            // Core dot
            let core = Path(ellipseIn: CGRect(
                x: x - starSize / 2, y: y - starSize / 2,
                width: starSize, height: starSize
            ))
            ctx.fill(core, with: .color(Color(red: 1.0, green: 0.97, blue: 0.85).opacity(0.95)))
        }
    }
}

// MARK: - Helpers

/// Linear blend of two SwiftUI Colors via UIColor RGBA components.
private func blendColors(_ a: Color, _ b: Color, by t: CGFloat) -> Color {
    let ua = UIColor(a)
    let ub = UIColor(b)
    var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
    var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
    ua.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
    ub.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
    let t = max(0, min(1, t))
    return Color(
        red: Double(r1 + (r2 - r1) * t),
        green: Double(g1 + (g2 - g1) * t),
        blue: Double(b1 + (b2 - b1) * t),
        opacity: Double(a1 + (a2 - a1) * t)
    )
}

/// Tiny seeded RNG so the tree topology is deterministic per couple.
/// xorshift64 — fine for visual randomness.
private struct SeededRNG {
    private var state: UInt64

    init(seed: UInt64) { self.state = seed == 0 ? 0xdead_beef_dead_beef : seed }

    mutating func nextUInt64() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    mutating func nextDouble() -> Double {
        // 53-bit fraction in [0, 1)
        Double(nextUInt64() >> 11) / Double(1 << 53)
    }
}
