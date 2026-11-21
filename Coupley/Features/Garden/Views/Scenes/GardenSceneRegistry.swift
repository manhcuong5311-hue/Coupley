//
//  GardenSceneRegistry.swift
//  Coupley
//
//  Our Garden, P5 (Scenes I): maps each scene id to its painter, and a
//  cache-free sketch of a whole scene for previews and the lab's gallery.
//  Scenes 1–4 are P5's; scenes 5–8 are P6's.
//

import Foundation
import SwiftUI

extension GardenSceneID {
    nonisolated var painter: any GardenScenePainting {
        switch self {
        case .meadow:       return MeadowScene()
        case .seaside:      return SeasideScene()
        case .cityLights:   return CityLightsScene()
        case .mountainLake: return MountainLakeScene()
        case .lanternTown:  return LanternTownScene()
        case .riceTerraces: return RiceTerracesScene()
        case .campus:       return CampusScene()
        case .homePorch:    return HomePorchScene()
        }
    }
}

/// One scene drawn straight from its painter, without the cache or a tree:
/// the sky gradient, sky life, far (day and night blended by the sky's
/// darkness, as the page blends its images), scene life, near, front and
/// front life, in C2's order. Still pose, so it is the same every time.
/// For previews and art review only; the hero composes `GardenScenePage`.
struct GardenSceneSketch: View {
    let scene: GardenSceneID
    let sky: GardenSkyState
    let season: GardenSceneSeason
    let seed: UInt64

    init(scene: GardenSceneID, sky: GardenSkyState, season: GardenSceneSeason, seed: UInt64 = 1) {
        self.scene = scene
        self.sky = sky
        self.season = season
        self.seed = seed
    }

    /// The sky at `localHour` (0–24, fractions are minutes) on any day.
    init(scene: GardenSceneID, localHour: Double, season: GardenSceneSeason, seed: UInt64 = 1) {
        let utc = TimeZone(identifier: "UTC") ?? .current
        let date = Date(timeIntervalSinceReferenceDate: 86_400 * 1_000 + localHour * 3_600)
        self.init(scene: scene, sky: GardenSky.state(at: date, in: utc), season: season, seed: seed)
    }

    var body: some View {
        let painter = scene.painter, horizon = scene.info.layout.horizon
        let sky = sky, season = season
        let ambient = GardenAmbientState(time: 0, pose: .still, sky: sky, season: season, seed: seed)
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .linearGradient(Gradient(colors: [sky.top.color, sky.horizon.color]),
                                               startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height * horizon)))
            func staticLayer(_ layer: GardenBackdropLayer) {
                for variant in GardenBackdropCache.variants(forDarkness: sky.darkness) {
                    var layerContext = context
                    layerContext.opacity = variant == .night ? sky.darkness : 1
                    layerContext.drawLayer { painter.drawLayer(layer, in: $0, size: size,
                                                               style: GardenSceneStyle(variant: variant, season: season)) }
                }
            }
            painter.drawAmbient(.sky, in: context, size: size, state: ambient)
            staticLayer(.far)
            painter.drawAmbient(.behind, in: context, size: size, state: ambient)
            staticLayer(.near)
            staticLayer(.front)
            painter.drawAmbient(.front, in: context, size: size, state: ambient)
        }
        .clipped()
    }
}
