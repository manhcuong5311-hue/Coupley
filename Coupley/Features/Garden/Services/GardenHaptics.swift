//
//  GardenHaptics.swift
//  Coupley
//
//  P8: the garden's haptic patterns (spec C8, C9): drizzle, rain, dew
//  ticks and heartbeat on one CHHapticEngine, a UIImpactFeedbackGenerator
//  fallback, silent when system haptics are off.
//
//  Every track is a list of beats on the effect's own clock (the same
//  seconds C9 gives the drawing), so the hand feels the can tilt, the
//  drizzle, the heartbeat at the splash and the success as the eye sees
//  them. One engine, created on first use and shut down by the system when
//  idle; if it cannot start (no Taptic Engine, the engine was reset and
//  failed to restart), the same beats play through UIKit's feedback
//  generators, which are silent when the user turned System Haptics off.
//
//  Reduce Motion: the visual effect becomes a short crossfade (C10), so the
//  track becomes one success haptic too.
//  A replay of the partner's watering is felt more softly and ends on a
//  soft tap instead of "success": the success belongs to the one who
//  watered.
//

import CoreHaptics
import Foundation
import UIKit

@MainActor
final class GardenHaptics {
    static let shared = GardenHaptics()

    /// One moment of a track.
    fileprivate enum Beat {
        /// A transient tap (Core Haptics intensity and sharpness, 0…1).
        case tap(at: TimeInterval, intensity: Float, sharpness: Float)
        /// The system's success pattern.
        case success(at: TimeInterval)

        var time: TimeInterval {
            switch self {
            case .tap(let at, _, _), .success(let at): return at
            }
        }
    }

    private var engine: CHHapticEngine?
    /// False once the engine failed to start; the UIKit fallback plays.
    private var engineUsable = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private var player: CHHapticPatternPlayer?
    /// The fallback's scheduled beats (cancelled by `stop()`).
    private var fallbackTask: Task<Void, Never>?

    private init() {}

    /// Plays the haptic track of a watering effect (the waterer's or a replay).
    func play(_ effect: GardenEffect, isReplay: Bool) {
        play(effect, isReplay: isReplay, delay: 0)
    }

    /// Plays the track of `playback`: its effect, felt as a replay when it is
    /// one, and after the golden first drop (with a tap where it lands) on
    /// the garden's first watering.
    func play(_ playback: GardenEffectPlayback) {
        play(playback.effect, isReplay: playback.isReplay,
             delay: playback.isFirstEver ? WateringEffectPainter.firstDropDuration : 0)
    }

    /// Plays the planting ceremony's haptic track.
    func playPlanting() {
        if UIAccessibility.isReduceMotionEnabled {
            start([.success(at: 0)])
        } else {
            start(Self.plantingTrack)
        }
    }

    /// Stops whatever is playing (a skipped effect or ceremony).
    func stop() {
        try? player?.stop(atTime: CHHapticTimeImmediate)
        player = nil
        fallbackTask?.cancel()
        fallbackTask = nil
    }

    // MARK: - Tracks

    private func play(_ effect: GardenEffect, isReplay: Bool, delay: TimeInterval) {
        guard !UIAccessibility.isReduceMotionEnabled else {
            start([isReplay ? .tap(at: 0, intensity: 0.4, sharpness: 0.2) : .success(at: 0)])
            return
        }
        var beats = Self.track(for: effect)
        if delay > 0 {
            beats = beats.map { $0.shifted(by: delay) }
            beats.insert(.tap(at: delay - 0.02, intensity: 0.5, sharpness: 0.6), at: 0)
        }
        if isReplay { beats = beats.map { $0.softened() } }
        start(beats)
    }

    /// C9's haptics per effect, on the effect's clock.
    private static func track(for effect: GardenEffect) -> [Beat] {
        switch effect {
        case .can:
            // Medium at the tilt, a drizzle during the pour, success at 2.4 s.
            return [medium(0.38)] + drizzle(from: 0.6, to: 2.0, seed: 1) + [.success(at: 2.4)]
        case .rainCloud:
            // Rain: 16 transients over 1.6 s, success at 2.6 s.
            return rain(count: 16, from: 0.6, to: 2.2, intensity: 0.2...0.4, sharpness: 0.3, seed: 2)
                + [.success(at: 2.6)]
        case .morningDew:
            // Six light ticks with the beads, then success as they glint.
            return (0..<6).map { .tap(at: 0.45 + Double($0) * 0.15, intensity: 0.32, sharpness: 0.55) }
                + [.success(at: 1.85)]
        case .moonlitDrizzle:
            // Ten soft transients through the drizzle, then success.
            return (0..<10).map { .tap(at: 0.15 + Double($0) * 0.19, intensity: 0.18, sharpness: 0.2) }
                + [.success(at: 2.2)]
        case .together:
            // Each can tilting, a heartbeat at the splash, success at 2.4 s.
            return [medium(0.45), medium(0.57),
                    .tap(at: 1.0, intensity: 0.7, sharpness: 0.35),
                    .tap(at: 1.12, intensity: 0.5, sharpness: 0.3),
                    .success(at: 2.4)]
        case .rainReturns:
            // Four soft impacts through the rain, then success as it clears.
            return (0..<4).map { .tap(at: 0.7 + Double($0) * 0.38, intensity: 0.45, sharpness: 0.15) }
                + [.success(at: 2.3)]
        }
    }

    /// C8: two light taps as the seeds land, soft as the sprout pops, rigid
    /// 0.4 as the tree sprouts, a drizzle with the can, success with the words.
    private static let plantingTrack: [Beat] =
        [.tap(at: 0.45, intensity: 0.4, sharpness: 0.45),
         .tap(at: 0.55, intensity: 0.4, sharpness: 0.45),
         .tap(at: 0.95, intensity: 0.45, sharpness: 0.15),
         .tap(at: 1.45, intensity: 0.4, sharpness: 0.9)]
        + drizzle(from: PlantingCeremonyTimeline.pourStart, to: PlantingCeremonyTimeline.pourEnd, seed: 3)
        + [.success(at: PlantingCeremonyTimeline.wordsStart)]

    private static func medium(_ time: TimeInterval) -> Beat {
        .tap(at: time, intensity: 0.65, sharpness: 0.5)
    }

    /// Transients every 90–140 ms, intensity 0.25–0.45, sharpness 0.5.
    private static func drizzle(from start: TimeInterval, to end: TimeInterval, seed: UInt64) -> [Beat] {
        var beats: [Beat] = []
        var time = start
        var index = 0
        while time < end {
            let intensity = 0.25 + 0.2 * WateringEffectPainter.unit(seed, index, 90)
            beats.append(.tap(at: time, intensity: Float(intensity), sharpness: 0.5))
            time += 0.09 + 0.05 * WateringEffectPainter.unit(seed, index, 91)
            index += 1
        }
        return beats
    }

    /// `count` transients spread over start...end with seeded intensities.
    private static func rain(count: Int, from start: TimeInterval, to end: TimeInterval,
                             intensity: ClosedRange<Double>, sharpness: Float, seed: UInt64) -> [Beat] {
        (0..<count).map { i in
            let jitter = (WateringEffectPainter.unit(seed, i, 92) - 0.5) * 0.04
            let time = start + (end - start) * Double(i) / Double(count) + jitter
            let level = intensity.lowerBound + (intensity.upperBound - intensity.lowerBound)
                * WateringEffectPainter.unit(seed, i, 93)
            return .tap(at: max(start, time), intensity: Float(level), sharpness: sharpness)
        }
    }

    // MARK: - Playing

    private func start(_ beats: [Beat]) {
        stop()
        guard !beats.isEmpty else { return }
        if engineUsable, let engine = readyEngine() {
            do {
                let pattern = try CHHapticPattern(events: beats.flatMap { $0.events }, parameters: [])
                let player = try engine.makePlayer(with: pattern)
                try player.start(atTime: CHHapticTimeImmediate)
                self.player = player
                return
            } catch {
                engineUsable = false
            }
        }
        playWithUIKit(beats)
    }

    /// The shared engine, started (it restarts itself after a reset and is
    /// stopped by the system when idle).
    private func readyEngine() -> CHHapticEngine? {
        if engine == nil {
            guard let created = try? CHHapticEngine() else {
                engineUsable = false
                return nil
            }
            created.playsHapticsOnly = true
            created.isAutoShutdownEnabled = true
            created.resetHandler = { @Sendable in
                Task { @MainActor in GardenHaptics.shared.engineDidReset() }
            }
            created.stoppedHandler = { @Sendable _ in
                Task { @MainActor in GardenHaptics.shared.player = nil }
            }
            engine = created
        }
        do {
            try engine?.start()
        } catch {
            engineUsable = false
            return nil
        }
        return engine
    }

    private func engineDidReset() {
        player = nil
        do {
            try engine?.start()
        } catch {
            engineUsable = false
        }
    }

    /// The fallback: each beat on UIKit's generators at its time.
    private func playWithUIKit(_ beats: [Beat]) {
        let impact = UIImpactFeedbackGenerator(style: .medium)
        let notification = UINotificationFeedbackGenerator()
        impact.prepare()
        fallbackTask = Task { @MainActor in
            var clock: TimeInterval = 0
            for beat in beats.sorted(by: { $0.time < $1.time }) {
                let wait = beat.time - clock
                if wait > 0 {
                    try? await Task.sleep(for: .seconds(wait))
                }
                guard !Task.isCancelled else { return }
                clock = beat.time
                switch beat {
                case .tap(_, let intensity, _):
                    impact.impactOccurred(intensity: CGFloat(intensity))
                case .success:
                    notification.notificationOccurred(.success)
                }
            }
        }
    }
}

private extension GardenHaptics.Beat {
    /// Core Haptics events. "Success" is two taps, the second stronger, as
    /// the system's notification feedback feels.
    var events: [CHHapticEvent] {
        switch self {
        case .tap(let at, let intensity, let sharpness):
            return [Self.transient(at, intensity, sharpness)]
        case .success(let at):
            return [Self.transient(at, 0.55, 0.45), Self.transient(at + 0.11, 0.9, 0.6)]
        }
    }

    func shifted(by delay: TimeInterval) -> Self {
        switch self {
        case .tap(let at, let intensity, let sharpness): return .tap(at: at + delay, intensity: intensity, sharpness: sharpness)
        case .success(let at):                           return .success(at: at + delay)
        }
    }

    /// A replay: 70% as strong, ending on a soft tap rather than success.
    func softened() -> Self {
        switch self {
        case .tap(let at, let intensity, let sharpness): return .tap(at: at, intensity: intensity * 0.7, sharpness: sharpness)
        case .success(let at):                           return .tap(at: at, intensity: 0.45, sharpness: 0.25)
        }
    }

    static func transient(_ time: TimeInterval, _ intensity: Float, _ sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticTransient,
                      parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                                   CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)],
                      relativeTime: time)
    }
}
