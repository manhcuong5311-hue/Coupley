//
//  GardenSheet.swift
//  Coupley
//
//  The Garden sheet (spec B5.5): the trees shelf, what is waiting, the
//  places, the latest waterings and the one filled "Plant a tree". The
//  postcard, the places map and the journal are pushed on its own
//  NavigationStack; a request opens the seed sheet once this one is gone.
//
//  Also the single route of every Journey garden sheet (spec B5, I5):
//  TimeTreeView presents them one at a time with `.sheet(item:)`, through
//  GardenRouteSheet, and hands one sheet over to the next only from the
//  closing sheet's onDismiss.
//

import Foundation
import SwiftUI
import UIKit

// MARK: - Route

/// Which garden sheet Journey shows. One at a time; hand-overs happen in
/// the sheet's onDismiss.
enum GardenSheetRoute: Identifiable, Equatable {
    case plant(GardenDraft.Mode)
    case seed(id: String)
    case postcard(GardenSlot)
    case garden
    /// The Garden sheet with its journal already pushed (the status well).
    case journal
    case waterNote

    var id: String {
        switch self {
        case .plant(let mode): return "plant.\(mode)"
        case .seed(let id): return "seed.\(id)"
        case .postcard(let slot): return "postcard.\(slot.rawValue)"
        case .garden: return "garden"
        case .journal: return "journal"
        case .waterNote: return "waterNote"
        }
    }

    /// The plant form and the water note hold the user's typing
    /// (TimeTreeView.isEditingSomething).
    var isEditing: Bool {
        switch self {
        case .plant, .waterNote: return true
        case .seed, .postcard, .garden, .journal: return false
        }
    }
}

/// The content of one Journey garden sheet, with its detents.
struct GardenRouteSheet: View {

    let route: GardenSheetRoute
    @ObservedObject var garden: GardenViewModel
    /// The water note being written (kept when the sheet is swiped away).
    /// Only the water-note sheet reads its text, so typing re-renders
    /// nothing else.
    let noteDraft: GardenNoteDraft
    /// The Timeline's first day per memory kind, for the plant form's "From
    /// your Timeline" hint (TimeTreeViewModel.firstDateByKind).
    var timelineDays: [MemoryKind: Date] = [:]
    /// Asks Journey to show another garden sheet once this one is gone.
    let handOver: (GardenSheetRoute) -> Void
    /// The note to water with; Journey waters once the sheet is gone.
    let onWater: (String) -> Void
    /// Closes this sheet.
    let onClose: () -> Void

    var body: some View {
        content
            .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var content: some View {
        switch route {
        case .plant(let mode):
            GardenPlantSheet(garden: garden, mode: mode, timelineDays: timelineDays)
                .presentationDetents([.large])
        case .seed(let id):
            GardenSeedSheet(garden: garden, proposalId: id,
                            onPlanted: onClose,
                            onOpenTree: { slot in
                                garden.select(slot)
                                onClose()
                            })
                .presentationDetents([.large])
        case .postcard(let slot):
            TreePostcardView(garden: garden, slot: slot, isPushed: false)
                .presentationDetents([.large])
        case .garden, .journal:
            GardenSheet(garden: garden,
                        onPlantTree: { handOver(.plant(.newPlaceTree)) },
                        onOpenRequest: { handOver(.seed(id: $0)) },
                        startsAtJournal: route == .journal)
                .presentationDetents([.large])
        case .waterNote:
            WaterNoteSheet(garden: garden, draft: noteDraft, onWater: onWater)
                .presentationDetents([.height(320), .large])
        }
    }
}

// MARK: - Garden sheet

struct GardenSheet: View {

    @ObservedObject var garden: GardenViewModel
    /// The filled "Plant a tree" (and the shelf's dashed cell): handed to
    /// Journey, which opens the plant sheet once this one is gone.
    let onPlantTree: () -> Void
    /// A waiting request: Journey opens its seed sheet once this one is gone.
    let onOpenRequest: (String) -> Void
    /// Opens with the journal pushed (from the hero's status line).
    let startsAtJournal: Bool

    init(garden: GardenViewModel,
         onPlantTree: @escaping () -> Void = {},
         onOpenRequest: @escaping (String) -> Void = { _ in },
         startsAtJournal: Bool = false) {
        self.garden = garden
        self.onPlantTree = onPlantTree
        self.onOpenRequest = onOpenRequest
        self.startsAtJournal = startsAtJournal
    }

    /// What this sheet pushes.
    enum Destination: Hashable {
        case postcard(GardenSlot)
        case map
        case journal
    }

    @Environment(\.dismiss) private var dismiss
    @State private var path: [Destination] = []
    @State private var openedJournal = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    treesSection
                    if !garden.requests.isEmpty {
                        waitingSection
                    }
                    placesSection
                    wateringSection
                }
                .padding(.horizontal, Brand.Space.gutter)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Brand.bgGradient.ignoresSafeArea())
            .navigationTitle(Text("Your garden", comment: "Garden sheet: navigation title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done", comment: "Button: close the garden sheet")
                    }
                    .foregroundStyle(Brand.accentStart)
                }
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .postcard(let slot):
                    TreePostcardView(garden: garden, slot: slot, isPushed: true)
                case .map:
                    GardenMapView(garden: garden, onOpenTree: { path.append(.postcard($0)) })
                case .journal:
                    GardenJournalView(garden: garden)
                }
            }
        }
        .onAppear {
            guard startsAtJournal, !openedJournal else { return }
            openedJournal = true
            path = [.journal]
        }
    }

    private var pages: [GardenPageModel] { garden.hero.pages }

    // MARK: Trees

    private var treesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(Text("Trees", comment: "Garden sheet: section with every tree"))
            switch garden.availability {
            case .unavailable(.listenerFailed):
                Text("Couldn't load your garden. Check your connection and try again.",
                     comment: "Garden sheet: the garden could not be loaded")
                    .font(JourneyFont.body)
                    .foregroundStyle(Brand.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            default:
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        if garden.availability == .loading && pages.isEmpty {
                            ForEach(0..<3, id: \.self) { _ in skeletonTerrarium }
                        } else {
                            ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                                Button {
                                    path.append(.postcard(page.slot))
                                } label: {
                                    GardenTerrarium(page: page, stage: stage(of: page), days: days(of: page),
                                                    isFresh: isFresh(page))
                                        // One tap waters every tree: they revive one
                                        // after another (C9).
                                        .animation(.easeOut(duration: 0.45).delay(0.25 + 0.12 * Double(index)),
                                                   value: page.visual)
                                }
                                .buttonStyle(BouncyButtonStyle(scale: 0.96))
                            }
                            if garden.canPlantMore {
                                plantCell
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollClipDisabled()
            }
        }
    }

    private func days(of page: GardenPageModel) -> Int {
        let start = page.slot.isOurTree ? garden.anchor.startDate : (page.growthStart ?? garden.tree(page.slot)?.plantedAt)
        return start.map { GardenGrowth.days(since: $0, now: garden.now) } ?? 0
    }

    private func stage(of page: GardenPageModel) -> TreeGrowthStage {
        .from(daysTogether: days(of: page))
    }

    /// Watered less than 48 hours ago, by this tree's own clock.
    private func isFresh(_ page: GardenPageModel) -> Bool {
        let last = garden.waterings.waterings.compactMap(\.wateredAt).max()
        let planted = page.slot.isOurTree ? nil : garden.tree(page.slot)?.plantedAt
        return GardenWaterState.state(lastWateredAt: last, plantedAt: planted, now: garden.now) == .fresh
    }

    private var plantCell: some View {
        Button(action: onPlantTree) {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 14, style: Brand.cornerStyle)
                    .strokeBorder(Brand.accentStart.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .frame(width: 96, height: 96)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Brand.accentStart)
                    }
                Text("Plant a tree", comment: "Garden: opens the plant sheet for a new tree")
                    .font(JourneyFont.caption)
                    .foregroundStyle(Brand.accentStart)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 96)
            }
        }
        .buttonStyle(BouncyButtonStyle(scale: 0.96))
    }

    private var skeletonTerrarium: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 14, style: Brand.cornerStyle)
                .fill(Brand.surfaceLight)
                .frame(width: 96, height: 96)
            Capsule()
                .fill(Brand.surfaceLight)
                .frame(width: 64, height: 10)
                .padding(.top, 4)
        }
        .shimmer()
        .accessibilityHidden(true)
    }

    // MARK: Waiting

    private var waitingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(Text("Waiting", comment: "Garden sheet: section with the seeds and requests that wait for an answer"))
            VStack(spacing: 0) {
                ForEach(garden.requests) { request in
                    Button {
                        onOpenRequest(request.id)
                    } label: {
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(request.title)
                                    .font(JourneyFont.label)
                                    .foregroundStyle(Brand.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let line = request.lines.first {
                                    Text(line)
                                        .font(JourneyFont.meta)
                                        .foregroundStyle(Brand.textSecondary)
                                        .lineLimit(2)
                                }
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.forward")
                                .font(JourneyFont.meta)
                                .foregroundStyle(Brand.textTertiary)
                                .accessibilityHidden(true)
                        }
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if request.id != garden.requests.last?.id {
                        Divider().overlay(Brand.divider)
                    }
                }
            }
            .padding(.horizontal, 14)
            .wellBackground(in: .card)
        }
    }

    // MARK: Places

    private var placesSection: some View {
        let placed = pages.filter { $0.place != nil }
        return VStack(alignment: .leading, spacing: 12) {
            sectionTitle(Text("Places", comment: "Garden sheet: section with the places the trees stand for"))
            if placed.isEmpty {
                Text("None of your trees has a place yet. Add one from a tree's card.",
                     comment: "Garden sheet: no tree has a place")
                    .font(JourneyFont.body)
                    .foregroundStyle(Brand.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(placed) { page in
                            if let place = page.place {
                                Button {
                                    path.append(.postcard(page.slot))
                                } label: {
                                    GardenSnapshotImage(place: place, scene: page.look.scene,
                                                        size: CGSize(width: 56, height: 56))
                                        .frame(width: 56, height: 56)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: Brand.cornerStyle))
                                }
                                .buttonStyle(BouncyButtonStyle(scale: 0.94))
                                .accessibilityLabel(Text(place.name))
                                .accessibilityHint(Text("Opens the tree's postcard.",
                                                        comment: "VoiceOver hint on a place in the garden sheet"))
                            }
                        }
                    }
                }
                BrandCTA(title: String(localized: "Open the map", comment: "Garden sheet: opens the map of every placed tree"),
                         icon: "map", tier: .card) {
                    path.append(.map)
                }
            }
        }
    }

    // MARK: Watering

    private var wateringSection: some View {
        let entries = Array(garden.journalEntries().prefix(5))
        return VStack(alignment: .leading, spacing: 12) {
            sectionTitle(Text("Watering", comment: "Garden sheet: section with the latest waterings"))
            if entries.isEmpty {
                Text("No waterings yet. The first drop starts the journal.",
                     comment: "Garden journal: no watering yet")
                    .font(JourneyFont.body)
                    .foregroundStyle(Brand.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(entries) { entry in
                        GardenJournalRow(entry: entry)
                    }
                }
                Button {
                    path.append(.journal)
                } label: {
                    Text("See every watering", comment: "Garden sheet: opens the garden journal")
                        .font(JourneyFont.label)
                        .foregroundStyle(Brand.accentStart)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Bottom

    @ViewBuilder
    private var bottomBar: some View {
        if garden.canPlantMore {
            BrandCTA(title: String(localized: "Plant a tree", comment: "Garden: opens the plant sheet for a new tree"),
                     icon: "leaf.fill", tier: .hero, action: onPlantTree)
                .padding(.horizontal, Brand.Space.gutter)
                .padding(.vertical, 12)
                .background(Brand.backgroundTop.opacity(0.96))
        } else if garden.treeCount >= GardenLimits.maxTrees {
            Text("Your garden has 8 trees. Let one rest to plant another.",
                 comment: "Garden error: the garden is full")
                .font(JourneyFont.meta)
                .foregroundStyle(Brand.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Brand.Space.gutter)
                .padding(.vertical, 12)
                .background(Brand.backgroundTop.opacity(0.96))
        }
    }

    private func sectionTitle(_ text: Text) -> some View {
        text
            .font(JourneyFont.title)
            .foregroundStyle(Brand.textPrimary)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Terrarium

/// One tree on the shelf (96×120): its scene swatch, a still tree at its
/// stage and thirst, its name, and a drop while it is fresh.
struct GardenTerrarium: View {
    let page: GardenPageModel
    let stage: TreeGrowthStage
    let days: Int
    let isFresh: Bool

    var body: some View {
        let title = page.preset.displayTitle(stored: page.title)
        VStack(spacing: 6) {
            ZStack {
                swatch
                RelationshipTreeCanvas(
                    stage: stage,
                    season: page.environment.season.treeSeason,
                    daysTogether: days,
                    memoryCount: 0,
                    crownActive: false,
                    style: .scene(species: page.look.species, sky: page.environment.sky,
                                  season: page.environment.season,
                                  topologySeed: page.slot.isOurTree ? nil : page.environment.seed),
                    vitality: TreeVitality(page.visual),
                    clock: .external(time: 0, pose: .still)
                )
                .padding(6)
            }
            .frame(width: 96, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: Brand.cornerStyle))
            .overlay(RoundedRectangle(cornerRadius: 14, style: Brand.cornerStyle)
                .strokeBorder(Brand.divider, lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                if isFresh {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(Circle().fill(GardenHero.water))
                        .padding(5)
                }
            }

            // Two lines: titles run longer in many languages ("Cây của
            // chúng mình", "Notre premier rendez-vous"); the row is top-aligned.
            Text(title)
                .font(JourneyFont.caption)
                .foregroundStyle(Brand.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 96)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isFresh
                            ? String(localized: "\(title), \(stage.displayName), freshly watered",
                                     comment: "VoiceOver: a tree on the garden shelf. First %@ is its title, second its growth stage.")
                            : String(localized: "\(title), \(stage.displayName)",
                                     comment: "VoiceOver: a tree on the garden shelf. First %@ is its title, second its growth stage."))
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var swatch: some View {
        if let image = GardenBackdropCache.shared.swatch(scene: page.look.scene, season: page.environment.season,
                                                         size: CGSize(width: 96, height: 96)) {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFill()
        } else {
            let info = page.look.scene.info
            VStack(spacing: 0) {
                LinearGradient(colors: [GardenRGB(0x6FB7EA).color, GardenRGB(0xD8EEF8).color],
                               startPoint: .top, endPoint: .bottom)
                info.groundDay.color
                    .frame(height: 96 * (1 - info.layout.horizon))
            }
        }
    }
}

// MARK: - Preview

// Builds a GardenViewModel on the in-memory service, so DEBUG only (K7).
#if DEBUG
#Preview("Garden sheet") {
    let service = InMemoryGardenService()
    let garden = GardenViewModel(session: GardenLab.session, service: service)
    GardenSheet(garden: garden)
        .onAppear {
            garden.start()
            service.simulatePartner(.water(note: "Thinking of our first coffee."))
        }
}
#endif
