//
//  GardenPlaceSearch.swift
//  Coupley
//
//  Place search for the garden's place picker (D1, D2): as-you-type
//  suggestions from MKLocalSearchCompleter, resolving a suggestion with
//  MKLocalSearch, naming a dropped pin by reverse geocoding, mapping MapKit's
//  point-of-interest categories to GardenPOIGroup (D4), and this phone's last
//  five picks ("Recent", purged with the garden caches).
//
//  Never reads the device's location: no CLLocationManager, no user
//  location, no NSLocation… key. Importing CoreLocation never prompts.
//
//  What leaves the phone: the text typed into the search and the map areas
//  shown go to Apple (MapKit), as the privacy page says. Nothing typed is
//  stored; a picked place keeps only what D3 lists.
//

import Foundation
import Combine
import MapKit
import CoreLocation
import Network

// MARK: - Candidate

/// What the place picker hands back to the plant form (P9-internal). The
/// country code only suggests a look; it is never stored.
nonisolated struct GardenPlaceCandidate: Equatable, Sendable {
    /// Already rounded to its precision.
    var place: GardenPlace
    /// An address result or a dropped pin (it may be someone's home).
    var isAddressOrPin: Bool
    /// nil for an address or a dropped pin.
    var group: GardenPOIGroup?
    /// ISO 3166-1 alpha-2, from the map item; used only for the look.
    var countryCode: String?
}

// MARK: - Search

@MainActor
final class GardenPlaceSearch: NSObject, ObservableObject {

    /// One as-you-type suggestion.
    struct Suggestion: Identifiable {
        let id: Int
        let title: String
        let subtitle: String
        /// An address (a street and number) rather than a named place.
        let looksLikeAddress: Bool
        fileprivate let completion: MKLocalSearchCompletion
    }

    enum Phase: Equatable {
        /// Nothing typed yet.
        case idle
        case searching
        case results
        case noResults
        case failed
    }

    /// What a dropped pin is near, from reverse geocoding. Never a street.
    struct PinDescription: Equatable {
        /// "Near Hoàn Kiếm Lake", the neighbourhood or the city.
        var name: String?
        /// "Hoàn Kiếm, Hà Nội": district and city (+ country abroad).
        var locality: String?
        var timeZoneId: String?
        var countryCode: String?
    }

    /// The text in the search field. Changes reach the completer after 250 ms.
    @Published var query = "" {
        didSet { scheduleQuery() }
    }
    @Published private(set) var suggestions: [Suggestion] = []
    @Published private(set) var phase: Phase = .idle

    /// At most this many rows (D1).
    static let maxSuggestions = 12
    /// "Recent": this phone's last picks.
    static let maxRecentPicks = 5

    private let completer = MKLocalSearchCompleter()
    private var debounce: Task<Void, Never>?
    private let geocoder = CLGeocoder()
    /// Bumped by every pin description request; stale answers are dropped.
    private var pinGeneration = 0

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.pointOfInterest, .address]
        completer.pointOfInterestFilter = .includingAll
    }

    /// The bias for suggestions (the garden's places, else the country).
    func setRegion(_ region: MKCoordinateRegion) {
        completer.region = region
    }

    /// Stops pending work when the picker goes away.
    func cancel() {
        debounce?.cancel()
        completer.cancel()
        geocoder.cancelGeocode()
    }

    // MARK: Typing

    private func scheduleQuery() {
        debounce?.cancel()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            completer.cancel()
            suggestions = []
            phase = .idle
            return
        }
        phase = .searching
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            self.completer.queryFragment = text
        }
    }

    fileprivate func completerUpdated(_ results: [MKLocalSearchCompletion]) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        suggestions = results.prefix(Self.maxSuggestions).enumerated().map { index, completion in
            Suggestion(id: index, title: completion.title, subtitle: completion.subtitle,
                       looksLikeAddress: completion.title.first?.isNumber ?? false,
                       completion: completion)
        }
        phase = suggestions.isEmpty ? .noResults : .results
    }

    fileprivate func completerFailed(_ error: Error) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        // "No results" arrives as an error from the completer.
        if let mapError = error as? MKError, mapError.code == .placemarkNotFound {
            suggestions = []
            phase = .noResults
        } else {
            phase = .failed
        }
    }

    // MARK: Resolving

    /// The place behind a suggestion, rounded to its default precision: a
    /// point of interest keeps the exact spot, an address only its area
    /// (named after its locality, never the street).
    func resolve(_ suggestion: Suggestion) async throws -> GardenPlaceCandidate {
        let request = MKLocalSearch.Request(completion: suggestion.completion)
        request.resultTypes = [.pointOfInterest, .address]
        let response = try await MKLocalSearch(request: request).start()
        guard let item = response.mapItems.first else { throw MKError(.placemarkNotFound) }
        return Self.candidate(from: item, fallbackName: suggestion.title)
    }

    /// The candidate a map item describes (D1 precision defaults, D3 fields).
    static func candidate(from item: MKMapItem, fallbackName: String) -> GardenPlaceCandidate {
        let fields = MapItemFields(item)
        let category = item.pointOfInterestCategory
        let isAddress = category == nil && fields.nameIsAddress
        let name: String
        if isAddress {
            name = fields.cityName ?? fields.locality ?? fallbackName
        } else {
            name = item.name ?? fallbackName
        }
        let place = GardenPlace(name: GardenLimits.placeName.truncate(name),
                                locality: fields.locality.map(GardenLimits.locality.truncate),
                                latitude: fields.coordinate.latitude,
                                longitude: fields.coordinate.longitude,
                                precision: isAddress ? .area : .exact,
                                poiCategory: isAddress ? nil : category?.rawValue,
                                timeZoneId: item.timeZone?.identifier)
        return GardenPlaceCandidate(place: place, isAddressOrPin: isAddress,
                                    group: isAddress ? nil : group(for: category),
                                    countryCode: fields.countryCode)
    }

    // MARK: Pins

    /// What a dropped pin is near (D1): an area of interest, the
    /// neighbourhood or the city; never a street. nil offline, on failure, or
    /// when a newer pin was asked about meanwhile.
    func describePin(at coordinate: CLLocationCoordinate2D) async -> PinDescription? {
        pinGeneration += 1
        let generation = pinGeneration
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let description: PinDescription?
        if #available(iOS 26, *) {
            description = await Self.describeWithMapKit(location)
        } else {
            geocoder.cancelGeocode()
            description = await describeWithGeocoder(location)
        }
        return generation == pinGeneration ? description : nil
    }

    @available(iOS 26, *)
    private static func describeWithMapKit(_ location: CLLocation) async -> PinDescription? {
        guard let request = MKReverseGeocodingRequest(location: location),
              let item = try? await request.mapItems.first else { return nil }
        let fields = MapItemFields(item)
        return PinDescription(name: fields.cityName ?? fields.locality, locality: fields.locality,
                              timeZoneId: item.timeZone?.identifier, countryCode: fields.countryCode)
    }

    private func describeWithGeocoder(_ location: CLLocation) async -> PinDescription? {
        guard let placemark = try? await geocoder.reverseGeocodeLocation(location).first else { return nil }
        let name: String?
        if let area = placemark.areasOfInterest?.first {
            name = String(localized: "Near \(area)",
                          comment: "Place picker: the proposed name of a dropped pin. The placeholder is a landmark or area, such as 'Hoàn Kiếm Lake'.")
        } else {
            name = placemark.subLocality ?? placemark.locality
        }
        return PinDescription(name: name,
                              locality: Self.locality(district: placemark.subLocality, city: placemark.locality,
                                                      country: placemark.country, countryCode: placemark.isoCountryCode),
                              timeZoneId: placemark.timeZone?.identifier,
                              countryCode: placemark.isoCountryCode)
    }

    // MARK: Framing the map

    /// The phone's country, framed by one MKLocalSearch for its name (D1:
    /// where the map starts when the garden has no places). Never the
    /// device's position. Remembered for the session.
    func countryRegion() async -> MKCoordinateRegion? {
        if let cached = Self.countryRegionCache { return cached }
        guard let code = Locale.current.region?.identifier,
              let name = Locale.current.localizedString(forRegionCode: code) else { return nil }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = name
        request.resultTypes = .address
        guard let response = try? await MKLocalSearch(request: request).start() else { return nil }
        Self.countryRegionCache = response.boundingRegion
        return response.boundingRegion
    }

    private static var countryRegionCache: MKCoordinateRegion?

    /// The whole world, the last fallback.
    static let worldRegion = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 20, longitude: 0),
                                                span: MKCoordinateSpan(latitudeDelta: 140, longitudeDelta: 360))

    /// The bounding box of `places` with 20% padding; one place gets an
    /// 800 m span. nil without places.
    static func region(fitting places: [GardenPlace]) -> MKCoordinateRegion? {
        guard let first = places.first else { return nil }
        var minLat = first.latitude, maxLat = first.latitude
        var minLng = first.longitude, maxLng = first.longitude
        for place in places.dropFirst() {
            minLat = min(minLat, place.latitude); maxLat = max(maxLat, place.latitude)
            minLng = min(minLng, place.longitude); maxLng = max(maxLng, place.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2)
        if places.count == 1 || (maxLat - minLat < 0.0001 && maxLng - minLng < 0.0001) {
            return MKCoordinateRegion(center: center, latitudinalMeters: 800, longitudinalMeters: 800)
        }
        let span = MKCoordinateSpan(latitudeDelta: min(170, max(0.01, (maxLat - minLat) * 1.2)),
                                    longitudeDelta: min(360, max(0.01, (maxLng - minLng) * 1.2)))
        return MKCoordinateRegion(center: center, span: span)
    }

    // MARK: Point-of-interest groups

    /// The contract group for a MapKit category (D4), by constant, never by
    /// comparing raw strings.
    nonisolated static func group(for category: MKPointOfInterestCategory?) -> GardenPOIGroup? {
        guard let category else { return nil }
        switch category {
        case .beach, .surfing, .swimming:
            return .beach
        case .marina, .aquarium, .kayaking, .fishing:
            return .water
        case .park, .zoo, .golf, .miniGolf:
            return .park
        case .cafe, .bakery, .restaurant, .foodMarket, .brewery, .winery, .distillery, .store:
            return .food
        case .nightlife, .theater, .movieTheater, .musicVenue, .hotel, .spa, .beauty, .fitnessCenter,
             .bowling, .conventionCenter, .planetarium, .skating:
            return .nightOut
        case .nationalPark, .campground, .hiking, .rockClimbing, .skiing, .rvPark:
            return .nature
        case .museum, .landmark, .nationalMonument, .castle, .fortress:
            return .heritage
        case .university, .school, .library:
            return .campus
        case .amusementPark, .stadium, .fairground, .baseball, .basketball, .soccer, .tennis, .volleyball,
             .goKart, .skatePark:
            return .sportsFun
        case .airport, .publicTransport, .carRental:
            return .travel
        default:
            return .other
        }
    }

    /// The group of a stored place (its `poi` raw value), to re-suggest a look.
    nonisolated static func group(forStoredCategory raw: String?) -> GardenPOIGroup? {
        raw.map { group(for: MKPointOfInterestCategory(rawValue: $0)) } ?? nil
    }

    /// The SF Symbol of a group, for result rows and the garden's places.
    nonisolated static func symbol(for group: GardenPOIGroup?) -> String {
        switch group {
        case .beach?:     return "beach.umbrella"
        case .water?:     return "water.waves"
        case .park?:      return "tree"
        case .food?:      return "cup.and.saucer"
        case .nightOut?:  return "music.note"
        case .nature?:    return "mountain.2"
        case .heritage?:  return "building.columns"
        case .campus?:    return "graduationcap"
        case .sportsFun?: return "figure.run"
        case .travel?:    return "airplane"
        case .other?, nil: return "mappin"
        }
    }

    // MARK: Locality

    /// "Hoàn Kiếm, Hà Nội", or "Lisbon, Portugal" abroad: district and city
    /// (+ the country when it is not the phone's). Never a street.
    nonisolated static func locality(district: String?, city: String?, country: String?,
                                     countryCode: String?) -> String? {
        var parts: [String] = []
        if let district, !district.isEmpty { parts.append(district) }
        if let city, !city.isEmpty, city != district { parts.append(city) }
        if let country, !country.isEmpty, let countryCode,
           countryCode.uppercased() != Locale.current.region?.identifier.uppercased() {
            parts.append(country)
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    // MARK: Recent picks

    /// One remembered pick: names and coordinates only.
    private struct RecentPick: Codable, Equatable {
        var name: String
        var locality: String?
        var latitude: Double
        var longitude: Double
        var precision: GardenPlacePrecision
    }

    /// Under the garden's prefix, so leaving `.ready` purges it with the
    /// rest of the garden's keys as well as through `purgeRecentPicks()`.
    private static let recentPicksKey = GardenDefaultsKey.prefix + "recentPlaces"

    /// This phone's last picks, newest first.
    static func recentPicks() -> [GardenPlace] {
        guard let data = UserDefaults.standard.data(forKey: recentPicksKey),
              let picks = try? JSONDecoder().decode([RecentPick].self, from: data) else { return [] }
        return picks.map {
            GardenPlace(name: $0.name, locality: $0.locality, latitude: $0.latitude,
                        longitude: $0.longitude, precision: $0.precision)
        }
    }

    static func remember(_ place: GardenPlace) {
        let pick = RecentPick(name: place.name, locality: place.locality, latitude: place.latitude,
                              longitude: place.longitude, precision: place.precision)
        var picks = recentPicks().map {
            RecentPick(name: $0.name, locality: $0.locality, latitude: $0.latitude,
                       longitude: $0.longitude, precision: $0.precision)
        }
        picks.removeAll { $0 == pick }
        picks.insert(pick, at: 0)
        if let data = try? JSONEncoder().encode(Array(picks.prefix(maxRecentPicks))) {
            UserDefaults.standard.set(data, forKey: recentPicksKey)
        }
    }

    /// Forgets this phone's recent picks (the app leaving `.ready`).
    static func purgeRecentPicks() {
        UserDefaults.standard.removeObject(forKey: recentPicksKey)
    }
}

// MARK: - Completer delegate

/// Isolated conformance: MapKit calls the delegate on the main thread.
extension GardenPlaceSearch: MKLocalSearchCompleterDelegate {
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        completerUpdated(completer.results)
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        completerFailed(error)
    }
}

// MARK: - Map item fields

/// The fields a map item gives the garden, read through `placemark` before
/// iOS 26 and through `location` and the address representations after.
private struct MapItemFields {
    var coordinate: CLLocationCoordinate2D
    var locality: String?
    var cityName: String?
    var countryCode: String?
    /// The item's name is (the start of) its street address.
    var nameIsAddress: Bool

    init(_ item: MKMapItem) {
        let name = item.name ?? ""
        if #available(iOS 26, *) {
            let representations = item.addressRepresentations
            coordinate = item.location.coordinate
            locality = representations?.cityWithContext
            cityName = representations?.cityName
            countryCode = representations?.region?.identifier
            let address = item.address?.fullAddress ?? ""
            nameIsAddress = name.isEmpty || address.hasPrefix(name)
        } else {
            let placemark = item.placemark
            coordinate = placemark.coordinate
            locality = GardenPlaceSearch.locality(district: placemark.subLocality, city: placemark.locality,
                                                  country: placemark.country, countryCode: placemark.isoCountryCode)
            cityName = placemark.locality ?? placemark.subLocality
            countryCode = placemark.isoCountryCode
            // The placemark's title is its formatted address.
            let address = placemark.title ?? ""
            nameIsAddress = name.isEmpty || address.hasPrefix(name)
        }
    }
}

// MARK: - Connection state for the views

/// Whether the phone has a network path, published for views: the place
/// picker's offline state and the consent sheets' disabled controls. The
/// service's own fail-fast check is GardenConnectivity; this is its
/// observable twin for SwiftUI. Reports online until the first answer.
@MainActor
final class GardenReachability: ObservableObject {
    static let shared = GardenReachability()

    @Published private(set) var isOnline = true

    private let monitor = NWPathMonitor()

    private init() {
        // The shared instance lives as long as the app.
        monitor.pathUpdateHandler = { path in
            let online = path.status == .satisfied
            Task { @MainActor in GardenReachability.shared.update(online) }
        }
        monitor.start(queue: DispatchQueue(label: "com.coupley.garden.reachability", qos: .utility))
    }

    private func update(_ online: Bool) {
        if isOnline != online { isOnline = online }
    }
}
