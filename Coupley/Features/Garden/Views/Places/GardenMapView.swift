//
//  GardenMapView.swift
//  Coupley
//
//  The garden's places on a map (D5), pushed from the Garden sheet: exact
//  trees as annotations, area trees as circles, a List toggle for VoiceOver.
//  No user location, ever.
//

import Foundation
import SwiftUI
import MapKit
import CoreLocation

struct GardenMapView: View {

    @ObservedObject var garden: GardenViewModel
    let onOpenTree: (GardenSlot) -> Void

    @State private var showsList = false
    @State private var camera: MapCameraPosition = .automatic

    /// An area place's soft circle (D5): about its 2-decimal rounding.
    private static let areaRadius: CLLocationDistance = 600

    init(garden: GardenViewModel, onOpenTree: @escaping (GardenSlot) -> Void) {
        self.garden = garden
        self.onOpenTree = onOpenTree
    }

    /// Every planted tree that has a place, Our tree first.
    private var placedTrees: [GardenTree] {
        GardenSlot.allCases.compactMap { slot in
            guard let tree = garden.tree(slot), tree.place != nil else { return nil }
            return tree
        }
    }

    var body: some View {
        Group {
            if placedTrees.isEmpty {
                emptyState
            } else if showsList {
                placesList
            } else {
                map
            }
        }
        .background(Brand.bgGradient.ignoresSafeArea())
        .navigationTitle(Text("Your places", comment: "Garden map: navigation title of the map of the garden's places"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !placedTrees.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Picker(selection: $showsList) {
                        Label {
                            Text("Map", comment: "Garden map: show the places on a map")
                        } icon: {
                            Image(systemName: "map")
                        }
                        .tag(false)
                        Label {
                            Text("List", comment: "Garden map: show the places as a list")
                        } icon: {
                            Image(systemName: "list.bullet")
                        }
                        .tag(true)
                    } label: {
                        Text("Show as", comment: "Garden map: VoiceOver label of the map/list switch")
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            }
        }
        .onAppear { fitCamera() }
        .onChange(of: placedTrees.compactMap(\.place)) { _, _ in fitCamera() }
    }

    // MARK: - Map

    private var map: some View {
        Map(position: $camera) {
            ForEach(placedTrees) { tree in
                if let place = tree.place {
                    let coordinate = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
                    let accent = tree.look.scene.info.accent.color
                    switch place.precision {
                    case .exact:
                        Annotation(coordinate: coordinate, anchor: .center) {
                            Button {
                                onOpenTree(tree.slot)
                            } label: {
                                Image(systemName: "tree.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 34, height: 34)
                                    .background(Circle().fill(accent))
                                    .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 2))
                                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                                    // A 34 pt pin in a 44 × 44 pt target.
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(BouncyButtonStyle(scale: 0.9))
                            .accessibilityLabel(spokenLabel(tree, place))
                        } label: {
                            Text(tree.displayTitle)
                        }
                    case .area:
                        MapCircle(center: coordinate, radius: Self.areaRadius)
                            .foregroundStyle(accent.opacity(0.15))
                            .stroke(accent.opacity(0.55), lineWidth: 1.5)
                        Annotation(coordinate: coordinate, anchor: .center) {
                            Button {
                                onOpenTree(tree.slot)
                            } label: {
                                Text(tree.displayTitle)
                                    .font(JourneyFont.caption)
                                    .foregroundStyle(Brand.textPrimary)
                                    .lineLimit(1)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(Capsule().fill(.regularMaterial))
                            }
                            .buttonStyle(BouncyButtonStyle(scale: 0.95))
                            .accessibilityLabel(spokenLabel(tree, place))
                        } label: {
                            EmptyView()
                        }
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
    }

    // MARK: - List

    private var placesList: some View {
        ScrollView {
            BrandCard(tier: .card) {
                VStack(spacing: 0) {
                    ForEach(Array(placedTrees.enumerated()), id: \.element.id) { index, tree in
                        if index > 0 {
                            Rectangle().fill(Brand.divider).frame(height: 1)
                        }
                        if let place = tree.place {
                            listRow(tree, place)
                        }
                    }
                }
            }
            .padding(Brand.Space.gutter)
        }
    }

    private func listRow(_ tree: GardenTree, _ place: GardenPlace) -> some View {
        Button {
            onOpenTree(tree.slot)
        } label: {
            HStack(spacing: 12) {
                GardenSnapshotImage(place: place, scene: tree.look.scene, size: CGSize(width: 56, height: 56))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: Brand.cornerStyle))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tree.displayTitle)
                        .font(JourneyFont.label)
                        .foregroundStyle(Brand.textPrimary)
                    Text(place.name)
                        .font(JourneyFont.body)
                        .foregroundStyle(Brand.textSecondary)
                    if let locality = place.locality, locality != place.name {
                        Text(locality)
                            .font(JourneyFont.meta)
                            .foregroundStyle(Brand.textTertiary)
                    }
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(JourneyFont.meta)
                    .foregroundStyle(Brand.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel(tree, place))
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "map")
                .font(.largeTitle)
                .foregroundStyle(Brand.textTertiary)
                .accessibilityHidden(true)
            Text("None of your trees has a place yet. Add one from a tree's card.",
                 comment: "Garden: empty state of the places map and list")
                .font(JourneyFont.body)
                .foregroundStyle(Brand.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(Brand.Space.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    /// "Our first trip, Đà Lạt, the exact spot" / "…, the area".
    private func spokenLabel(_ tree: GardenTree, _ place: GardenPlace) -> String {
        switch place.precision {
        case .exact:
            return String(localized: "\(tree.displayTitle), \(place.name), the exact spot",
                          comment: "VoiceOver: a tree on the garden map. First placeholder: the tree's title; second: its place's name.")
        case .area:
            return String(localized: "\(tree.displayTitle), \(place.name), the area",
                          comment: "VoiceOver: a tree on the garden map whose place is only an area. First placeholder: the tree's title; second: its place's name.")
        }
    }

    /// All places with 20% padding; one place gets an 800 m span (D5).
    private func fitCamera() {
        guard let region = GardenPlaceSearch.region(fitting: placedTrees.compactMap(\.place)) else { return }
        camera = .region(region)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Places map") {
    NavigationStack {
        GardenMapView(garden: GardenPreviewGarden.make(),
                      onOpenTree: { _ in })
    }
}
#endif
