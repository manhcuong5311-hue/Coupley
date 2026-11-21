//
//  TreePostcardView.swift
//  Coupley
//
//  A tree's postcard (B5.4): its place as a map snapshot framed with a stamp
//  and a postmark, its moment, planting and look, and the look picker. A
//  sheet from the place chip, or pushed from the Garden sheet.
//
//  Identity (name, place, day) changes only by a suggestion the partner
//  agrees to; the look changes at once for both (the partner can change it
//  back for 24 hours).
//

import Foundation
import SwiftUI
import MapKit
import CoreLocation

struct TreePostcardView: View {

    @ObservedObject var garden: GardenViewModel
    let slot: GardenSlot
    /// Pushed inside the Garden sheet (no own NavigationStack or Close).
    let isPushed: Bool

    @Environment(\.dismiss) private var dismiss

    init(garden: GardenViewModel, slot: GardenSlot, isPushed: Bool) {
        self.garden = garden
        self.slot = slot
        self.isPushed = isPushed
    }

    var body: some View {
        if isPushed {
            TreePostcardContent(garden: garden, slot: slot)
        } else {
            NavigationStack {
                TreePostcardContent(garden: garden, slot: slot)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                dismiss()
                            } label: {
                                Text("Close", comment: "Toolbar button: close this sheet")
                            }
                            .foregroundStyle(Brand.textSecondary)
                        }
                    }
            }
        }
    }
}

// MARK: - Content

private struct TreePostcardContent: View {

    @ObservedObject var garden: GardenViewModel
    let slot: GardenSlot

    @ObservedObject private var reachability = GardenReachability.shared

    private enum Route: Hashable {
        case change
        case look
        case proposal(String)
    }

    @State private var route: Route?
    @State private var confirmsRest = false
    /// My waiting change or rest request, until "Take it back" is confirmed.
    @State private var confirmsTakeBack: GardenProposal?
    @State private var isActing = false

    private var tree: GardenTree? { garden.tree(slot) }
    private var partnerName: String { garden.partnerName }

    private var pendingChange: GardenProposal? { garden.proposal(id: GardenDocID.change(slot)) }
    private var pendingRest: GardenProposal? {
        slot.isOurTree ? nil : garden.proposal(id: GardenDocID.rest(slot))
    }

    private func isMine(_ proposal: GardenProposal) -> Bool {
        garden.requests.first { $0.id == proposal.id }?.isMine ?? false
    }

    var body: some View {
        Group {
            if let tree {
                content(tree)
            } else {
                restingView
            }
        }
        .background(Brand.bgGradient.ignoresSafeArea())
        .navigationTitle(Text(verbatim: tree?.displayTitle ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $route) { route in
            destination(route)
        }
    }

    private func content(_ tree: GardenTree) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                postcard(tree)
                details(tree)
                pending(tree)
                actions(tree)
            }
            .padding(.horizontal, Brand.Space.gutter)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .alert(Text("Ask to let “\(tree.displayTitle)” rest?",
                    comment: "Postcard: confirmation title before asking to let a tree rest. The placeholder is the tree's title."),
               isPresented: $confirmsRest) {
            Button {
                isActing = true
                Task {
                    _ = await garden.requestRest(slot, note: nil)
                    isActing = false
                }
            } label: {
                Text("Ask \(partnerName)", comment: "Postcard: send the rest request. The placeholder is the partner's name.")
            }
            Button(role: .cancel) {} label: { Text("Cancel", comment: "Cancel a confirmation") }
        } message: {
            Text("It stays in your garden until \(partnerName) agrees. Once it rests, it's gone for both of you, with its place.",
                 comment: "Postcard: what asking to let a tree rest means. The placeholder is the partner's name.")
        }
        .alert(takeBackQuestion, isPresented: Binding(
            get: { confirmsTakeBack != nil },
            set: { if !$0 { confirmsTakeBack = nil } }
        ), presenting: confirmsTakeBack) { proposal in
            Button(role: .destructive) {
                takeBack(proposal)
            } label: {
                Text("Take it back", comment: "Seed sheet: withdraw my seed or request")
            }
            Button(role: .cancel) {} label: { Text("Cancel", comment: "Cancel a confirmation") }
        }
    }

    // MARK: The card

    private func postcard(_ tree: GardenTree) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width - 16
            let size = CGSize(width: width, height: (width * 2 / 3).rounded())
            ZStack(alignment: .topTrailing) {
                Group {
                    if let place = tree.place {
                        GardenSnapshotImage(place: place, scene: tree.look.scene, size: size)
                    } else {
                        GardenSceneSwatch(scene: tree.look.scene, size: size)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))

                stamp(tree.look.scene)
                    .padding(10)

                if let text = postmarkText(tree) {
                    postmark(text)
                        .padding(.top, 18)
                        .padding(.trailing, 64)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
            )
        }
        .aspectRatio(3 / 2, contentMode: .fit)
        .padding(.bottom, 8)
    }

    /// A perforated stamp showing the scene.
    private func stamp(_ scene: GardenSceneID) -> some View {
        GardenSceneSwatch(scene: scene, size: CGSize(width: 40, height: 48))
            .padding(3)
            .background(Color.white)
            .overlay(
                Rectangle()
                    .strokeBorder(Color.white, style: StrokeStyle(lineWidth: 3, dash: [3, 3]))
                    .padding(-1.5)
            )
            .shadow(color: .black.opacity(0.18), radius: 1.5, y: 0.5)
            .accessibilityHidden(true)
    }

    private func postmark(_ text: String) -> some View {
        Text(verbatim: text)
            .font(JourneyFont.meta.weight(.bold))
            .foregroundStyle(Color.black.opacity(0.55))
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .minimumScaleFactor(0.6)
            .padding(10)
            .frame(width: 84, height: 84)
            .overlay(Circle().strokeBorder(Color.black.opacity(0.45), lineWidth: 1.5))
            .overlay(Circle().strokeBorder(Color.black.opacity(0.3), lineWidth: 1).padding(4))
            .rotationEffect(.degrees(-12))
            .accessibilityHidden(true)
    }

    /// "LISBON · 12 MAR 2024" for an exact place, "12 MAR 2024" for an area.
    private func postmarkText(_ tree: GardenTree) -> String? {
        let day = (tree.momentDay ?? (tree.isOurTree ? tree.agreedStartDay ?? garden.anchor.startDate : nil))
            .map(GardenDayText.postmark(stored:))
            ?? tree.plantedAt.map(GardenDayText.postmark(stored:))
        guard let place = tree.place, place.precision == .exact else { return day }
        let town = (place.locality ?? place.name)
            .split(separator: ",").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? place.name
        guard let day else { return town.uppercased() }
        return String(localized: "\(town.uppercased()) · \(day)",
                      comment: "Postcard postmark: the place's town, then a date such as '12 MAR 2024'")
    }

    // MARK: Details

    private func details(_ tree: GardenTree) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let place = tree.place {
                VStack(alignment: .leading, spacing: 3) {
                    Text(place.name)
                        .font(JourneyFont.title)
                        .foregroundStyle(Brand.textPrimary)
                    if let locality = place.locality, locality != place.name {
                        Text(locality)
                            .font(JourneyFont.body)
                            .foregroundStyle(Brand.textSecondary)
                    }
                }
                .accessibilityElement(children: .combine)
            } else {
                HStack(spacing: 12) {
                    Text("No place yet", comment: "Postcard: the tree has no place")
                        .font(JourneyFont.title)
                        .foregroundStyle(Brand.textPrimary)
                    Spacer(minLength: 0)
                }
                if pendingChange == nil {
                    BrandCTA(title: String(localized: "Add a place", comment: "Postcard: suggest a place for a tree without one"),
                             icon: "mappin.and.ellipse", tier: .card) {
                        route = .change
                    }
                }
            }

            BrandCard(tier: .card) {
                VStack(alignment: .leading, spacing: 0) {
                    if let moment = tree.momentDay {
                        detailRow(LocalizedStringResource("The moment", comment: "Postcard row label: the day of the tree's moment"),
                                  value: momentText(moment))
                        divider
                    }
                    plantedRow(tree)
                    divider
                    detailRow(LocalizedStringResource("Growth", comment: "Postcard row label: the tree's growth stage"),
                              value: growthStage(tree).displayName)
                    divider
                    HStack(alignment: .firstTextBaseline) {
                        detailRow(LocalizedStringResource("Look", comment: "Postcard row label: the tree's scene and species"),
                                  value: GardenPlaceText.look(tree.look))
                        Button {
                            route = .look
                        } label: {
                            Text("Change", comment: "Postcard: open the look picker")
                                .font(JourneyFont.label)
                                .foregroundStyle(Brand.accentStart)
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(Text("Change the look", comment: "VoiceOver: open the look picker from the postcard"))
                    }
                }
            }
        }
    }

    /// "12 March 2024 · 2 years ago". The day alone for today's moment (a
    /// day has no hour: it would read "14 hours ago") and in a language iOS
    /// has no relative wording for.
    private func momentText(_ stored: Date) -> String {
        let local = JourneyCalendarDay.localDay(ofStored: stored)
        guard local < Calendar.current.startOfDay(for: Date()),
              let ago = RelativeTimeWording.namedPhrase(for: local) else {
            return GardenDayText.long(local: local)
        }
        return String(localized: "\(GardenDayText.long(local: local)) · \(ago)",
                      comment: "Postcard: the moment's day, then how long ago, as in '12 March 2024 · 2 years ago'")
    }

    @ViewBuilder
    private func plantedRow(_ tree: GardenTree) -> some View {
        if tree.origin == .legacy, tree.isOurTree {
            let start = tree.agreedStartDay ?? garden.anchor.startDate
            detailRow(nil, value: start.map {
                String(localized: "Growing since \(GardenDayText.long(stored: $0))",
                       comment: "Postcard: Our tree recorded from an existing start date. The placeholder is a date.")
            } ?? "")
        } else {
            let day = tree.plantedAt.map {
                $0.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
            }
            detailRow(LocalizedStringResource("Planted", comment: "Postcard row label: when the tree was planted"),
                      value: day.map {
                          String(localized: "Together · \($0)",
                                 comment: "Postcard: planted by both partners, then the day, as in 'Together · Sat 14 Nov 2026'")
                      } ?? String(localized: "Together", comment: "Postcard: planted by both partners (the day is still on its way)"))
        }
    }

    /// Our tree grows from the start date; a place tree from its planting.
    private func growthStage(_ tree: GardenTree) -> TreeGrowthStage {
        guard let start = tree.growthStart(ourStartDate: garden.anchor.startDate) else { return .seed }
        return TreeGrowthStage.from(daysTogether: GardenDayCount.days(fromStored: start, now: garden.now))
    }

    private func detailRow(_ label: LocalizedStringResource?, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let label {
                Text(label)
                    .font(JourneyFont.caption)
                    .foregroundStyle(Brand.textSecondary)
            }
            Text(value)
                .font(JourneyFont.label)
                .foregroundStyle(Brand.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private var divider: some View {
        Rectangle().fill(Brand.divider).frame(height: 1)
    }

    // MARK: Pending requests

    @ViewBuilder
    private func pending(_ tree: GardenTree) -> some View {
        let items = [pendingChange, pendingRest].compactMap { $0 }
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(items) { proposal in
                    pendingRow(proposal)
                }
            }
        }
    }

    private func pendingRow(_ proposal: GardenProposal) -> some View {
        let mine = isMine(proposal)
        let line: String
        switch (proposal.kind, mine) {
        case (.rest, true):
            line = String(localized: "You asked to let it rest. Waiting for \(partnerName).",
                          comment: "Postcard: my rest request waits. The placeholder is the partner's name.")
        case (.rest, false):
            line = String(localized: "\(partnerName) would like to let a tree rest",
                          comment: "Postcard: the partner's rest request waits. The placeholder is the partner's name.")
        case (_, true):
            line = String(localized: "You suggested a change. Waiting for \(partnerName).",
                          comment: "Postcard: my suggested change waits. The placeholder is the partner's name.")
        case (_, false):
            line = String(localized: "\(partnerName) suggested a change",
                          comment: "Postcard: the partner's suggested change waits. The placeholder is the partner's name.")
        }
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "hourglass")
                .font(JourneyFont.meta)
                .foregroundStyle(Brand.textTertiary)
                .accessibilityHidden(true)
            Text(line)
                .font(JourneyFont.body)
                .foregroundStyle(Brand.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if mine {
                // Withdrawing asks first: the link sits right beside the line.
                Button {
                    confirmsTakeBack = proposal
                } label: {
                    Text("Take it back", comment: "Seed sheet: withdraw my seed or request")
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .disabled(!reachability.isOnline || isActing)
            } else {
                Button {
                    route = .proposal(proposal.id)
                } label: {
                    Text("Take a look", comment: "Postcard: open the partner's request")
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
            }
        }
        .font(JourneyFont.label)
        .foregroundStyle(Brand.accentStart)
        .buttonStyle(.borderless)
    }

    private var takeBackQuestion: Text {
        if confirmsTakeBack?.kind == .rest {
            return Text("Take back your request to let it rest?",
                        comment: "Postcard: confirmation before withdrawing my request to let this tree rest")
        }
        return Text("Take back your suggested change?",
                    comment: "Postcard: confirmation before withdrawing my suggested change to this tree")
    }

    private func takeBack(_ proposal: GardenProposal) {
        isActing = true
        Task {
            _ = await garden.takeBack(proposal.id)
            isActing = false
        }
    }

    // MARK: Actions

    private func actions(_ tree: GardenTree) -> some View {
        VStack(spacing: 6) {
            if let place = tree.place {
                BrandCTA(title: String(localized: "Open in Maps", comment: "Postcard: open the tree's place in Apple Maps"),
                         icon: "map", tier: .card) {
                    openInMaps(place)
                }
            }
            if pendingChange == nil {
                textButton(String(localized: "Suggest a change", comment: "Postcard: suggest a new name, place or day for the tree")) {
                    route = .change
                }
            }
            if !tree.isOurTree, pendingRest == nil {
                textButton(String(localized: "Let this tree rest…", comment: "Postcard: ask the partner to let this tree go")) {
                    confirmsRest = true
                }
                .disabled(!reachability.isOnline || isActing)
            }
        }
    }

    private func textButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(JourneyFont.label)
                .foregroundStyle(Brand.accentStart)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    /// Apple Maps at the stored spot, under the place's name.
    private func openInMaps(_ place: GardenPlace) {
        let item: MKMapItem
        if #available(iOS 26, *) {
            item = MKMapItem(location: CLLocation(latitude: place.latitude, longitude: place.longitude), address: nil)
        } else {
            item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: place.latitude,
                                                                                       longitude: place.longitude)))
        }
        item.name = place.name
        item.openInMaps(launchOptions: nil)
    }

    // MARK: Resting

    private var restingView: some View {
        VStack(spacing: 12) {
            Image(systemName: "leaf")
                .font(.largeTitle)
                .foregroundStyle(Brand.textTertiary)
                .accessibilityHidden(true)
            Text(GardenCopy.treeResting)
                .font(JourneyFont.body)
                .foregroundStyle(Brand.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(Brand.Space.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Destinations

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .change:
            GardenPlantForm(garden: garden, mode: .changeTree(slot)) {
                self.route = nil
            }
        case .look:
            GardenLookPicker(garden: garden, slot: slot) {
                self.route = nil
            }
        case .proposal(let id):
            GardenSeedSheet(garden: garden, proposalId: id, onPlanted: {}, onOpenTree: { _ in self.route = nil },
                            isPushed: true)
        }
    }
}

// MARK: - Look picker

/// "Change the look" (B5.4): the 8 scenes, the species, and the one filled
/// "Save look". The look changes at once for both partners.
private struct GardenLookPicker: View {

    @ObservedObject var garden: GardenViewModel
    let slot: GardenSlot
    let onDone: () -> Void

    @State private var look: GardenLook
    @State private var isSaving = false
    /// The last Save look did not go through: the picker stays with its reason.
    @State private var failed = false

    init(garden: GardenViewModel, slot: GardenSlot, onDone: @escaping () -> Void) {
        self.garden = garden
        self.slot = slot
        self.onDone = onDone
        _look = State(initialValue: garden.tree(slot)?.look ?? .ourTreeDefault)
    }

    private var current: GardenLook? { garden.tree(slot)?.look }

    private var speciesChoices: [GardenSpecies] {
        slot.isOurTree ? GardenSpecies.ourTreeChoices : GardenSpecies.allCases
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 14) {
                    ForEach(GardenSceneID.allCases) { scene in
                        sceneCell(scene)
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(speciesChoices) { species in
                            GardenChip(title: species.displayName, isSelected: look.species == species) {
                                look.species = species
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Text("\(garden.partnerName) sees the new look right away.",
                     comment: "Look picker footer. The placeholder is the partner's name.")
                    .font(JourneyFont.meta)
                    .foregroundStyle(Brand.textSecondary)
            }
            .padding(.horizontal, Brand.Space.gutter)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .background(Brand.bgGradient.ignoresSafeArea())
        .navigationTitle(Text("Change the look", comment: "Look picker: navigation title"))
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if let message = footerMessage {
                    Text(message)
                        .font(JourneyFont.meta)
                        .foregroundStyle(Brand.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                BrandCTA(title: String(localized: "Save look", comment: "Look picker: the filled button"),
                         tier: .hero, isEnabled: look != current && garden.canChangeLook(slot), isBusy: isSaving) {
                    save()
                }
            }
            .padding(.horizontal, Brand.Space.gutter)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .background(.bar)
        }
    }

    /// Why Save look did not go through, or why it cannot now (the garden
    /// is unavailable, or Our tree is not recorded yet).
    private var footerMessage: String? {
        if failed, let message = garden.errorMessage { return message }
        guard !garden.canChangeLook(slot) else { return nil }
        return garden.availability.allowsWrites
            ? GardenCopy.lookFailed
            : GardenError.denied.message(partnerName: garden.partnerName, now: garden.now)
    }

    /// Closes only once the change is sent; otherwise stays with the reason.
    private func save() {
        isSaving = true
        failed = false
        Task {
            let saved = await garden.changeLook(slot, to: look)
            isSaving = false
            if saved { onDone() } else { failed = true }
        }
    }

    private func sceneCell(_ scene: GardenSceneID) -> some View {
        let isSelected = look.scene == scene
        let isCurrent = current?.scene == scene
        return Button {
            look = GardenLook(scene: scene,
                              species: speciesChoices.contains(look.species)
                                ? look.species
                                : GardenLook.suggested(scene: scene, forOurTree: slot.isOurTree).species)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { proxy in
                    GardenSceneSwatch(scene: scene, size: proxy.size)
                }
                .aspectRatio(3 / 2, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: Brand.cornerStyle))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: Brand.cornerStyle)
                        .strokeBorder(isSelected ? Brand.accentStart : Brand.divider, lineWidth: isSelected ? 3 : 1)
                )
                HStack(spacing: 4) {
                    Text(scene.displayName)
                        .font(JourneyFont.label)
                        .foregroundStyle(isSelected ? Brand.accentStart : Brand.textPrimary)
                    if isCurrent {
                        // Own key: a plain "Now" key is a sealed letter's countdown chip.
                        Text(LocalizedStringResource("garden.look.current", defaultValue: "Now",
                                                     comment: "Look picker: a small tag after a scene's name that marks the scene the tree has now (its current look), as in 'Meadow  Now'. Not a countdown."))
                            .font(JourneyFont.meta)
                            .foregroundStyle(Brand.textSecondary)
                    }
                }
            }
        }
        .buttonStyle(BouncyButtonStyle(scale: 0.97))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Postcard") {
    TreePostcardView(garden: GardenPreviewGarden.make(), slot: .our, isPushed: false)
}
#endif
