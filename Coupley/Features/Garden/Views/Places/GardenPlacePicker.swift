//
//  GardenPlacePicker.swift
//  Coupley
//
//  "Where is it?" (D1): search or drop a pin, pushed inside the plant form
//  (never a second sheet). Returns a GardenPlaceCandidate, or nil for
//  "Skip for now".
//
//  Privacy by default: a point of interest keeps its exact spot; an address
//  or a dropped pin (it may be someone's home) keeps only its area, named
//  after the neighbourhood or city, never the street. The map starts on the
//  garden's own places or the phone's country, never on the device.
//

import Foundation
import SwiftUI
import MapKit
import CoreLocation

struct GardenPlacePicker: View {

    @ObservedObject var garden: GardenViewModel
    let onChoose: (GardenPlaceCandidate?) -> Void

    @StateObject private var search = GardenPlaceSearch()
    @ObservedObject private var reachability = GardenReachability.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Tab: Hashable { case search, pin }

    /// The confirmation card's editable values (a chosen result).
    private struct Confirmation: Equatable {
        var name: String
        var locality: String?
        var latitude: Double
        var longitude: Double
        var isExact: Bool
        var poiCategory: String?
        var timeZoneId: String?
        var isAddressOrPin: Bool
        var group: GardenPOIGroup?
        var countryCode: String?

        init(candidate: GardenPlaceCandidate) {
            let place = candidate.place
            name = place.name
            locality = place.locality
            latitude = place.latitude
            longitude = place.longitude
            isExact = place.precision == .exact
            poiCategory = place.poiCategory
            timeZoneId = place.timeZoneId
            isAddressOrPin = candidate.isAddressOrPin
            group = candidate.group
            countryCode = candidate.countryCode
        }

        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }

    @State private var tab: Tab = .search
    @State private var confirmation: Confirmation?
    @State private var resolvingId: Int?
    @State private var resolveFailed = false
    @State private var startRegion: MKCoordinateRegion?

    // Drop a pin
    @State private var pinCamera: MapCameraPosition = .automatic
    @State private var pinCenter: CLLocationCoordinate2D?
    @State private var pinDescription: GardenPlaceSearch.PinDescription?
    @State private var pinName = ""
    @State private var pinNameEdited = false
    @State private var pinIsExact = false
    @State private var isDescribingPin = false

    @FocusState private var searchFocused: Bool

    init(garden: GardenViewModel, onChoose: @escaping (GardenPlaceCandidate?) -> Void) {
        self.garden = garden
        self.onChoose = onChoose
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            Picker(selection: $tab) {
                Text("Search", comment: "Place picker: segment to search for a place by name").tag(Tab.search)
                Text("Drop a pin", comment: "Place picker: segment to put a pin on a map").tag(Tab.pin)
            } label: {
                Text("How to choose the place", comment: "Place picker: VoiceOver label of the search / pin switch")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Brand.Space.gutter)
            .padding(.vertical, 10)

            switch tab {
            case .search:
                if let confirmation {
                    confirmationView(confirmation)
                } else {
                    searchView
                }
            case .pin:
                pinView
            }
        }
        .background(Brand.bgGradient.ignoresSafeArea())
        .navigationTitle(Text("Where is it?", comment: "Place picker: navigation title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    onChoose(nil)
                } label: {
                    Text("Skip for now", comment: "Place picker: leave without choosing a place")
                }
                .foregroundStyle(Brand.textSecondary)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let bottom = bottomAction {
                BrandCTA(title: String(localized: "Use this place", comment: "Place picker: the filled button that picks the place"),
                         icon: "mappin.and.ellipse",
                         tier: .hero,
                         isEnabled: bottom.isEnabled) {
                    bottom.action()
                }
                .padding(.horizontal, Brand.Space.gutter)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
        }
        .task { await frameMap() }
        .onDisappear { search.cancel() }
    }

    /// The filled control: present on a confirmation card or the pin card.
    private var bottomAction: (isEnabled: Bool, action: () -> Void)? {
        switch tab {
        case .search:
            guard let confirmation else { return nil }
            let name = confirmation.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return (!name.isEmpty, { choose(confirmation) })
        case .pin:
            guard let pinCenter else { return nil }
            let name = pinName.trimmingCharacters(in: .whitespacesAndNewlines)
            return (!name.isEmpty, { choosePin(at: pinCenter) })
        }
    }

    // MARK: - Search

    private var searchView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                searchField

                if !reachability.isOnline {
                    stateLine(String(localized: "Place search needs a connection. Drop a pin or skip for now.",
                                     comment: "Place picker: offline"))
                } else if search.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    beforeTyping
                } else {
                    results
                }

                privacyFootnote
            }
            .padding(.horizontal, Brand.Space.gutter)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Brand.textTertiary)
                .accessibilityHidden(true)
            TextField(text: $search.query) {
                Text("Search for a place or address", comment: "Place picker: search field placeholder")
            }
            .font(JourneyFont.body)
            .foregroundStyle(Brand.textPrimary)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(.search)
            .focused($searchFocused)
            .disabled(!reachability.isOnline)
            if !search.query.isEmpty {
                Button {
                    search.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Brand.textTertiary)
                }
                .accessibilityLabel(Text("Clear the search", comment: "Place picker: VoiceOver label of the clear button"))
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .wellBackground(in: .card)
    }

    @ViewBuilder
    private var beforeTyping: some View {
        let gardenPlaces = gardenPlaceEntries
        let recent = GardenPlaceSearch.recentPicks().filter { pick in
            !gardenPlaces.contains { $0.place.latitude == pick.latitude && $0.place.longitude == pick.longitude }
        }

        if !gardenPlaces.isEmpty {
            section(LocalizedStringResource("Your garden's places", comment: "Place picker: places other trees already stand at")) {
                ForEach(Array(gardenPlaces.enumerated()), id: \.offset) { index, entry in
                    if index > 0 { rule }
                    placeRow(symbol: GardenPlaceSearch.symbol(for: GardenPlaceSearch.group(forStoredCategory: entry.place.poiCategory)),
                             title: entry.place.name,
                             subtitle: entry.treeTitle) {
                        let group = GardenPlaceSearch.group(forStoredCategory: entry.place.poiCategory)
                        confirmation = Confirmation(candidate: GardenPlaceCandidate(
                            place: entry.place, isAddressOrPin: entry.place.poiCategory == nil,
                            group: group, countryCode: nil))
                    }
                }
            }
        }

        if !recent.isEmpty {
            // Own key: a plain "Recent" key is the notifications header.
            section(LocalizedStringResource("garden.places.recent", defaultValue: "Recent",
                                            comment: "Place picker: section header above the places (cafés, parks, addresses) picked recently on this phone. Not notifications.")) {
                ForEach(Array(recent.enumerated()), id: \.offset) { index, place in
                    if index > 0 { rule }
                    placeRow(symbol: "clock.arrow.circlepath", title: place.name, subtitle: place.locality) {
                        confirmation = Confirmation(candidate: GardenPlaceCandidate(
                            place: place, isAddressOrPin: place.precision == .area, group: nil, countryCode: nil))
                    }
                }
            }
        }

        Text("Search by name, like “Highlands Coffee Nguyễn Huệ” or “Lisbon Oceanarium”.",
             comment: "Place picker: hint before typing. Replace the two examples with a well-known café and a landmark familiar in your language's main country.")
            .font(JourneyFont.body)
            .foregroundStyle(Brand.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var results: some View {
        switch search.phase {
        case .idle, .searching:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Searching…", comment: "Place picker: waiting for search results")
                    .font(JourneyFont.body)
                    .foregroundStyle(Brand.textSecondary)
            }
            .padding(.horizontal, 4)
        case .noResults:
            stateLine(String(localized: "No places found for “\(search.query)”. Try another name, or drop a pin.",
                             comment: "Place picker: no results. The placeholder is what the user typed."))
        case .failed:
            stateLine(String(localized: "Couldn't search right now. Try again, or drop a pin.",
                             comment: "Place picker: the search failed"))
        case .results:
            BrandCard(tier: .card) {
                VStack(spacing: 0) {
                    ForEach(search.suggestions) { suggestion in
                        if suggestion.id > 0 { rule }
                        placeRow(symbol: suggestion.looksLikeAddress ? "signpost.right" : "mappin.circle",
                                 title: suggestion.title,
                                 subtitle: suggestion.subtitle.isEmpty ? nil : suggestion.subtitle,
                                 isBusy: resolvingId == suggestion.id) {
                            resolve(suggestion)
                        }
                    }
                }
            }
            if resolveFailed {
                stateLine(String(localized: "Couldn't search right now. Try again, or drop a pin.",
                                 comment: "Place picker: the search failed"))
            }
        }
    }

    // MARK: - Confirmation

    private func confirmationView(_ value: Confirmation) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Button {
                    confirmation = nil
                } label: {
                    // `backward` mirrors in right-to-left languages.
                    Label {
                        Text("Back to the results", comment: "Place picker: leave the confirmation card")
                    } icon: {
                        Image(systemName: "chevron.backward")
                    }
                    .font(JourneyFont.label)
                    .foregroundStyle(Brand.accentStart)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }

                BrandCard(tier: .card, insetsContent: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        miniMap(value)
                            .frame(height: 150)
                            .clipShape(UnevenRoundedRectangle(topLeadingRadius: Brand.cardCornerRadius,
                                                              topTrailingRadius: Brand.cardCornerRadius,
                                                              style: Brand.cornerStyle))
                        VStack(alignment: .leading, spacing: 12) {
                            nameField(text: Binding(
                                get: { confirmation?.name ?? "" },
                                set: { confirmation?.name = GardenLimits.placeName.truncate($0) }))
                            if let locality = value.locality {
                                Text(locality)
                                    .font(JourneyFont.body)
                                    .foregroundStyle(Brand.textSecondary)
                            }
                            precisionToggle(isOn: Binding(
                                get: { confirmation?.isExact ?? false },
                                set: { confirmation?.isExact = $0 }))
                        }
                        .padding(16)
                    }
                }

                privacyFootnote
            }
            .padding(.horizontal, Brand.Space.gutter)
            .padding(.bottom, 24)
        }
    }

    /// A small, still map of the chosen spot (or its area).
    private func miniMap(_ value: Confirmation) -> some View {
        let span: CLLocationDistance = value.isExact ? 800 : 6000
        return Map(initialPosition: .region(MKCoordinateRegion(center: value.coordinate,
                                                               latitudinalMeters: span, longitudinalMeters: span)),
                   interactionModes: []) {
            if value.isExact {
                Marker(value.name, systemImage: "tree.fill", coordinate: value.coordinate)
                    .tint(Brand.accentStart)
            } else {
                MapCircle(center: value.coordinate, radius: 600)
                    .foregroundStyle(Brand.accentStart.opacity(0.15))
                    .stroke(Brand.accentStart.opacity(0.55), lineWidth: 1.5)
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .id(value.isExact)
        .accessibilityHidden(true)
    }

    // MARK: - Drop a pin

    private var pinView: some View {
        VStack(spacing: 0) {
            ZStack {
                Map(position: $pinCamera)
                    .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
                    .mapControls {
                        MapCompass()
                        MapScaleView()
                    }
                    .onMapCameraChange(frequency: .onEnd) { context in
                        pinMoved(to: context.region.center)
                    }
                    .accessibilityLabel(Text("Map. Move it to put the pin on the spot.",
                                             comment: "VoiceOver: the map under the fixed pin in the place picker"))

                // The fixed centre pin: its point sits on the map's centre.
                Image(systemName: "mappin")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Brand.accentStart)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    .offset(y: -17)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Move the map to put the pin on the spot.",
                     comment: "Place picker, drop a pin: instruction under the map")
                    .font(JourneyFont.body)
                    .foregroundStyle(Brand.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if pinCenter != nil {
                    HStack(spacing: 8) {
                        nameField(text: Binding(
                            get: { pinName },
                            set: {
                                pinName = GardenLimits.placeName.truncate($0)
                                pinNameEdited = true
                            }))
                        if isDescribingPin {
                            ProgressView().controlSize(.small)
                        }
                    }
                    if let locality = pinDescription?.locality {
                        Text(locality)
                            .font(JourneyFont.body)
                            .foregroundStyle(Brand.textSecondary)
                    }
                    precisionToggle(isOn: $pinIsExact)
                }

                privacyFootnote
            }
            .padding(.horizontal, Brand.Space.gutter)
            .padding(.top, 14)
            .padding(.bottom, 4)
        }
    }

    private func pinMoved(to center: CLLocationCoordinate2D) {
        pinCenter = center
        isDescribingPin = true
        Task {
            let description = await search.describePin(at: center)
            // nil also when a newer pin was asked about: keep waiting for it.
            guard let description else {
                if pinCenter.map({ $0.latitude == center.latitude && $0.longitude == center.longitude }) ?? false {
                    isDescribingPin = false
                }
                return
            }
            isDescribingPin = false
            pinDescription = description
            if !pinNameEdited {
                pinName = GardenLimits.placeName.truncate(description.name ?? "")
            }
        }
    }

    // MARK: - Pieces

    private func nameField(text: Binding<String>) -> some View {
        TextField(text: text) {
            Text("Name this place", comment: "Place picker: placeholder of the place's editable name")
        }
        .font(JourneyFont.title)
        .foregroundStyle(Brand.textPrimary)
        .textInputAutocapitalization(.words)
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .wellBackground(in: .card)
    }

    private func precisionToggle(isOn: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: isOn.animation(reduceMotion ? nil : .snappy)) {
                Text("Show the exact spot", comment: "Place picker: keep the exact position (about 11 m) instead of only the area")
                    .font(JourneyFont.label)
                    .foregroundStyle(Brand.textPrimary)
            }
            .tint(Brand.accentStart)
            if !isOn.wrappedValue {
                Text("Only the area (about 1 km)", comment: "Place picker: what is kept when the exact spot is off")
                    .font(JourneyFont.meta)
                    .foregroundStyle(Brand.textSecondary)
            }
        }
    }

    private var privacyFootnote: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "lock.fill")
                .font(JourneyFont.meta)
                .foregroundStyle(Brand.textTertiary)
                .accessibilityHidden(true)
            Text("Only you and \(garden.partnerName) can see this place. Coupley never reads your phone's location.",
                 comment: "Place picker footnote on every step. The placeholder is the partner's name.")
                .font(JourneyFont.meta)
                .foregroundStyle(Brand.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }

    private func stateLine(_ text: String) -> some View {
        Text(text)
            .font(JourneyFont.body)
            .foregroundStyle(Brand.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    private func section<Content: View>(_ title: LocalizedStringResource,
                                        @ViewBuilder content: () -> Content) -> some View {
        // Built here: BrandCard keeps its content closure (escaping).
        let rows = content()
        return VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(JourneyFont.caption)
                .foregroundStyle(Brand.textSecondary)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 4)
            BrandCard(tier: .card) {
                VStack(spacing: 0) { rows }
            }
        }
    }

    private func placeRow(symbol: String, title: String, subtitle: String?, isBusy: Bool = false,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(JourneyFont.title)
                    .foregroundStyle(Brand.accentStart)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(JourneyFont.label)
                        .foregroundStyle(Brand.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(JourneyFont.meta)
                            .foregroundStyle(Brand.textSecondary)
                            .lineLimit(2)
                    }
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if isBusy {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(resolvingId != nil)
    }

    private var rule: some View {
        Rectangle().fill(Brand.divider).frame(height: 1)
    }

    // MARK: - Data

    /// The garden's own places (other trees), one per spot.
    private var gardenPlaceEntries: [(place: GardenPlace, treeTitle: String)] {
        var seen = Set<String>()
        return GardenSlot.allCases.compactMap { slot in
            guard let tree = garden.tree(slot), let place = tree.place else { return nil }
            let key = "\(place.latitude),\(place.longitude),\(place.name)"
            guard seen.insert(key).inserted else { return nil }
            return (place, tree.displayTitle)
        }
    }

    /// The map starts on the garden's places, else the phone's country,
    /// else the world (D1). Never the device's position.
    private func frameMap() async {
        guard startRegion == nil else { return }
        let gardenRegion = GardenPlaceSearch.region(fitting: gardenPlaceEntries.map(\.place))
        let region: MKCoordinateRegion
        if let gardenRegion {
            region = gardenRegion
        } else if let country = await search.countryRegion() {
            region = country
        } else {
            region = GardenPlaceSearch.worldRegion
        }
        startRegion = region
        search.setRegion(region)
        pinCamera = .region(region)
    }

    private func resolve(_ suggestion: GardenPlaceSearch.Suggestion) {
        searchFocused = false
        resolveFailed = false
        resolvingId = suggestion.id
        Task {
            defer { resolvingId = nil }
            do {
                let candidate = try await search.resolve(suggestion)
                confirmation = Confirmation(candidate: candidate)
            } catch {
                resolveFailed = true
            }
        }
    }

    private func choose(_ value: Confirmation) {
        let place = GardenPlace(name: value.name.trimmingCharacters(in: .whitespacesAndNewlines),
                                locality: value.locality,
                                latitude: value.latitude, longitude: value.longitude,
                                precision: value.isExact ? .exact : .area,
                                poiCategory: value.poiCategory, timeZoneId: value.timeZoneId)
        GardenPlaceSearch.remember(place)
        onChoose(GardenPlaceCandidate(place: place, isAddressOrPin: value.isAddressOrPin,
                                      group: value.group, countryCode: value.countryCode))
    }

    private func choosePin(at center: CLLocationCoordinate2D) {
        let place = GardenPlace(name: pinName.trimmingCharacters(in: .whitespacesAndNewlines),
                                locality: pinDescription?.locality.map(GardenLimits.locality.truncate),
                                latitude: center.latitude, longitude: center.longitude,
                                precision: pinIsExact ? .exact : .area,
                                timeZoneId: pinDescription?.timeZoneId)
        GardenPlaceSearch.remember(place)
        onChoose(GardenPlaceCandidate(place: place, isAddressOrPin: true, group: nil,
                                      countryCode: pinDescription?.countryCode))
    }
}
