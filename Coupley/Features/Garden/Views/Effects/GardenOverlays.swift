//
//  GardenOverlays.swift
//  Coupley
//
//  P8: what stays after a watering and the small overlays around it
//  (spec C9): the resting cans, the 24 h rainbow, the after-glow, the
//  page-dot ripple and the Reduce Motion drop.
//
//  Anchors are in the scene page's coordinates (`TreeCanvasAnchors.offset`),
//  so every overlay here fills the page and draws at those points. The
//  cans and the rainbow are static shapes (layer 6 of C2, redrawn only when
//  their inputs change); the after-glow and the ripple animate for about a
//  second on their own short clock and then stop. All of them are
//  decoration: hidden from VoiceOver and never hit-tested (the status line
//  says in words what they show).
//

import SwiftUI

/// The waterer's can resting by the trunk for 24 h (partner's left, yours right).
struct GardenRestingCansView: View {
    let cans: GardenRestingCans
    let anchors: TreeCanvasAnchors

    init(cans: GardenRestingCans, anchors: TreeCanvasAnchors) {
        self.cans = cans
        self.anchors = anchors
    }

    var body: some View {
        Canvas { context, _ in
            let size = max(14, anchors.unit * 0.11)
            if cans == .partners || cans == .both {
                // The partner's can, spout pointing away from the trunk.
                drawResting(in: context, at: anchors.leftCanPoint, size: size, mirrored: false)
            }
            if cans == .mine || cans == .both {
                drawResting(in: context, at: anchors.rightCanPoint, size: size, mirrored: true)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// An upright can standing on `point` with a soft contact shadow. Its
    /// body sits a little outward of the point, so the handle (on the trunk's
    /// side) clears the bark.
    private func drawResting(in context: GraphicsContext, at point: CGPoint, size: CGFloat, mirrored: Bool) {
        let x = point.x + (mirrored ? 1 : -1) * size * 0.25
        let shadow = CGRect(x: x - size * 0.6, y: point.y - 1.5, width: size * 1.2, height: 3)
        context.fill(Path(ellipseIn: shadow), with: .color(.black.opacity(0.18)))
        WateringEffectPainter.drawCanSprite(in: context, position: CGPoint(x: x, y: point.y - size * 0.39),
                                            size: size, angle: 0, mirrored: mirrored, opacity: 1)
    }
}

/// The faint rainbow that stays for 24 h after "watered together". Place it
/// behind the tree canvas: it arcs around the canopy from the trunk base.
struct GardenRainbowView: View {
    let anchors: TreeCanvasAnchors
    let size: CGSize
    let opacity: Double
    /// The page sky's darkness: above 0.5 the rainbow is a silver moonbow,
    /// as the watering effect draws it at night.
    let darkness: Double

    init(anchors: TreeCanvasAnchors, size: CGSize, opacity: Double, darkness: Double = 0) {
        self.anchors = anchors
        self.size = size
        self.opacity = opacity
        self.darkness = darkness
    }

    var body: some View {
        Canvas { context, _ in
            WateringEffectPainter.drawRainbow(in: context, anchors: anchors, alpha: opacity, darkness: darkness)
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Eight glints and wet soil fading in on a page swiped to after a watering.
struct GardenAfterGlowView: View {
    let anchors: TreeCanvasAnchors
    let startTime: TimeInterval

    /// The soil sheen rises over 0.6 s and fades by 1.4 s, when the page's
    /// own watered look carries on alone.
    static let duration: TimeInterval = 1.4

    @State private var finished = false

    init(anchors: TreeCanvasAnchors, startTime: TimeInterval) {
        self.anchors = anchors
        self.startTime = startTime
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: finished)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate - startTime
            Canvas { context, _ in
                guard t >= 0, t < Self.duration else { return }
                let moisture = WateringEffectPainter.envelope(t, start: 0, end: Self.duration, fadeIn: 0.6, fadeOut: 0.4)
                WateringEffectPainter.drawSoakingSoil(in: context, anchors: anchors, moisture: moisture)
                WateringEffectPainter.drawCanopyGlints(in: context, anchors: anchors,
                                                       seed: UInt64(bitPattern: Int64(startTime * 1000)),
                                                       count: 8, time: t, start: 0.1, stagger: 0.05, life: 0.45,
                                                       salt: 100)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: startTime) {
            finished = false
            let remaining = startTime + Self.duration - Date().timeIntervalSinceReferenceDate
            if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
            guard !Task.isCancelled else { return }
            finished = true
        }
    }
}

/// Rings rippling left to right across the pager's dots on a one-tap watering.
///
/// Overlay it centred on the dot row: it is `Metrics.padding` wider than the
/// row on each side (the rings grow past the dots) and finds each dot's
/// centre from `Metrics`, the page dots' geometry (B3: 6 pt dots, the
/// selected one a 16 × 6 capsule).
struct GardenDotRipple: View {
    let dotCount: Int
    let startTime: TimeInterval
    /// The capsule dot, which is wider than the others; nil = all alike.
    let selectedIndex: Int?

    /// The page dots' geometry, shared with the pager's dot row.
    enum Metrics {
        static let dotSize: CGFloat = 6
        static let selectedWidth: CGFloat = 16
        static let spacing: CGFloat = 6
        /// The largest ring's radius: the ripple's margin around the row.
        static let padding: CGFloat = 11
    }

    @State private var finished = false

    init(dotCount: Int, startTime: TimeInterval, selectedIndex: Int? = nil) {
        self.dotCount = dotCount
        self.startTime = startTime
        self.selectedIndex = selectedIndex
    }

    /// Dot i starts at 0.25 + 0.12·i s; each ring lasts 0.45 s.
    private var duration: TimeInterval { 0.25 + 0.12 * Double(max(0, dotCount - 1)) + 0.45 }

    private func width(of index: Int) -> CGFloat {
        index == selectedIndex ? Metrics.selectedWidth : Metrics.dotSize
    }

    private var rowWidth: CGFloat {
        guard dotCount > 0 else { return 0 }
        return (0..<dotCount).reduce(0) { $0 + width(of: $1) } + Metrics.spacing * CGFloat(dotCount - 1)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: finished)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate - startTime
            Canvas { context, size in
                var x = Metrics.padding
                for i in 0..<dotCount {
                    let w = width(of: i)
                    defer { x += w + Metrics.spacing }
                    let age = t - (0.25 + 0.12 * Double(i))
                    guard age >= 0, age < 0.45 else { continue }
                    let grow = CGFloat(WateringEffectPainter.easeOutCubic(age / 0.45))
                    let r = 4 + 7 * grow
                    let center = CGPoint(x: x + w / 2, y: size.height / 2)
                    var ring = Path()
                    ring.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
                    context.stroke(ring, with: .color(GardenRGB(0x8FD3FF).color.opacity(0.8 * (1 - age / 0.45))),
                                   lineWidth: 1.5)
                }
            }
        }
        .frame(width: rowWidth + Metrics.padding * 2, height: Metrics.padding * 2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: startTime) {
            finished = false
            let remaining = startTime + duration - Date().timeIntervalSinceReferenceDate
            if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
            guard !Task.isCancelled else { return }
            finished = true
        }
    }
}

/// The Reduce Motion stand-in for every watering effect: a still water drop
/// above the soil for 1.2 s, then a short fade (C10).
struct GardenReducedMotionDrop: View {
    let anchors: TreeCanvasAnchors

    @State private var isShown = true

    init(anchors: TreeCanvasAnchors) {
        self.anchors = anchors
    }

    var body: some View {
        Image(systemName: "drop.fill")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(GardenRGB(0x8FD3FF).color)
            .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
            .position(x: anchors.trunkBase.x, y: anchors.soilRect.minY - 14)
            .opacity(isShown ? 1 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task {
                try? await Task.sleep(for: .seconds(1.2))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.3)) { isShown = false }
            }
    }
}

#Preview("Resting cans, rainbow, drop") {
    let anchors = RelationshipTreeCanvas.anchors(in: CGSize(width: 180, height: 180), stage: .blooming)
        .offset(by: CGPoint(x: 120, y: 14))
    ZStack(alignment: .topLeading) {
        LinearGradient(colors: [GardenRGB(0x6FB7EA).color, GardenRGB(0xD8EEF8).color],
                       startPoint: .top, endPoint: .bottom)
        GardenRainbowView(anchors: anchors, size: CGSize(width: 351, height: 208), opacity: 0.25)
        RelationshipTreeCanvas(stage: .blooming, season: .summer, daysTogether: 200, memoryCount: 0,
                               crownActive: false)
            .frame(width: 180, height: 180)
            .offset(x: 120, y: 14)
        GardenRestingCansView(cans: .both, anchors: anchors)
        GardenReducedMotionDrop(anchors: anchors)
    }
    .frame(width: 351, height: 208)
    .border(.red.opacity(0.3))
}
