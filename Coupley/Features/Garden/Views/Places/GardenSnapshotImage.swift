//
//  GardenSnapshotImage.swift
//  Coupley
//
//  A map snapshot of a tree's place with Apple Maps attribution (D5); the
//  scene swatch stands in while it loads, offline or on failure. Also the
//  scene swatch itself (look chips, stamps, places without a map), shared by
//  the garden's sheets.
//

import Foundation
import SwiftUI

struct GardenSnapshotImage: View {

    let place: GardenPlace
    let scene: GardenSceneID
    let size: CGSize

    @Environment(\.colorScheme) private var colorScheme
    /// The last snapshot that arrived, with the request it answers.
    @State private var loaded: Loaded?

    private struct Loaded {
        let request: GardenSnapshotRequest
        let image: CGImage
    }

    init(place: GardenPlace, scene: GardenSceneID, size: CGSize) {
        self.place = place
        self.scene = scene
        self.size = size
    }

    private var request: GardenSnapshotRequest {
        GardenSnapshotRequest(place: place, size: size, isDark: colorScheme == .dark)
    }

    /// The loaded map, only while it shows this place: a new size or
    /// appearance keeps it until its own snapshot lands, another place
    /// never shows it.
    private var image: CGImage? {
        let request = self.request
        guard let loaded, loaded.request.latitude == request.latitude,
              loaded.request.longitude == request.longitude,
              loaded.request.precision == request.precision else { return nil }
        return loaded.image
    }

    var body: some View {
        let image = self.image
        ZStack(alignment: .bottomLeading) {
            if let image {
                Image(decorative: image, scale: CGFloat(image.width) / max(1, size.width))
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
                GardenMapAttribution(isCompact: size.width < 160)
                    .padding(size.width < 160 ? 3 : 6)
            } else {
                GardenSceneSwatch(scene: scene, size: size)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .animation(.easeOut(duration: 0.2), value: image != nil)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Map of \(place.name)",
                                 comment: "VoiceOver: a small map of a garden tree's place. The placeholder is the place's name."))
        // A row that scrolls away cancels its job (D5); a cancelled job (the
        // place, size or appearance changed) never writes over a newer one.
        .task(id: request) {
            let request = self.request
            let image = await GardenMapSnapshotter.shared.snapshot(request)
            guard !Task.isCancelled else { return }
            loaded = image.map { Loaded(request: request, image: $0) }
        }
    }
}

// MARK: - Attribution

/// "Apple Maps · Legal" over every snapshot (D5): snapshot images carry no
/// legal label of their own. Thumbnails too small for the link show the
/// name alone.
struct GardenMapAttribution: View {

    var isCompact = false

    static let legalURL = URL(string: "https://www.apple.com/legal/internet-services/maps/")!

    var body: some View {
        HStack(spacing: 4) {
            Text("Apple Maps", comment: "Attribution on map images: Apple's map service. Use Apple's own name for Apple Maps in your language.")
            if !isCompact {
                Text(verbatim: ScriptSpacing.factMark)
                    .accessibilityHidden(true)
                Link(destination: Self.legalURL) {
                    Text("Legal", comment: "Link on map images to Apple Maps' legal notices")
                        .underline()
                }
            }
        }
        .font(isCompact ? .system(size: 8, weight: .medium, design: .rounded) : JourneyFont.meta)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .foregroundStyle(.white)
        .padding(.horizontal, isCompact ? 4 : 7)
        .padding(.vertical, isCompact ? 1.5 : 3)
        .background(Capsule().fill(Color.black.opacity(0.55)))
    }
}

// MARK: - Scene swatch

/// A small picture of a scene: the backdrop cache's swatch, or a flat sky
/// and ground in the scene's colours while it has none.
///
/// The cache is asked in the body, never from a task: on a miss it renders
/// the swatch a frame later and bumps its observed revision, which redraws
/// exactly the views whose body asked (at whatever size they ask now).
struct GardenSceneSwatch: View {

    let scene: GardenSceneID
    let size: CGSize

    var body: some View {
        let season = GardenSeasons.season(at: Date(), latitude: nil, timeZone: .current)
        let image = GardenBackdropCache.shared.swatch(scene: scene, season: season, size: size)
        ZStack {
            if let image {
                Image(decorative: image, scale: CGFloat(image.width) / max(1, size.width))
                    .resizable()
                    .scaledToFill()
            } else {
                fallback
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .accessibilityHidden(true)
    }

    /// Noon sky over the scene's ground, the horizon where the scene puts it.
    private var fallback: some View {
        let info = scene.info
        let sky = GardenSky.state(at: Self.noon, in: .gmt)
        return VStack(spacing: 0) {
            LinearGradient(colors: [sky.top.color, sky.horizon.color], startPoint: .top, endPoint: .bottom)
                .frame(height: size.height * info.layout.horizon)
            info.groundDay.color
        }
    }

    /// 12:00 GMT on any day: the sky's daylight keyframe.
    private static let noon = Date(timeIntervalSince1970: 12 * 3600)
}

// MARK: - Previews

#Preview("Swatches") {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96))], spacing: 12) {
        ForEach(GardenSceneID.allCases) { scene in
            VStack(spacing: 4) {
                GardenSceneSwatch(scene: scene, size: CGSize(width: 96, height: 64))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Text(scene.displayName).font(JourneyFont.meta)
            }
        }
    }
    .padding()
}

#Preview("Snapshot") {
    VStack(spacing: 16) {
        GardenSnapshotImage(place: GardenPlace(name: "Café Giảng", locality: "Hoàn Kiếm, Hà Nội",
                                               latitude: 21.03452, longitude: 105.85431, precision: .exact,
                                               poiCategory: "MKPOICategoryCafe", timeZoneId: "Asia/Ho_Chi_Minh"),
                            scene: .cityLights, size: CGSize(width: 343, height: 229))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        GardenSnapshotImage(place: GardenPlace(name: "Đà Nẵng", locality: "Đà Nẵng",
                                               latitude: 16.0544, longitude: 108.2022, precision: .area),
                            scene: .seaside, size: CGSize(width: 56, height: 56))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    .padding()
}
