//
//  GardenContract.swift
//  Coupley
//
//  THE shared contract for Journey's garden. Read-only for every build
//  package: if a package needs a change here, the lead changes it for all.
//  Repo path: Coupley/Features/Garden/Models/GardenContract.swift
//
//  What lives here:
//    - the feature switch, cadence thresholds and text limits
//    - Firestore document ids, field names and the rules-probe document
//    - every enum and value type more than one package touches
//    - small PURE functions every package must agree on: the water state,
//      the tree's thirst curve, the watering "moment", the effect choice,
//      the one-filled-CTA resolver, the sky at a place's local time, the
//      season by latitude, the scene catalog and the place -> look mapping
//    - the protocols each package implements (service, painters, caches,
//      snapshotter, reminders) and the notification / UserDefaults keys
//
//  Concurrency: the app target builds with SWIFT_DEFAULT_ACTOR_ISOLATION =
//  MainActor. Value types and painters used off the main actor (Canvas
//  with `rendersAsynchronously: true`, Firestore transaction bodies,
//  notification handlers) are marked `nonisolated` here. Service-like
//  protocols are explicitly @MainActor. TreeGrowthStage and TreeSeason are
//  main-actor isolated in the project (no `nonisolated`; not changed by the
//  garden), so nonisolated code (scene painters, the effect painter, this
//  file) never calls their members; the tree painter (P7) keeps today's
//  main-actor isolation.
//
//  Localization: every user-facing string here is String(localized:comment:),
//  a whole sentence or one format with placeholders, never concatenated.
//  Strings written to Firestore (a preset's default title) are base-language
//  DATA and are shown through GardenPreset.displayTitle(stored:).
//
//  Calendar days (a tree's moment, a proposed start date) are stored the
//  way the start date is: JourneyCalendarDay.storedMoment(forLocalDay:)
//  (10:00 UTC of the picked Gregorian day) and read back ONLY through
//  JourneyCalendarDay.localDay(ofStored:). Nothing here (or in the rules)
//  ever checks the stored hour.
//

import Foundation
import SwiftUI
import CoreGraphics

// MARK: - Feature switch

nonisolated enum GardenFeature {
    /// Compile-time switch. `false` keeps the pre-garden Journey (old hero,
    /// direct start date, no gardenPushToken). Until Gate 3 it is on in DEBUG
    /// (every package can exercise the garden) and off in Release (a release
    /// cut from the branch stays pre-garden). At Gate 3 the lead replaces
    /// this with `static let isEnabled = true` for every configuration.
    ///
    /// Gate 3 checklist (spec L4). The garden build is submitted only once
    /// every item is done, and each deploy or publication needs the owner's
    /// approval first (spec L2):
    /// - Set `isEnabled = true` for every configuration (drop the `#if DEBUG`).
    /// - Re-add Precise Location and Coarse Location to
    ///   `Coupley/PrivacyInfo.xcprivacy` (`NSPrivacyCollectedDataTypes`,
    ///   each linked, purpose App Functionality, not tracking), beside Other
    ///   User Content. They stay out until then: a Release build before
    ///   Gate 3 stores no place (spec D6, L2 #5).
    /// - Publish the privacy page (`index.html`: the Places section, the
    ///   Couple data line, the Apple Maps bullet) with a new "Last updated"
    ///   date (spec D6, L2 #3).
    /// - Update the App Store privacy answers: Precise and Coarse Location,
    ///   Other User Content (spec D6, L2 #4).
    /// - Deploy `firestore.rules`, then the functions (spec D20, L2 #1–#2),
    ///   before the build reaches anyone.
    #if DEBUG
    static let isEnabled = true
    #else
    static let isEnabled = false
    #endif
    /// Written to users/{uid}.capabilities.garden by every garden build.
    /// A partner without it is on a legacy build (1.1, 1.2, or any 1.3 cut
    /// without the garden). Version strings are never compared.
    static let capabilityLevel = 1
}

// MARK: - How an unwatered tree looks

/// Owner decision 3 (14 Nov 2026): watering is a reward only. A watered
/// tree is greener and fuller than its plain look for a day or two
/// (`GardenTreeVisual.lushness`, with wet soil and dew); a tree left
/// unwatered converges back to its plain look and never droops, dries, dies
/// or loses growth. The water states (ready, thirsty, resting) stay as the
/// status line, copy and reminders only.
///
/// `true` brings back the spec's thirsty and resting look (C6: drooping
/// limbs and leaves, dry olive leaves, fallen leaves, blossoms closed into
/// buds, pale and cracked soil) and the tree guide's and FAQ's copy that
/// describes it. The painter keeps that code either way; the lab's species
/// gallery and the canvas previews still show it.
nonisolated enum GardenTreeLook {
    static let withersWhenThirsty = false
}

// MARK: - Cadence (server-time durations)

nonisolated enum GardenCadence {
    static let hour: TimeInterval = 3600

    /// One watering per person per 12 hours. The rules accept it after
    /// `ruleCooldown` (11 h 50 min) so a phone a few minutes off is never refused.
    static let cooldown: TimeInterval = 12 * hour
    static let ruleCooldown: TimeInterval = 710 * 60

    /// Water states, measured from the latest watering by either partner
    /// (or the tree's planting, if later): fresh < 48 h <= ready < 72 h
    /// <= thirsty < 168 h <= resting.
    static let readyAfter: TimeInterval = 48 * hour
    static let thirstyAfter: TimeInterval = 72 * hour
    static let restingAfter: TimeInterval = 168 * hour

    /// Signs that someone was just here.
    static let dewFor: TimeInterval = 6 * hour
    static let wetFor: TimeInterval = 12 * hour

    /// Two waterings by the two partners within this window are
    /// "watered together" (server times only, app and function alike).
    static let togetherWindow: TimeInterval = 24 * hour
    /// The partner watered less than this ago and I have not since: "Water back".
    static let waterBackWindow: TimeInterval = 24 * hour
    /// A watering at least this long after the previous one is "the rain returns".
    static let rainReturnsAfter: TimeInterval = 168 * hour

    static let rainbowFor: TimeInterval = 24 * hour
    static let restingCansFor: TimeInterval = 24 * hour
    static let noteInHeroFor: TimeInterval = 48 * hour
    static let homeRowFor: TimeInterval = 24 * hour
    static let lookUndoFor: TimeInterval = 24 * hour
    static let ceremonyWithin: TimeInterval = 7 * 24 * hour
    /// Swiping to another page this soon after watering shows its after-glow.
    static let afterGlowWithin: TimeInterval = 10
    static let snoozeFor: TimeInterval = 3 * 24 * hour
    /// The device clock is corrected by at most this much (estimated from
    /// this device's own acknowledged waterings).
    static let maxServerOffset: TimeInterval = 600
    /// Consent transactions give up after this long (state then "unknown"
    /// until the listener shows the truth).
    static let transactionTimeout: TimeInterval = 10
    /// "Watering… it reaches Sam when you're back online" after this long pending.
    static let pendingWateringCopyAfter: TimeInterval = 3
    /// Local reminders fire at this local hour (floating calendar trigger).
    static let reminderHour = 19
}

// MARK: - Text limits

/// Client caps. Each limit has a grapheme cap (what the user sees) and a
/// UTF-8 byte cap at or below the rules' `size()` cap, so a text the app
/// accepts is never refused by the server, whatever `size()` counts.
nonisolated struct GardenTextLimit: Equatable, Sendable {
    let graphemes: Int
    let utf8: Int

    /// Trimmed; nil when empty.
    func clean(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func accepts(_ text: String) -> Bool {
        text.count <= graphemes && text.utf8.count <= utf8
    }

    /// Cuts on grapheme boundaries until both caps hold.
    func truncate(_ text: String) -> String {
        var result = String(text.prefix(graphemes))
        while result.utf8.count > utf8, !result.isEmpty { result.removeLast() }
        return result
    }
}

nonisolated enum GardenLimits {
    static let maxTrees = 8
    /// Enforced by the rules by construction: a member can create only the
    /// place-seed ids seed_<own uid>_1 … _3 (GardenDocID.placeSeed).
    static let maxOpenSeedsPerPerson = 3
    static let wateringNote = GardenTextLimit(graphemes: 100, utf8: 400)   // rules: size() <= 400
    static let seedNote = GardenTextLimit(graphemes: 140, utf8: 560)       // rules: size() <= 560
    static let title = GardenTextLimit(graphemes: 40, utf8: 160)           // rules: size() <= 160
    static let placeName = GardenTextLimit(graphemes: 80, utf8: 320)       // rules: size() <= 320
    static let locality = GardenTextLimit(graphemes: 80, utf8: 320)        // rules: size() <= 320
    /// Waterings kept live by the listener (newest first).
    static let wateringListen = 60
    static let journalPage = 50
}

// MARK: - Firestore layout

/// Every garden document is a FLAT document in couples/{c}/timeTreeMeta,
/// next to `config` (the start date). Never a subcollection: every purge
/// since 1.2 deletes this collection page by page.
nonisolated enum GardenDocType: String, Sendable {
    case tree, proposal, water, waterer
}

nonisolated enum GardenDocID {
    /// The 1.2 start-date document. Unchanged schema, unchanged open rule.
    static let config = "config"
    /// The one proposal to plant Our tree (only while there is no start date).
    static let seedOurTree = "seed_our"
    /// The one proposed new start date.
    static let startDate = "startdate"

    static func tree(_ slot: GardenSlot) -> String { "tree_" + slot.rawValue }
    static func change(_ slot: GardenSlot) -> String { "change_" + slot.rawValue }
    /// Place trees only; Our tree can never be let go.
    static func rest(_ slot: GardenSlot) -> String {
        precondition(slot != .our, "Our tree cannot rest")
        return "rest_" + slot.rawValue
    }
    /// A place seed: `seed_<creator uid>_<n>`, n = 1…3. The rules let a member
    /// create only their own three ids, so open seeds are bounded by
    /// construction. A counter keeps the id (it names the creator, not the
    /// current proposer). The sending transaction takes the first free number.
    static let placeSeedNumbers: ClosedRange<Int> = 1...GardenLimits.maxOpenSeedsPerPerson
    static func placeSeed(creator uid: String, number: Int) -> String { "seed_\(uid)_\(number)" }
    /// The creator's first free id, or nil when all three exist (GardenError.tooManySeeds).
    static func firstFreePlaceSeed(creator uid: String, existing: Set<String>) -> String? {
        placeSeedNumbers.map { placeSeed(creator: uid, number: $0) }.first { !existing.contains($0) }
    }
    /// The creator and number of a place-seed id (rules: ^seed_[A-Za-z0-9]{1,128}_[1-3]$).
    static func placeSeedParts(_ id: String) -> (creator: String, number: Int)? {
        guard id.hasPrefix("seed_"), id != seedOurTree else { return nil }
        let body = id.dropFirst(5)
        guard let separator = body.lastIndex(of: "_") else { return nil }
        let creator = body[..<separator]
        guard let number = Int(body[body.index(after: separator)...]),
              placeSeedNumbers.contains(number),
              (1...128).contains(creator.count),
              creator.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        return (String(creator), number)
    }
    static func isPlaceSeed(_ id: String) -> Bool { placeSeedParts(id) != nil }

    /// A new watering's id: `water_` + a 20-character auto id (Firestore's
    /// own alphabet and length), made on the phone before the write (it
    /// seeds the effect choice). The ONE generator: the app and the DEBUG
    /// lab both take it, so neither can write an id that the rules
    /// (`^water_[A-Za-z0-9]{20}$`), the codec or the push function refuse.
    static func newWatering() -> String {
        let id = waterPrefix + String((0..<autoIdLength).map { _ in autoIdAlphabet.randomElement() ?? "A" })
        assert(isWater(id), "GardenDocID.newWatering() made an id the rules refuse")
        return id
    }
    /// The rules' and the push function's watering id, exactly:
    /// `^water_[A-Za-z0-9]{20}$`. The codec reads nothing else as a watering.
    static func isWater(_ id: String) -> Bool {
        guard id.hasPrefix(waterPrefix) else { return false }
        let body = id.dropFirst(waterPrefix.count)
        return body.count == autoIdLength && body.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }
    private static let waterPrefix = "water_"
    private static let autoIdLength = 20
    private static let autoIdAlphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")

    static func waterer(uid: String) -> String { "waterer_" + uid }

    static func isProposal(_ id: String) -> Bool {
        if id == seedOurTree || id == startDate || isPlaceSeed(id) { return true }
        if id.hasPrefix("change_") { return GardenSlot(rawValue: String(id.dropFirst(7))) != nil }
        if id.hasPrefix("rest_") {
            guard let slot = GardenSlot(rawValue: String(id.dropFirst(5))) else { return false }
            return slot != .our
        }
        return false
    }
    static func slot(ofTreeDocument id: String) -> GardenSlot? {
        guard id.hasPrefix("tree_") else { return nil }
        return GardenSlot(rawValue: String(id.dropFirst(5)))
    }
}

/// Field names. Writes use explicit dictionaries (never Codable) so the key
/// sets match the rules' `hasOnly` lists exactly.
nonisolated enum GardenField {
    static let docType = "docType"
    // Trees and proposals
    static let slot = "slot", key = "key", title = "title", preset = "preset"
    static let momentDay = "momentDay", place = "place", scene = "scene", species = "species"
    static let origin = "origin", plantedAt = "plantedAt", plantedBy = "plantedBy"
    static let agreedStartDay = "agreedStartDay", agreementKind = "agreementKind"
    static let agreementBy = "agreementBy", agreementAt = "agreementAt", fromProposal = "fromProposal"
    static let lookBy = "lookBy", lookAt = "lookAt", prevScene = "prevScene", prevSpecies = "prevSpecies"
    static let updatedAt = "updatedAt"
    // Proposals only
    static let kind = "kind", by = "by", at = "at", rev = "rev", note = "note"
    static let startDay = "startDay", fromStartDay = "fromStartDay"
    // Waterings (the only documents with `wateredAt`, so ordering by it
    // returns waterings alone and needs no composite index)
    static let wateredAt = "wateredAt", effect = "effect"
    // Waterers
    static let lastWateredAt = "lastWateredAt", lastWateringId = "lastWateringId"
    // The `place` map
    static let placeName = "name", placeLocality = "locality", placeLat = "lat", placeLng = "lng"
    static let placePrecision = "precision", placePOI = "poi", placeTimeZone = "tz"
    // users/{uid}
    static let capabilities = "capabilities", capabilityGarden = "garden"
    static let gardenPushToken = "gardenPushToken"
    static let notificationPreferences = "notificationPreferences", preferenceGarden = "garden"
}

/// Top-level `appConfig/garden`. Its rule (`allow get: if isSignedIn()`)
/// ships in the same rules file as the garden rules, so a permission-denied
/// get means "the garden rules are not deployed": the garden then stays
/// unavailable and writes nothing. A missing document means enabled;
/// `{enabled: false}` (written only by an admin) turns the garden off and
/// the app falls back to the pre-garden Journey.
nonisolated enum GardenAppConfig {
    static let collection = "appConfig"
    static let document = "garden"
    static let enabledField = "enabled"
}

// MARK: - Slots

nonisolated enum GardenSlot: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case our, p1, p2, p3, p4, p5, p6, p7

    var id: String { rawValue }
    var isOurTree: Bool { self == .our }

    static let placeSlots: [GardenSlot] = [.p1, .p2, .p3, .p4, .p5, .p6, .p7]
}

// MARK: - Presets (what a tree stands for)

nonisolated enum GardenPreset: String, CaseIterable, Codable, Hashable, Sendable {
    case ourTree, firstMet, firstDate, firstTrip, saidLove, firstHome, engaged, wedding, ourPlace, custom

    /// Unknown tokens (a newer app's preset) read as `.custom`.
    init(token: String) { self = GardenPreset(rawValue: token) ?? .custom }

    /// Chip order in the plant sheet. Our tree never appears as a chip.
    static let placePresets: [GardenPreset] = [
        .firstMet, .firstDate, .firstTrip, .saidLove, .firstHome, .engaged, .wedding, .ourPlace, .custom
    ]

    /// Written to Firestore as the title when the couple keeps the preset's
    /// default: base-language DATA, never localized (the push function, the
    /// partner's phone and older apps read it). Views use displayTitle(stored:).
    var storedDefaultTitle: String {
        switch self {
        case .ourTree:  return "Our tree"
        case .firstMet: return "Where we first met"
        case .firstDate: return "Our first date"
        case .firstTrip: return "Our first trip"
        case .saidLove: return "Where we said “I love you”"
        case .firstHome: return "Our first home"
        case .engaged:  return "Where we got engaged"
        case .wedding:  return "Where we got married"
        case .ourPlace: return "Our place"
        case .custom:   return ""
        }
    }

    /// The default title in the reader's language ("" for custom).
    var localizedDefaultTitle: String {
        switch self {
        case .ourTree:   return String(localized: "Our tree", comment: "Garden: the title of the couple's first tree")
        case .firstMet:  return String(localized: "Where we first met", comment: "Garden: preset title of a tree for the place the couple first met")
        case .firstDate: return String(localized: "Our first date", comment: "Garden: preset title of a tree for the couple's first date")
        case .firstTrip: return String(localized: "Our first trip", comment: "Garden: preset title of a tree for the couple's first trip")
        case .saidLove:  return String(localized: "Where we said “I love you”", comment: "Garden: preset title of a tree for where they first said I love you")
        case .firstHome: return String(localized: "Our first home", comment: "Garden: preset title of a tree for the couple's first home")
        case .engaged:   return String(localized: "Where we got engaged", comment: "Garden: preset title of a tree for the engagement place")
        case .wedding:   return String(localized: "Where we got married", comment: "Garden: preset title of a tree for the wedding place")
        case .ourPlace:  return String(localized: "Our place", comment: "Garden: preset title of a tree for a place that is theirs")
        case .custom:    return ""
        }
    }

    /// What a view shows for a stored title: the preset's localized title
    /// while the stored text is still the base default, else the couple's words.
    func displayTitle(stored: String) -> String {
        guard self != .custom, stored == storedDefaultTitle else { return stored }
        return localizedDefaultTitle
    }

    /// Chip label.
    var chipTitle: String {
        switch self {
        case .custom: return String(localized: "Something else", comment: "Garden: preset chip for a tree with the couple's own title")
        default:      return localizedDefaultTitle
        }
    }

    /// The look a preset suggests when no place category says otherwise.
    var fallbackScene: GardenSceneID {
        switch self {
        case .ourTree, .firstMet, .ourPlace, .custom: return .meadow
        case .firstDate, .saidLove, .engaged:         return .cityLights
        case .firstTrip:                              return .mountainLake
        case .firstHome:                              return .homePorch
        case .wedding:                                return .lanternTown
        }
    }

    /// A memory of this kind on the Timeline prefills the moment's day.
    var prefillMemoryKind: MemoryKind? {
        switch self {
        case .firstDate: return .firstDate
        case .firstTrip: return .firstTrip
        case .firstHome: return .movingTogether
        case .engaged:   return .proposal
        case .wedding:   return .wedding
        default:         return nil
        }
    }
}

// MARK: - Looks

nonisolated enum GardenSceneID: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case meadow, seaside, cityLights, mountainLake, lanternTown, riceTerraces, campus, homePorch

    /// Unknown tokens (a newer app's scene) draw as Meadow; never rewritten.
    init(token: String) { self = GardenSceneID(rawValue: token) ?? .meadow }
    var id: String { rawValue }
}

nonisolated enum GardenSpecies: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case oak, cherry, banyan, pine, palm

    /// Unknown tokens draw as oak.
    init(token: String) { self = GardenSpecies(rawValue: token) ?? .oak }
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .oak:    return String(localized: "Oak", comment: "Garden: tree species name")
        case .cherry: return String(localized: "Blossom", comment: "Garden: tree species name for a cherry or peach blossom tree")
        case .banyan: return String(localized: "Banyan", comment: "Garden: tree species name")
        case .pine:   return String(localized: "Pine", comment: "Garden: tree species name")
        case .palm:   return String(localized: "Palm", comment: "Garden: tree species name")
        }
    }

    /// Our tree carries letters and stars on its limbs, so it is offered
    /// only species whose limbs follow TreeCanvasLayout exactly.
    var canBeOurTree: Bool { self == .oak || self == .cherry || self == .banyan }

    static let ourTreeChoices: [GardenSpecies] = [.oak, .cherry, .banyan]
}

nonisolated struct GardenLook: Equatable, Hashable, Codable, Sendable {
    var scene: GardenSceneID
    var species: GardenSpecies

    /// Existing couples' tree, exactly as it looks today, in the Meadow.
    static let ourTreeDefault = GardenLook(scene: .meadow, species: .oak)

    /// The scene's default species (Our tree falls back to oak when the
    /// scene's default cannot carry letters).
    static func suggested(scene: GardenSceneID, forOurTree: Bool) -> GardenLook {
        let species = scene.info.defaultSpecies
        return GardenLook(scene: scene, species: forOurTree && !species.canBeOurTree ? .oak : species)
    }
}

// MARK: - Places

nonisolated enum GardenPlacePrecision: String, Codable, Hashable, Sendable {
    /// 4 decimals, about 11 m. Default for a point of interest.
    case exact
    /// 2 decimals, about 1.1 km. Default for an address or a dropped pin.
    case area

    var decimals: Int { self == .exact ? 4 : 2 }
}

/// A chosen place. Never the device's location. Stored as the `place` map
/// (name, locality, lat, lng, precision, poi, tz); the rules re-check the
/// rounding. No street or address lines are ever stored.
nonisolated struct GardenPlace: Equatable, Hashable, Codable, Sendable {
    var name: String
    /// District / city, never the street. "Hoàn Kiếm, Hà Nội".
    var locality: String?
    private(set) var latitude: Double
    private(set) var longitude: Double
    private(set) var precision: GardenPlacePrecision
    /// MKPointOfInterestCategory.rawValue, only to re-suggest a look.
    var poiCategory: String?
    /// IANA id from MKMapItem.timeZone; paints the sky at the place's hour.
    var timeZoneId: String?

    init(name: String, locality: String?, latitude: Double, longitude: Double,
         precision: GardenPlacePrecision, poiCategory: String? = nil, timeZoneId: String? = nil) {
        self.name = name
        self.locality = locality
        self.latitude = Self.rounded(latitude, to: precision)
        self.longitude = Self.rounded(longitude, to: precision)
        self.precision = precision
        self.poiCategory = poiCategory
        self.timeZoneId = timeZoneId
    }

    static func rounded(_ value: Double, to precision: GardenPlacePrecision) -> Double {
        let scale = precision == .exact ? 10_000.0 : 100.0
        return (value * scale).rounded() / scale
    }

    /// Re-rounds the stored coordinates (switching "Show the exact spot" off).
    func with(precision newPrecision: GardenPlacePrecision) -> GardenPlace {
        GardenPlace(name: name, locality: locality, latitude: latitude, longitude: longitude,
                    precision: newPrecision, poiCategory: poiCategory, timeZoneId: timeZoneId)
    }

    var timeZone: TimeZone? { timeZoneId.flatMap(TimeZone.init(identifier:)) }
}

/// What a MapKit category means for a look. P9 maps MKPointOfInterestCategory
/// constants to these groups (never by comparing raw strings).
nonisolated enum GardenPOIGroup: String, Sendable {
    case beach, water, park, food, nightOut, nature, heritage, campus, sportsFun, travel, other
}

nonisolated enum GardenLookSuggestion {
    /// Countries where a nature place suggests Rice Terraces instead of Mountain Lake.
    static let ricePaddyCountries: Set<String> = ["VN", "LA", "KH", "TH", "MM", "PH", "ID", "CN", "NP", "BT"]
    /// Countries where a heritage place suggests Lantern Town instead of Campus.
    static let lanternCountries: Set<String> = ["VN", "CN", "JP", "KR", "TW", "HK", "MO", "TH", "LA", "KH", "MM", "SG", "MY"]

    /// The scene a chosen place suggests. An address or a dropped pin has no
    /// group: First home -> Home Porch, otherwise the preset's fallback.
    static func scene(group: GardenPOIGroup?, countryCode: String?, preset: GardenPreset) -> GardenSceneID {
        let country = countryCode?.uppercased() ?? ""
        switch group {
        case .beach?, .water?:   return .seaside
        case .park?:             return .meadow
        case .food?, .nightOut?: return .cityLights
        case .nature?:           return ricePaddyCountries.contains(country) ? .riceTerraces : .mountainLake
        case .heritage?:         return lanternCountries.contains(country) ? .lanternTown : .campus
        case .campus?:           return .campus
        case .sportsFun?:        return .meadow
        case .travel?:           return preset == .firstTrip ? .mountainLake : .cityLights
        case .other?, nil:       return preset == .firstHome ? .homePorch : preset.fallbackScene
        }
    }
}

// MARK: - Kinds

nonisolated enum GardenProposalKind: String, Codable, Sendable {
    /// seed_our (Our tree's first planting) or seed_<id> (a place tree).
    case plant
    /// change_<slot>: a new name / place / moment / look for a planted tree.
    case change
    /// rest_<slot>: let a place tree go.
    case rest
    /// startdate: a new start date.
    case startDate
}

nonisolated enum GardenAgreementKind: String, Codable, Sendable {
    case plant, change, startDate
    /// Our tree recorded from an existing start date (by either partner, no
    /// consent needed for the past), or re-recorded after a legacy edit.
    case recorded
}

nonisolated enum GardenTreeOrigin: String, Codable, Sendable {
    case together, legacy
}

// MARK: - Models (decoded; read-only snapshots)

nonisolated struct GardenTree: Identifiable, Equatable, Sendable {
    let slot: GardenSlot
    /// Identity across slot reuse (ceremony and seen flags, push keys).
    let key: String
    var title: String
    var preset: GardenPreset
    /// Stored calendar-day instant; read with JourneyCalendarDay.localDay(ofStored:).
    var momentDay: Date?
    var place: GardenPlace?
    var look: GardenLook
    var origin: GardenTreeOrigin
    var plantedAt: Date?
    /// [proposer, planter]; empty for a recorded (legacy) Our tree.
    var plantedBy: [String]
    /// Our tree only: the start date both agreed to (or recorded).
    var agreedStartDay: Date?
    var agreementKind: GardenAgreementKind
    var agreementBy: [String]
    var agreementAt: Date?
    var fromProposal: String?
    var lookBy: String?
    var lookAt: Date?
    var previousLook: GardenLook?
    var updatedAt: Date?
    var hasPendingWrites: Bool

    var id: String { slot.rawValue }
    var isOurTree: Bool { slot == .our }
    /// The title in the reader's language (a kept preset default is localized).
    var displayTitle: String { preset.displayTitle(stored: title) }

    /// What Our tree is before its record exists (an existing couple's
    /// first launch, offline): drawn from the start date alone.
    static func unrecordedOurTree(startDate: Date) -> GardenTree {
        GardenTree(slot: .our, key: "unrecorded", title: GardenPreset.ourTree.storedDefaultTitle,
                   preset: .ourTree, momentDay: nil, place: nil, look: .ourTreeDefault,
                   origin: .legacy, plantedAt: nil, plantedBy: [], agreedStartDay: startDate,
                   agreementKind: .recorded, agreementBy: [], agreementAt: nil, fromProposal: nil,
                   lookBy: nil, lookAt: nil, previousLook: nil, updatedAt: nil, hasPendingWrites: false)
    }

    /// The stored instant this tree grows from: Our tree from the start
    /// date (config), a place tree from the day it was planted. A place
    /// tree's moment's day is remembered (postcard, title line), never grown
    /// from (the user's answer, 14 Nov 2026).
    func growthStart(ourStartDate: Date?) -> Date? {
        isOurTree ? ourStartDate : plantedAt
    }
}

/// Which version of a proposal the user was shown: its `rev` and the server
/// time of that version (`at`, whole milliseconds). A proposal taken back and
/// re-sent under the same fixed id (seed_our, startdate, change_<slot>,
/// rest_<slot>, a reused seed_<uid>_<n>) restarts at rev 1 but gets a new
/// `at`, so a consent transaction that compares BOTH never carries out
/// content the user did not see (no ABA). No rules change is involved.
nonisolated struct GardenProposalVersion: Equatable, Hashable, Sendable {
    let rev: Int
    let atMillis: Int64

    /// From a Firestore Timestamp's parts (the codec passes `ts.seconds` and
    /// `ts.nanoseconds`), so the snapshot shown and the snapshot read inside
    /// the transaction produce the same integer.
    static func millis(seconds: Int64, nanoseconds: Int32) -> Int64 {
        seconds * 1000 + Int64(nanoseconds / 1_000_000)
    }
}

nonisolated struct GardenProposal: Identifiable, Equatable, Sendable {
    /// The document id (seed_our, seed_<uid>_<n>, change_<slot>, rest_<slot>, startdate).
    let id: String
    var kind: GardenProposalKind
    /// "our", "new" (a place seed) or "p1"…"p7".
    var slot: String
    var key: String
    /// The current proposer: the creator, or whoever answered with their own version.
    var by: String
    /// Server time of the last create/edit/counter (estimated while pending).
    var at: Date?
    /// `at` in whole milliseconds, from the raw Timestamp (GardenProposalVersion.millis).
    var atMillis: Int64?
    /// 1 on create, +1 on every edit or counter.
    var rev: Int
    var note: String?
    var startDay: Date?
    var fromStartDay: Date?
    var title: String?
    var preset: GardenPreset?
    var momentDay: Date?
    var place: GardenPlace?
    var look: GardenLook?
    var hasPendingWrites: Bool

    var targetSlot: GardenSlot? { GardenSlot(rawValue: slot) }

    /// What a consent action carries and the transaction compares. nil while
    /// this proposal has pending writes: its actions are disabled until then.
    var version: GardenProposalVersion? {
        guard !hasPendingWrites, let atMillis else { return nil }
        return GardenProposalVersion(rev: rev, atMillis: atMillis)
    }

    /// The proposed title in the reader's language.
    var displayTitle: String? { title.map { (preset ?? .custom).displayTitle(stored: $0) } }
}

nonisolated struct GardenWatering: Identifiable, Equatable, Sendable {
    let id: String
    var by: String
    /// Server time (estimated while pending).
    var wateredAt: Date?
    var note: String?
    /// The animation the waterer saw; the partner replays exactly this.
    var effect: GardenEffect
    var hasPendingWrites: Bool
}

nonisolated struct GardenWaterer: Equatable, Sendable {
    let uid: String
    var lastWateredAt: Date?
    var lastWateringId: String
}

/// The start date as the garden sees it (its own listener on `config`).
nonisolated struct GardenAnchorState: Equatable, Sendable {
    var exists: Bool
    /// The stored instant (10:00 UTC for new values, any instant from 1.2).
    var startDate: Date?
    /// False while only an empty cache has answered (never "no start date" then).
    var isResolved: Bool

    static let unresolved = GardenAnchorState(exists: false, startDate: nil, isResolved: false)
}

nonisolated struct GardenDocsSnapshot: Equatable, Sendable {
    var trees: [GardenTree]
    var proposals: [GardenProposal]
    var waterers: [GardenWaterer]
    var isFromCache: Bool

    static let empty = GardenDocsSnapshot(trees: [], proposals: [], waterers: [], isFromCache: true)
}

nonisolated struct GardenWateringsSnapshot: Equatable, Sendable {
    /// Newest first, at most GardenLimits.wateringListen.
    var waterings: [GardenWatering]
    var isFromCache: Bool

    static let empty = GardenWateringsSnapshot(waterings: [], isFromCache: true)
}

nonisolated struct GardenPartnerInfo: Equatable, Sendable {
    /// nil until the partner's user document answers.
    var canGarden: Bool?
    var timeZone: TimeZone?
    var displayName: String?

    static let unknown = GardenPartnerInfo(canGarden: nil, timeZone: nil, displayName: nil)
}

/// What the plant sheet edits. Days are the LOCAL days the user picked;
/// the service stores them with JourneyCalendarDay.storedMoment(forLocalDay:).
nonisolated struct GardenDraft: Equatable, Sendable {
    enum Mode: Equatable, Sendable {
        case newPlaceTree
        case ourTreeFirstPlanting
        /// My own seed, the version I was shown.
        case editSeed(id: String, seen: GardenProposalVersion)
        /// The partner's seed or change request, answered with my version.
        case counter(id: String, seen: GardenProposalVersion)
        case changeTree(GardenSlot)
        case editChange(id: String, seen: GardenProposalVersion)
    }

    var mode: Mode
    var preset: GardenPreset
    /// The Name field. Empty, or still the preset's default (in either
    /// language), means "the preset's default": see `storedTitle`.
    var title: String
    /// Our tree's first planting only.
    var startDay: Date?
    /// Place trees only; nil = "We're not sure of the day".
    var momentDay: Date?
    var place: GardenPlace?
    var look: GardenLook
    var note: String?

    var isOurTree: Bool {
        switch mode {
        case .ourTreeFirstPlanting: return true
        case .changeTree(let slot): return slot == .our
        default:                    return preset == .ourTree
        }
    }

    /// What is written to Firestore: the couple's own words, or the preset's
    /// base-language default while the field still shows the default.
    var storedTitle: String {
        let typed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if preset != .custom,
           typed.isEmpty || typed == preset.localizedDefaultTitle || typed == preset.storedDefaultTitle {
            return preset.storedDefaultTitle
        }
        return typed
    }
}

// MARK: - Availability and errors

nonisolated enum GardenUnavailableReason: Equatable, Sendable {
    /// appConfig/garden answered permission-denied: rules not deployed.
    case rulesMissing
    /// A garden listener failed (retried on foreground and after 3, 6, 9 s).
    case listenerFailed
    /// First launch offline, never verified on this device.
    case neverOnline
}

nonisolated enum GardenAvailability: Equatable, Sendable {
    case unpaired
    case loading
    case ready
    case unavailable(GardenUnavailableReason)
    /// appConfig/garden {enabled: false}: show the pre-garden Journey.
    case disabledRemotely

    var allowsWrites: Bool { self == .ready }
}

nonisolated enum GardenProbeResult: Equatable, Sendable {
    case enabled, disabledRemotely, rulesMissing, offline
}

nonisolated enum GardenError: Error, Equatable, Sendable {
    case offline
    /// The transaction did not answer within GardenCadence.transactionTimeout.
    case timedOut
    /// The proposal or tree changed since the user looked (rev mismatch).
    case changed
    /// The proposal is gone (taken back, let go).
    case gone
    case alreadyPlanted
    /// Edit attempted on a seed the partner has since answered with their version.
    case notYours
    /// The partner created the same fixed-id proposal first (Our tree, start date, change).
    case partnerProposedFirst
    case full
    /// All three of my place-seed ids (seed_<me>_1…3) are open.
    case tooManySeeds
    /// The start date changed (a legacy app) since the suggestion was made.
    case startDateChanged
    /// A start date appeared (a legacy app planted) since the seed was sent.
    case startDateSetElsewhere
    case cooldown(until: Date)
    /// Permission denied: rules not deployed, or the couple is disconnected.
    case denied
    case invalid
    case other

    /// The exact copy for the error strip or a sheet's inline error.
    /// @MainActor: FutureLetterClock (the app's time formatter) is main-actor isolated.
    @MainActor
    func message(partnerName: String, now: Date) -> String {
        switch self {
        case .offline:
            return String(localized: "You're offline. Planting needs a connection so you both see the same tree.",
                          comment: "Garden error: a seed, an answer or a request needs a connection")
        case .timedOut:
            return String(localized: "That didn't reach \(partnerName) yet. If it went through, you'll see it here in a moment.",
                          comment: "Garden error: the request timed out; the placeholder is the partner's name")
        case .changed:
            return String(localized: "\(partnerName) just changed this. Take another look.",
                          comment: "Garden error: the partner changed the seed or request while you were looking")
        case .gone:
            return String(localized: "\(partnerName) took this back.",
                          comment: "Garden error: the partner withdrew the seed or request")
        case .alreadyPlanted:
            return String(localized: "Too late, \(partnerName) planted it just now 🌳",
                          comment: "Garden: you tried to take a seed back the moment the partner planted it")
        case .notYours:
            return String(localized: "\(partnerName) answered with their own version. Take a look.",
                          comment: "Garden error: you edited a seed the partner has since answered with their own version")
        case .partnerProposedFirst:
            return String(localized: "\(partnerName) sent one at the same moment. Here it is.",
                          comment: "Garden: both partners sent the same kind of proposal at once")
        case .full:
            return String(localized: "Your garden has 8 trees. Let one rest to plant another.",
                          comment: "Garden error: the garden is full")
        case .tooManySeeds:
            return String(localized: "You have 3 seeds waiting for \(partnerName). Take one back to send another.",
                          comment: "Garden error: the limit of open seeds per person was reached")
        case .startDateChanged:
            return String(localized: "The start date changed since \(partnerName) suggested this.",
                          comment: "Garden error: a start-date suggestion became void")
        case .startDateSetElsewhere:
            return String(localized: "Your start date was just set in an older version of Coupley. Your tree is planted.",
                          comment: "Garden: the partner's older app set the start date while a seed waited")
        case .cooldown(let until):
            let when = FutureLetterClock.moment(until, now: now)
            return String(localized: "You already watered recently. You can water again \(when).",
                          comment: "Garden error: one watering per person every 12 hours; the placeholder is like 'today at 9:14 PM'")
        case .denied:
            return String(localized: "The garden isn't available right now. Your trees are fine.",
                          comment: "Garden error: permission denied (rules not deployed or the couple disconnected)")
        case .invalid, .other:
            return String(localized: "Couldn't save that. Try again in a moment.",
                          comment: "Garden error: any other failure")
        }
    }
}

// MARK: - Watering timeline (pure)

nonisolated enum GardenWaterState: String, Equatable, Sendable {
    case neverWatered, fresh, ready, thirsty, resting

    /// The GARDEN's state: hours since the latest watering by either partner
    /// (L) alone. It drives the status line, the water action and its CTA,
    /// GardenPrimaryAction (the masthead +'s fill), Home, VoiceOver's water
    /// value and the reminders, so it never changes with the selected page.
    static func garden(lastWateredAt last: Date?, now: Date) -> GardenWaterState {
        state(lastWateredAt: last, plantedAt: nil, now: now)
    }

    /// A TREE's state, for its look only: `plantedAt` restarts the clock for
    /// a tree planted after the latest watering.
    static func state(lastWateredAt last: Date?, plantedAt: Date?, now: Date) -> GardenWaterState {
        guard let last else { return .neverWatered }
        let since = now.timeIntervalSince(max(last, plantedAt ?? .distantPast))
        switch max(0, since) {
        case ..<GardenCadence.readyAfter:   return .fresh
        case ..<GardenCadence.thirstyAfter: return .ready
        case ..<GardenCadence.restingAfter: return .thirsty
        default:                            return .resting
        }
    }

    var spoken: String {
        switch self {
        case .neverWatered: return String(localized: "Not watered yet", comment: "Garden water state, said by VoiceOver")
        case .fresh:        return String(localized: "Watered", comment: "Garden water state, said by VoiceOver")
        case .ready:        return String(localized: "Ready for water", comment: "Garden water state, said by VoiceOver")
        case .thirsty:      return String(localized: "A little thirsty", comment: "Garden water state, said by VoiceOver")
        case .resting:      return String(localized: "Resting", comment: "Garden water state, said by VoiceOver")
        }
    }
}

/// Who watered last, from the waterings listener (newest first). Pending
/// waterings count as mine "now" for display only, never for the server.
nonisolated struct GardenWaterTimeline: Equatable, Sendable {
    var latest: GardenWatering?
    var mineLastAt: Date?
    var partnerLastAt: Date?
    var partnerLast: GardenWatering?
    var neverWatered: Bool

    static func from(waterings: [GardenWatering], me: String) -> GardenWaterTimeline {
        let sorted = waterings.sorted { ($0.wateredAt ?? .distantFuture) > ($1.wateredAt ?? .distantFuture) }
        let mine = sorted.first { $0.by == me }
        let partner = sorted.first { $0.by != me }
        return GardenWaterTimeline(latest: sorted.first, mineLastAt: mine?.wateredAt,
                                   partnerLastAt: partner?.wateredAt, partnerLast: partner,
                                   neverWatered: sorted.isEmpty)
    }

    /// The pair at the top of the log is "watered together".
    var isTogether: Bool {
        guard let mine = mineLastAt, let theirs = partnerLastAt else { return false }
        return abs(mine.timeIntervalSince(theirs)) <= GardenCadence.togetherWindow
    }
}

/// Values that drive ONE tree's look (P7) from hours since max(L, plantedAt).
/// A tree never dies. Watering only adds to its plain look (`.healthy`):
/// lushness, wet soil and dew, which fade back to plain on their own; it
/// never droops or dries while `GardenTreeLook.withersWhenThirsty` is off
/// (owner decision 3). Never used for controls or copy.
nonisolated struct GardenTreeVisual: Equatable, Sendable {
    /// Only with `GardenTreeLook.withersWhenThirsty`, else always 0:
    /// 0 fresh/ready, rises 0 -> 0.5 over 72-96 h, 0.5 -> 1 over 168-192 h.
    var thirst: Double
    /// 1 at watering, 0 after 12 h.
    var wetness: Double
    /// 1 at watering, 0 after 6 h.
    var dew: Double
    /// Only with `GardenTreeLook.withersWhenThirsty`, else always 0: pale
    /// soil while "ready", 0 before 48 h, 1 at 72 h.
    var soilDryness: Double
    /// The reward for watering: 1 for 24 h after a watering, easing to 0 by
    /// 48 h. A freshly watered tree is greener and fuller than its plain
    /// look. 0 for a tree nobody has watered since it was planted.
    var lushness: Double = 0

    static let healthy = GardenTreeVisual(thirst: 0, wetness: 0, dew: 0, soilDryness: 0)

    /// A tree's look: its clock restarts at its planting if that is later
    /// than the garden's latest watering, so a new tree shows the wet soil
    /// and dew of its planting, but never the watering's lushness (it has
    /// not been watered yet). healthy when never watered.
    static func forTree(lastWateredAt last: Date?, plantedAt: Date?, now: Date) -> GardenTreeVisual {
        guard let last else { return .healthy }
        let since = now.timeIntervalSince(max(last, plantedAt ?? .distantPast))
        var visual = at(hoursSinceWater: since / GardenCadence.hour)
        if let plantedAt, last < plantedAt { visual.lushness = 0 }
        return visual
    }

    /// The look `hours` after a watering. `withers` draws the spec's
    /// thirsty and resting look (C6); the app passes the owner's switch,
    /// and only previews and checks ask for it explicitly.
    static func at(hoursSinceWater hours: Double?,
                   withers: Bool = GardenTreeLook.withersWhenThirsty) -> GardenTreeVisual {
        guard let h = hours.map({ max(0, $0) }) else { return .healthy }
        let thirst: Double
        switch h {
        case ..<72:  thirst = 0
        case ..<96:  thirst = 0.5 * (h - 72) / 24
        case ..<168: thirst = 0.5
        case ..<192: thirst = 0.5 + 0.5 * (h - 168) / 24
        default:     thirst = 1
        }
        let soilDryness = h < 48 ? 0 : min(1, (h - 48) / 24)
        return GardenTreeVisual(thirst: withers ? thirst : 0,
                                wetness: max(0, 1 - h / 12),
                                dew: max(0, 1 - h / 6),
                                soilDryness: withers ? soilDryness : 0,
                                lushness: h < 24 ? 1 : max(0, 1 - (h - 24) / 24))
    }
}

/// What a watering means, from server times only (the push function uses
/// the same rule in functions/garden.js).
nonisolated enum GardenMoment: String, Codable, Sendable {
    case first, together, returned, plain

    /// `others` are every watering confirmed BEFORE this one (any order).
    static func of(at: Date, by: String, others: [GardenWatering]) -> GardenMoment {
        let before = others.compactMap { w -> (String, Date)? in
            guard let t = w.wateredAt, t < at else { return nil }
            return (w.by, t)
        }
        guard let previous = before.map(\.1).max() else { return .first }
        let partnerLast = before.filter { $0.0 != by }.map(\.1).max()
        if let partnerLast, at.timeIntervalSince(partnerLast) <= GardenCadence.togetherWindow { return .together }
        if at.timeIntervalSince(previous) >= GardenCadence.rainReturnsAfter { return .returned }
        return .plain
    }
}

// MARK: - Watering effects

nonisolated enum GardenEffect: String, CaseIterable, Codable, Hashable, Sendable {
    case can, rainCloud, morningDew, moonlitDrizzle, together, rainReturns

    /// Unknown tokens (a newer app) replay as the can.
    init(token: String) { self = GardenEffect(rawValue: token) ?? .can }

    var duration: TimeInterval {
        switch self {
        case .can:            return 2.6
        case .rainCloud:      return 3.2
        case .morningDew:     return 2.4
        case .moonlitDrizzle: return 2.8
        case .together:       return 3.4
        case .rainReturns:    return 3.2
        }
    }

    /// When the tree starts reviving: its lushness rises (and any droop,
    /// with `GardenTreeLook.withersWhenThirsty`, eases to 0) over 1.2 s.
    var reviveOffset: TimeInterval {
        switch self {
        case .can:            return 0.8
        case .rainCloud:      return 1.0
        case .morningDew:     return 0.6
        case .moonlitDrizzle: return 0.8
        case .together:       return 1.0
        case .rainReturns:    return 1.0
        }
    }

    static let reducedMotionDuration: TimeInterval = 0.3
    static let replayTapToSkip = true

    /// Chosen on the waterer's phone at the tap and STORED on the watering,
    /// so the partner replays exactly this. `localHour` is the hour at the
    /// selected tree's place (its time zone), else the phone's.
    static func choose(wateringId: String, moment: GardenMoment, localHour: Int,
                       previous: GardenEffect?) -> GardenEffect {
        switch moment {
        case .together: return .together
        case .returned: return .rainReturns
        case .first:    return .can
        case .plain:    break
        }
        var pool: [GardenEffect] = [.can, .rainCloud]
        if (5..<10).contains(localHour) { pool.append(.morningDew) }
        if localHour >= 20 || localHour < 5 { pool = [.can, .moonlitDrizzle] }
        var index = Int(JourneyTreeOrnament.stableSeed(wateringId) % UInt64(pool.count))
        if pool[index] == previous, pool.count > 1 { index = (index + 1) % pool.count }
        return pool[index]
    }
}

/// One effect on screen: the waterer's own tap, or a replay of the
/// partner's stored effect.
nonisolated struct GardenEffectPlayback: Identifiable, Equatable, Sendable {
    /// The watering id.
    let id: String
    let effect: GardenEffect
    /// Reference-date seconds (TimelineView dates) when it started.
    let startTime: TimeInterval
    let seed: UInt64
    let isReplay: Bool
    /// The garden's first watering ever: a golden first drop before the effect.
    let isFirstEver: Bool
    let byPartner: Bool
    let treeCount: Int

    init(wateringId: String, effect: GardenEffect, startTime: TimeInterval, isReplay: Bool,
         isFirstEver: Bool, byPartner: Bool, treeCount: Int) {
        self.id = wateringId
        self.effect = effect
        self.startTime = startTime
        self.seed = JourneyTreeOrnament.stableSeed(wateringId)
        self.isReplay = isReplay
        self.isFirstEver = isFirstEver
        self.byPartner = byPartner
        self.treeCount = treeCount
    }

    var totalDuration: TimeInterval { effect.duration + (isFirstEver ? 0.4 : 0) }
}

// MARK: - Hero actions and the one filled CTA

nonisolated enum GardenWaterAction: Equatable, Sendable {
    /// No Our tree, loading, unavailable: no water control at all.
    case none
    case firstWater
    case waterBack
    /// Ready, thirsty or resting.
    case waterDue
    /// Fresh and my cooldown is over: a quiet outlined control.
    case waterOptional
    /// My cooldown: no control, the status says when I watered.
    case locked(until: Date)

    /// Watering is today's job: the hero's CTA is the screen's one fill.
    var isTheJob: Bool {
        switch self {
        case .firstWater, .waterBack, .waterDue: return true
        default:                                 return false
        }
    }

    /// `state` is the GARDEN's state (GardenWaterState.garden), never a page's.
    static func resolve(timeline: GardenWaterTimeline, state: GardenWaterState, canWrite: Bool,
                        hasOurTree: Bool, now: Date) -> GardenWaterAction {
        guard canWrite, hasOurTree else { return .none }
        if let mine = timeline.mineLastAt, now.timeIntervalSince(mine) < GardenCadence.cooldown {
            return .locked(until: mine.addingTimeInterval(GardenCadence.cooldown))
        }
        if timeline.neverWatered { return .firstWater }
        if let theirs = timeline.partnerLastAt,
           now.timeIntervalSince(theirs) < GardenCadence.waterBackWindow,
           (timeline.mineLastAt ?? .distantPast) < theirs {
            return .waterBack
        }
        switch state {
        case .ready, .thirsty, .resting: return .waterDue
        case .fresh, .neverWatered:      return .waterOptional
        }
    }
}

nonisolated enum GardenOurSeedState: Equatable, Sendable {
    case none, mineWaiting, partnersWaiting
}

/// Exactly one control on Journey is filled. Pure, so it can be checked
/// for every state.
nonisolated enum GardenPrimaryAction: Equatable, Sendable {
    /// No start date, nothing proposed: hero "Plant a seed".
    case heroPlantSeed
    /// No start date, the partner's seed waits: hero "See Sam's seed".
    case heroSeePartnerSeed
    /// Watering is the job: the hero's water CTA.
    case heroWater(GardenWaterAction)
    /// Everything else: the masthead + keeps today's fill.
    case mastheadPlus

    var isMastheadPlusFilled: Bool { self == .mastheadPlus }

    /// `hasStartDate == nil` while unresolved (the + is hidden while
    /// Journey's first load runs; this returns .mastheadPlus then).
    /// `water` must come from the GARDEN's state, so swiping pages never
    /// moves the fill.
    static func resolve(hasStartDate: Bool?, ourSeed: GardenOurSeedState,
                        water: GardenWaterAction, availability: GardenAvailability) -> GardenPrimaryAction {
        // Pre-garden Journey, unpaired, loading and every unavailable state:
        // the hero shows no CTA at all and the + keeps the fill.
        guard availability.allowsWrites else { return .mastheadPlus }
        switch hasStartDate {
        case .some(false):
            switch ourSeed {
            case .none:            return .heroPlantSeed
            case .partnersWaiting: return .heroSeePartnerSeed
            case .mineWaiting:     return .mastheadPlus
            }
        case .some(true):
            return water.isTheJob ? .heroWater(water) : .mastheadPlus
        case .none:
            return .mastheadPlus
        }
    }

    /// Whether the planting hero (no start date) shows its button. In
    /// loading and unavailable states it shows text only: a DISABLED hero
    /// BrandCTA still paints a 35% accent fill, which would be a second
    /// accent beside the filled masthead +.
    static func emptyHeroShowsButton(availability: GardenAvailability) -> Bool {
        availability.allowsWrites
    }
}

/// Whether a scene page runs its clock (P10's GardenScenePage). Selection,
/// not scroll visibility, picks the page: a peeking neighbour mid-swipe
/// draws one frozen frame.
nonisolated struct GardenMotionGate: Equatable, Sendable {
    var isSelectedPage: Bool
    /// The hero container is in Journey's viewport (onScrollVisibilityChange
    /// on the hero, outside the horizontal pager).
    var heroVisible: Bool
    /// Journey is the shown tab (the hero's onAppear / onDisappear).
    var tabShown: Bool
    /// Something covers Journey (GardenHero.isCovered): one of its sheets,
    /// ContentView's letters sheet, the crown or the planting ceremony.
    /// Presenting any of them fires no onDisappear, so without this the
    /// hero animates under every sheet.
    var journeySheetPresented: Bool
    var sceneActive: Bool
    var lowPower: Bool
    var reduceMotion: Bool

    var isOnScreen: Bool { isSelectedPage && heroVisible && tabShown && !journeySheetPresented && sceneActive }
    /// Sky life, ambience and the tree's sway.
    var isLive: Bool { isOnScreen && !lowPower && !reduceMotion }
    /// A watering effect or a replay (short, user-started): plays in Low
    /// Power Mode, never under Reduce Motion.
    var allowsEffect: Bool { isOnScreen && !reduceMotion }
}

// MARK: - Sky (the place's local time)

nonisolated struct GardenRGB: Equatable, Hashable, Sendable {
    let r: Double, g: Double, b: Double

    init(_ hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }

    init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }

    var color: Color { Color(red: r, green: g, blue: b) }

    func mixed(with other: GardenRGB, _ t: Double) -> GardenRGB {
        let t = min(1, max(0, t))
        return GardenRGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }
}

nonisolated enum GardenTimeOfDay: String, Sendable {
    case earlyMorning, morning, afternoon, evening, night

    /// A whole phrase for GardenSceneEnvironment.spokenSetting.
    var spokenPhrase: String {
        switch self {
        case .earlyMorning: return String(localized: "in the early morning", comment: "VoiceOver: when a garden scene is, part of 'in a meadow, in the early morning, in spring'")
        case .morning:      return String(localized: "in the morning", comment: "VoiceOver: when a garden scene is")
        case .afternoon:    return String(localized: "in the afternoon", comment: "VoiceOver: when a garden scene is")
        case .evening:      return String(localized: "in the evening", comment: "VoiceOver: when a garden scene is")
        case .night:        return String(localized: "at night", comment: "VoiceOver: when a garden scene is")
        }
    }
}

nonisolated struct GardenSkyState: Equatable, Sendable {
    var top: GardenRGB
    var horizon: GardenRGB
    /// 0 day … 1 night. Opacity of the night landscape over the day one.
    var darkness: Double
    var warmTint: GardenRGB
    var warmTintAlpha: Double
    /// Fractions of the band; nil when below the horizon.
    var sun: CGPoint?
    var moon: CGPoint?
    var starsAlpha: Double
    var timeOfDay: GardenTimeOfDay
    var localHour: Int
    /// 0…59: the minute past `localHour` at the place (half- and
    /// quarter-hour zones included). Campus's clock hands read it.
    var localMinute: Int

    /// The tree's bark and starlight follow the scene's sky, not the app's
    /// colour scheme: a night sky in Light mode needs the lit bark.
    var treeBackdrop: TreeBackdrop { darkness > 0.5 ? .dark : .light }
}

nonisolated enum GardenSky {
    private struct Keyframe {
        let minute: Double
        let top: UInt32
        let horizon: UInt32
        let darkness: Double
        let tint: UInt32
        let tintAlpha: Double
    }

    /// Minutes since local midnight. Interpolated linearly between frames.
    private static let frames: [Keyframe] = [
        Keyframe(minute: 0,    top: 0x0B1430, horizon: 0x1F3157, darkness: 1.0,  tint: 0x000000, tintAlpha: 0),
        Keyframe(minute: 300,  top: 0x0B1430, horizon: 0x1F3157, darkness: 1.0,  tint: 0x000000, tintAlpha: 0),
        Keyframe(minute: 360,  top: 0x3B4E86, horizon: 0xF6B38A, darkness: 0.5,  tint: 0xFF9E6B, tintAlpha: 0.20),
        Keyframe(minute: 450,  top: 0x6FB7EA, horizon: 0xD8EEF8, darkness: 0.0,  tint: 0x000000, tintAlpha: 0),
        Keyframe(minute: 990,  top: 0x6FB7EA, horizon: 0xD8EEF8, darkness: 0.0,  tint: 0x000000, tintAlpha: 0),
        Keyframe(minute: 1050, top: 0x7AA6D6, horizon: 0xFFD08A, darkness: 0.15, tint: 0xFF9E5E, tintAlpha: 0.25),
        Keyframe(minute: 1140, top: 0x2E3A6E, horizon: 0xF08A6B, darkness: 0.6,  tint: 0xE86F7D, tintAlpha: 0.30),
        Keyframe(minute: 1230, top: 0x0B1430, horizon: 0x1F3157, darkness: 1.0,  tint: 0x000000, tintAlpha: 0),
        Keyframe(minute: 1440, top: 0x0B1430, horizon: 0x1F3157, darkness: 1.0,  tint: 0x000000, tintAlpha: 0)
    ]

    static func localMinutes(at date: Date, in timeZone: TimeZone) -> Double {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
    }

    static func state(at date: Date, in timeZone: TimeZone) -> GardenSkyState {
        let minute = localMinutes(at: date, in: timeZone)
        let upper = frames.firstIndex { $0.minute > minute } ?? frames.count - 1
        let a = frames[max(0, upper - 1)], b = frames[upper]
        let t = b.minute > a.minute ? (minute - a.minute) / (b.minute - a.minute) : 0
        let darkness = a.darkness + (b.darkness - a.darkness) * t
        let tintAlpha = a.tintAlpha + (b.tintAlpha - a.tintAlpha) * t
        let tint = a.tintAlpha >= b.tintAlpha ? GardenRGB(a.tint) : GardenRGB(b.tint)

        // The sun crosses an arc from 06:00 to 19:00, the moon from 19:00 to 06:00.
        func arc(_ progress: Double) -> CGPoint {
            CGPoint(x: 0.12 + 0.76 * progress, y: 0.55 - 0.43 * sin(progress * .pi))
        }
        let sun: CGPoint? = (360...1140).contains(minute) ? arc((minute - 360) / 780) : nil
        let nightMinute = minute >= 1140 ? minute - 1140 : minute + 300
        let moon: CGPoint? = sun == nil ? arc(min(1, nightMinute / 660)) : nil

        let hour = Int(minute / 60)
        let timeOfDay: GardenTimeOfDay
        switch hour {
        case 5..<7:   timeOfDay = .earlyMorning
        case 7..<12:  timeOfDay = .morning
        case 12..<17: timeOfDay = .afternoon
        case 17..<21: timeOfDay = .evening
        default:      timeOfDay = .night
        }
        return GardenSkyState(top: GardenRGB(a.top).mixed(with: GardenRGB(b.top), t),
                              horizon: GardenRGB(a.horizon).mixed(with: GardenRGB(b.horizon), t),
                              darkness: darkness, warmTint: tint, warmTintAlpha: tintAlpha,
                              sun: sun, moon: moon, starsAlpha: max(0, (darkness - 0.4) / 0.6),
                              timeOfDay: timeOfDay, localHour: hour, localMinute: Int(minute) % 60)
    }
}

// MARK: - Seasons (hemisphere and climate)

nonisolated enum GardenSceneSeason: String, CaseIterable, Sendable {
    case spring, summer, autumn
    /// Temperate winter: snow on the ground and roofs.
    case winter
    /// A tree without a place in Dec–Feb: frosty canopy as today, NO snow.
    case mildWinter
    /// Tropical Dec–Feb (|latitude| < 23.5°, all of Vietnam): green, dry ground, never snow.
    case drySeason

    /// What the tree canvas paints its canopy with.
    var treeSeason: TreeSeason {
        switch self {
        case .spring:             return .spring
        case .summer, .drySeason: return .summer
        case .autumn:             return .autumn
        case .winter, .mildWinter: return .winter
        }
    }

    var hasSnow: Bool { self == .winter }

    /// A whole phrase for GardenSceneEnvironment.spokenSetting.
    var spokenPhrase: String {
        switch self {
        case .spring:             return String(localized: "in spring", comment: "VoiceOver: the season of a garden scene")
        case .summer:             return String(localized: "in summer", comment: "VoiceOver: the season of a garden scene")
        case .autumn:             return String(localized: "in autumn", comment: "VoiceOver: the season of a garden scene")
        case .winter, .mildWinter: return String(localized: "in winter", comment: "VoiceOver: the season of a garden scene")
        case .drySeason:          return String(localized: "in the dry season", comment: "VoiceOver: the tropical dry season of a garden scene")
        }
    }
}

nonisolated enum GardenSeasons {
    /// A place's season from its latitude and the month at the place; a tree
    /// without a place uses the phone's month exactly as TreeSeason.current()
    /// does today, but its winter never snows.
    static func season(at date: Date, latitude: Double?, timeZone: TimeZone) -> GardenSceneSeason {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var month = calendar.component(.month, from: date)
        guard let latitude else {
            switch month {
            case 3...5:  return .spring
            case 6...8:  return .summer
            case 9...11: return .autumn
            default:     return .mildWinter
            }
        }
        if latitude <= -23.5 { month = (month + 5) % 12 + 1 }   // southern temperate: six months on
        let tropical = abs(latitude) < 23.5
        switch month {
        case 3...5:  return .spring
        case 6...8:  return .summer
        case 9...11: return .autumn
        default:     return tropical ? .drySeason : .winter
        }
    }

    /// Seaside snows only above this latitude (C4); below it a temperate
    /// winter by the sea is a mild one (grey sea, no gulls, no snow).
    static let seasideSnowLatitude = 45.0

    /// The season a scene is drawn in: `season(at:latitude:timeZone:)` with the
    /// Seaside exception. Every scene page goes through this (via
    /// GardenSceneEnvironment.make), so the backdrop key, the ambient passes
    /// and the tree (`TreeCanvasStyle.snows`) always agree.
    static func season(at date: Date, latitude: Double?, timeZone: TimeZone, scene: GardenSceneID) -> GardenSceneSeason {
        let season = season(at: date, latitude: latitude, timeZone: timeZone)
        if scene == .seaside, season == .winter, abs(latitude ?? 0) < seasideSnowLatitude { return .mildWinter }
        return season
    }
}

// MARK: - Scene catalog

nonisolated struct GardenSceneLayout: Equatable, Sendable {
    /// Where the trunk base sits, as fractions of the band (x of W, y of H):
    /// the knoll's apex, on the right-third line.
    var knollApex: CGPoint
    /// Horizon line (fraction of H).
    var horizon: CGFloat
    /// The tree canvas is a square of this many band heights.
    var treeSide: CGFloat

    /// The far layer is rendered this much wider than the band, centred,
    /// so parallax (0.35×) never shows its edge.
    static let farWidthFactor: CGFloat = 1.35
    static let farParallax: CGFloat = 0.35
    /// The front layer (grass in front of the trunk base) covers the bottom of the band.
    static let frontHeightFraction: CGFloat = 0.32

    /// The tree canvas frame: TreeCanvasLayout puts the ground at 0.93 of
    /// the square's side, so that point lands on the knoll apex.
    func treeFrame(in band: CGSize) -> CGRect {
        let side = band.height * treeSide
        return CGRect(x: band.width * knollApex.x - side / 2,
                      y: band.height * knollApex.y - side * 0.93,
                      width: side, height: side)
    }
}

/// Non-localized scene data, cheap enough to read every frame.
nonisolated struct GardenSceneInfo: Equatable, Sendable {
    let id: GardenSceneID
    /// SF Symbol for the seed-packet stamp and look chips.
    let stampSymbol: String
    let defaultSpecies: GardenSpecies
    let layout: GardenSceneLayout
    /// Map annotation ring and swatch accent.
    let accent: GardenRGB
    /// The placeholder band's flat ground (the near layer's main colour),
    /// drawn with SwiftUI shapes while a page's static images load.
    let groundDay: GardenRGB
    let groundNight: GardenRGB
}

extension GardenSceneID {
    nonisolated var info: GardenSceneInfo {
        switch self {
        case .meadow:
            return GardenSceneInfo(id: self, stampSymbol: "leaf", defaultSpecies: .oak,
                                   layout: GardenSceneLayout(knollApex: CGPoint(x: 0.62, y: 0.86), horizon: 0.58, treeSide: 0.86),
                                   accent: GardenRGB(0x6FAF5F), groundDay: GardenRGB(0x86C27A), groundNight: GardenRGB(0x1E3A2E))
        case .seaside:
            return GardenSceneInfo(id: self, stampSymbol: "water.waves", defaultSpecies: .palm,
                                   layout: GardenSceneLayout(knollApex: CGPoint(x: 0.64, y: 0.84), horizon: 0.54, treeSide: 0.86),
                                   accent: GardenRGB(0x2F8FBF), groundDay: GardenRGB(0xF2DDB0), groundNight: GardenRGB(0x5B5240))
        case .cityLights:
            return GardenSceneInfo(id: self, stampSymbol: "building.2", defaultSpecies: .cherry,
                                   layout: GardenSceneLayout(knollApex: CGPoint(x: 0.60, y: 0.80), horizon: 0.66, treeSide: 0.80),
                                   accent: GardenRGB(0xC8553D), groundDay: GardenRGB(0xC9B8A6), groundNight: GardenRGB(0x2D2A35))
        case .mountainLake:
            return GardenSceneInfo(id: self, stampSymbol: "mountain.2", defaultSpecies: .pine,
                                   layout: GardenSceneLayout(knollApex: CGPoint(x: 0.66, y: 0.86), horizon: 0.56, treeSide: 0.86),
                                   accent: GardenRGB(0x5E9CB8), groundDay: GardenRGB(0x5F8F57), groundNight: GardenRGB(0x18301F))
        case .lanternTown:
            return GardenSceneInfo(id: self, stampSymbol: "lamp.table", defaultSpecies: .cherry,
                                   layout: GardenSceneLayout(knollApex: CGPoint(x: 0.66, y: 0.86), horizon: 0.62, treeSide: 0.86),
                                   accent: GardenRGB(0xE63946), groundDay: GardenRGB(0xB8A58A), groundNight: GardenRGB(0x3E3830))
        case .riceTerraces:
            return GardenSceneInfo(id: self, stampSymbol: "leaf.circle", defaultSpecies: .banyan,
                                   layout: GardenSceneLayout(knollApex: CGPoint(x: 0.62, y: 0.84), horizon: 0.56, treeSide: 0.86),
                                   accent: GardenRGB(0x7DBF4E), groundDay: GardenRGB(0x7DBF4E), groundNight: GardenRGB(0x1E3324))
        case .campus:
            return GardenSceneInfo(id: self, stampSymbol: "graduationcap", defaultSpecies: .oak,
                                   layout: GardenSceneLayout(knollApex: CGPoint(x: 0.64, y: 0.86), horizon: 0.62, treeSide: 0.86),
                                   accent: GardenRGB(0xB5654B), groundDay: GardenRGB(0x79B566), groundNight: GardenRGB(0x1C3424))
        case .homePorch:
            return GardenSceneInfo(id: self, stampSymbol: "house", defaultSpecies: .oak,
                                   layout: GardenSceneLayout(knollApex: CGPoint(x: 0.64, y: 0.86), horizon: 0.60, treeSide: 0.86),
                                   accent: GardenRGB(0xA3574A), groundDay: GardenRGB(0x7DB46C), groundNight: GardenRGB(0x1C3424))
        }
    }

    /// Look picker, postcard rows and VoiceOver.
    nonisolated var displayName: String {
        switch self {
        case .meadow:       return String(localized: "Meadow", comment: "Garden scene name: fields with a windmill")
        case .seaside:      return String(localized: "Seaside", comment: "Garden scene name: a beach with a lighthouse")
        case .cityLights:   return String(localized: "City Lights", comment: "Garden scene name: a rooftop under string lights")
        case .mountainLake: return String(localized: "Mountain Lake", comment: "Garden scene name: peaks above a lake")
        case .lanternTown:  return String(localized: "Lantern Town", comment: "Garden scene name: an old town with silk lanterns by a river")
        case .riceTerraces: return String(localized: "Rice Terraces", comment: "Garden scene name: stepped rice fields")
        case .campus:       return String(localized: "Campus", comment: "Garden scene name: a university lawn with a clock tower")
        case .homePorch:
            // Own key: a plain "Home" key is the Home tab.
            return String(localized: "garden.scene.home", defaultValue: "Home",
                          comment: "Garden scene name: the porch of a little house (not the Home tab). Shown under its swatch in the look picker and in the Look rows, as in 'Home · Oak'.")
        }
    }

    /// A whole phrase for VoiceOver: "in a meadow with a windmill".
    nonisolated var spokenPhrase: String {
        switch self {
        case .meadow:       return String(localized: "in a meadow with a windmill", comment: "VoiceOver: where a garden tree stands")
        case .seaside:      return String(localized: "by the sea, with a lighthouse", comment: "VoiceOver: where a garden tree stands")
        case .cityLights:   return String(localized: "on a rooftop under string lights", comment: "VoiceOver: where a garden tree stands")
        case .mountainLake: return String(localized: "by a mountain lake", comment: "VoiceOver: where a garden tree stands")
        case .lanternTown:  return String(localized: "in a lantern-lit old town by a river", comment: "VoiceOver: where a garden tree stands")
        case .riceTerraces: return String(localized: "above green rice terraces", comment: "VoiceOver: where a garden tree stands")
        case .campus:       return String(localized: "on a campus lawn with a clock tower", comment: "VoiceOver: where a garden tree stands")
        case .homePorch:    return String(localized: "by the porch of a little house", comment: "VoiceOver: where a garden tree stands")
        }
    }
}

/// Everything a page needs to know about its place in time.
nonisolated struct GardenSceneEnvironment: Equatable, Sendable {
    var scene: GardenSceneID
    var season: GardenSceneSeason
    var sky: GardenSkyState
    /// A stable per-tree seed (FNV-1a of the tree key) for scattered props.
    var seed: UInt64

    static func make(scene: GardenSceneID, place: GardenPlace?, treeKey: String, now: Date,
                     phoneTimeZone: TimeZone = .current) -> GardenSceneEnvironment {
        let zone = place?.timeZone ?? phoneTimeZone
        return GardenSceneEnvironment(scene: scene,
                                      season: GardenSeasons.season(at: now, latitude: place?.latitude, timeZone: zone,
                                                                   scene: scene),
                                      sky: GardenSky.state(at: now, in: zone),
                                      seed: JourneyTreeOrnament.stableSeed(treeKey))
    }

    /// "in a meadow with a windmill, in the evening, in autumn": one
    /// localized format holding three localized phrases (no concatenation).
    var spokenSetting: String {
        let place = scene.spokenPhrase, time = sky.timeOfDay.spokenPhrase, when = season.spokenPhrase
        return String(localized: "\(place), \(time), \(when)",
                      comment: "VoiceOver: where and when a garden tree is. Example: in a meadow with a windmill, in the evening, in autumn")
    }
}

// MARK: - Tree canvas inputs (implemented by P7 in RelationshipTreeCanvas)

nonisolated enum TreeBackdrop: Equatable, Sendable {
    /// Follow the app's colour scheme (today's behaviour).
    case automatic
    /// A light sky behind the tree: today's light-scheme bark, amber stars.
    case light
    /// A dark sky: lit bark, cream stars (even in the app's Light mode).
    case dark
}

nonisolated enum TreeMotionPose: Equatable, Sendable {
    case live, frozen, still
}

nonisolated enum TreeCanvasClock: Equatable, Sendable {
    /// The canvas runs its own TimelineView and pause rules (today).
    case own
    /// The scene page's single TimelineView drives it; no second clock.
    case external(time: TimeInterval, pose: TreeMotionPose)
}

nonisolated enum TreeGlow: Equatable, Sendable {
    /// Today's warm ambient glow.
    case always
    /// Only as light falls: intensity 0…1 (the sky's darkness).
    case dusk(intensity: Double)
    case none
}

nonisolated struct TreeCanvasStyle: Equatable, Sendable {
    var species: GardenSpecies
    var backdrop: TreeBackdrop
    /// Today's soft ground patch. Off inside a scene (the knoll is the ground).
    var drawsGround: Bool
    var glow: TreeGlow
    /// Leaves, blossoms and fruit are seeded from this; nil = from the days
    /// together (Our tree, exactly today's silhouette). Place trees pass
    /// FNV-1a(key) so their shape is stable and their own.
    var topologySeed: UInt64?
    /// The scene has snow (`GardenSceneSeason.hasSnow`): a temperate winter.
    /// The canvas only gets `TreeSeason`, whose `.winter` is also the mild
    /// winter of a tree without a place; this tells them apart (the pine's
    /// snow edge; the banyan darkens only in a mild winter). False outside
    /// a scene (today's hero).
    var snows: Bool = false

    /// Today's hero tree, unchanged.
    static let hero = TreeCanvasStyle(species: .oak, backdrop: .automatic, drawsGround: true, glow: .always, topologySeed: nil)

    static func scene(species: GardenSpecies, sky: GardenSkyState, season: GardenSceneSeason,
                      topologySeed: UInt64?) -> TreeCanvasStyle {
        TreeCanvasStyle(species: species, backdrop: sky.treeBackdrop, drawsGround: false,
                        glow: .dusk(intensity: sky.darkness), topologySeed: topologySeed, snows: season.hasSnow)
    }
}

nonisolated struct TreeVitality: Equatable, Sendable {
    var thirst: Double
    var wetness: Double
    var dew: Double
    var soilDryness: Double
    /// 0…1, see `GardenTreeVisual.lushness`.
    var lushness: Double = 0
    /// Revival after a watering: droop eases from `reviveFrom` to 0 over
    /// 1.2 s with an easeOutBack overshoot (1.4), from `reviveStart`.
    var reviveFrom: Double
    var reviveStart: TimeInterval?

    static let healthy = TreeVitality(thirst: 0, wetness: 0, dew: 0, soilDryness: 0, reviveFrom: 0, reviveStart: nil)

    init(thirst: Double, wetness: Double, dew: Double, soilDryness: Double,
         lushness: Double = 0, reviveFrom: Double = 0, reviveStart: TimeInterval? = nil) {
        self.thirst = thirst
        self.wetness = wetness
        self.dew = dew
        self.soilDryness = soilDryness
        self.lushness = lushness
        self.reviveFrom = reviveFrom
        self.reviveStart = reviveStart
    }

    init(_ visual: GardenTreeVisual) {
        self.init(thirst: visual.thirst, wetness: visual.wetness, dew: visual.dew, soilDryness: visual.soilDryness,
                  lushness: visual.lushness)
    }

    /// The droop to draw at `time` (reference-date seconds). Negative values
    /// (the overshoot) lift the leaves a little past level.
    func droop(at time: TimeInterval) -> Double {
        guard let start = reviveStart else { return thirst }
        let t = min(1, max(0, (time - start) / 1.2))
        let s = 1.4, u = t - 1
        let easeOutBack = 1 + (s + 1) * u * u * u + s * u * u
        return reviveFrom * (1 - easeOutBack)
    }
}

/// The note tag hanging from the selected tree until the note is read.
nonisolated struct TreeNoteTag: Equatable, Sendable {
    let wateringId: String
}

/// Points effects and overlays anchor to, from the same TreeCanvasLayout
/// the drawing uses (`RelationshipTreeCanvas.anchors(in:stage:)`).
nonisolated struct TreeCanvasAnchors: Equatable, Sendable {
    var unit: CGFloat
    var trunkBase: CGPoint
    var trunkTop: CGPoint
    var canopyCenter: CGPoint
    var canopyRadius: CGFloat
    var groundY: CGFloat
    /// The soil bed ellipse at the trunk base.
    var soilRect: CGRect
    var noteTagPoint: CGPoint
    /// Where the partner's can rests (left) and this user's (right).
    var leftCanPoint: CGPoint
    var rightCanPoint: CGPoint
    var limbTips: [CGPoint]

    /// Shifts canvas-local anchors into the scene page's coordinates.
    func offset(by origin: CGPoint) -> TreeCanvasAnchors {
        func m(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + origin.x, y: p.y + origin.y) }
        return TreeCanvasAnchors(unit: unit, trunkBase: m(trunkBase), trunkTop: m(trunkTop),
                                 canopyCenter: m(canopyCenter), canopyRadius: canopyRadius,
                                 groundY: groundY + origin.y,
                                 soilRect: soilRect.offsetBy(dx: origin.x, dy: origin.y),
                                 noteTagPoint: m(noteTagPoint), leftCanPoint: m(leftCanPoint),
                                 rightCanPoint: m(rightCanPoint), limbTips: limbTips.map(m))
    }
}

// MARK: - Scene painting (P5 and P6 implement; P10 composes)

nonisolated enum GardenSkyVariant: String, Hashable, Sendable {
    case day, night
}

nonisolated enum GardenBackdropLayer: String, Hashable, Sendable {
    /// Behind everything but the sky: hills, skyline, peaks, sea. Rendered
    /// GardenSceneLayout.farWidthFactor wide for parallax.
    case far
    /// Ground, knoll, landmark, props: in front of `far`, behind the tree.
    case near
    /// Grass and planter faces IN FRONT of the trunk base (bottom 32%).
    case front
}

nonisolated enum GardenAmbientPass: String, Sendable {
    /// Celestial bodies, stars, clouds: drawn before `far`.
    case sky
    /// Scene life on the far plane (blades, beam, gulls, boats, lanterns): between `far` and `near`.
    case behind
    /// Falling petals, leaves, snow, fireflies: in front of the tree.
    case front
}

/// Inputs to a static layer. Static layers never depend on the time of day
/// (the day and night variants are blended by the sky's darkness) and never
/// on the TREE: they are seeded by the scene, so every tree in a scene shares
/// the same cached images (GardenBackdropKey has no tree in it).
nonisolated struct GardenSceneStyle: Hashable, Sendable {
    var variant: GardenSkyVariant
    var season: GardenSceneSeason

    /// The seed for a scene's static props (skyline, scatter, flowers).
    static func staticSeed(for scene: GardenSceneID) -> UInt64 {
        JourneyTreeOrnament.stableSeed("garden.static." + scene.rawValue)
    }
}

nonisolated struct GardenAmbientState: Equatable, Sendable {
    /// Reference-date seconds from the page's TimelineView.
    var time: TimeInterval
    var pose: TreeMotionPose
    var sky: GardenSkyState
    var season: GardenSceneSeason
    /// Per tree (GardenSceneEnvironment.seed): ambient life is never cached,
    /// so it can differ between two trees in the same scene.
    var seed: UInt64

    var isLive: Bool { pose == .live }
}

/// One scene's art. Pure value types; every draw call is safe off the main
/// actor (Canvas renders asynchronously). No text is ever drawn in a canvas.
nonisolated protocol GardenScenePainting: Sendable {
    var scene: GardenSceneID { get }
    func drawLayer(_ layer: GardenBackdropLayer, in context: GraphicsContext, size: CGSize, style: GardenSceneStyle)
    /// Budget: at most 30 moving primitives across the three passes.
    func drawAmbient(_ pass: GardenAmbientPass, in context: GraphicsContext, size: CGSize, state: GardenAmbientState)
    /// The scene's own touch in the last 0.6 s of any watering (progress 0…1).
    func drawWateringAccent(in context: GraphicsContext, size: CGSize, state: GardenAmbientState, progress: Double)
}

/// One cached static layer: scene, layer, variant, season, size, scale.
/// Deliberately no tree (see GardenSceneStyle).
nonisolated struct GardenBackdropKey: Hashable, Sendable {
    var scene: GardenSceneID
    var layer: GardenBackdropLayer
    var style: GardenSceneStyle
    /// Logical size of the band (the far layer's width is multiplied inside).
    var width: Int
    var height: Int
    /// min(displayScale, 2): landscapes are soft; 2× is plenty.
    var scale: Int

    /// Bump whenever any scene's static art changes: the disk tier lives
    /// under GardenBackdrops/v<artVersion>/ and older folders are deleted.
    static let artVersion = 2

    /// The disk tier's file name.
    var fileName: String {
        "\(scene.rawValue)-\(layer.rawValue)-\(style.variant.rawValue)-\(style.season.rawValue)-\(width)x\(height)@\(scale)x.png"
    }
}

/// The memory tier is sized from the working set: the selected page and its
/// two neighbours, each needing both variants at twilight.
nonisolated enum GardenBackdropBudget {
    static let pagesInMemory = 3
    static let variantsPerPage = 2
    /// Library/Caches/GardenBackdrops: our own art only (no user data), kept
    /// across sign-outs, oldest files evicted beyond this.
    static let diskFolder = "GardenBackdrops"
    static let diskLimitBytes = 48 * 1024 * 1024

    /// RGBA bytes of one page variant: far (1.35 W) + near (W) + front (0.32 H) at scale².
    /// 351×208 @2x ≈ 3.12 MB; 416×208 @2x ≈ 3.70 MB.
    static func bytesPerPageVariant(band: CGSize, scale: Int) -> Int {
        let area = Double(band.width) * Double(band.height)
        let layers = Double(GardenSceneLayout.farWidthFactor) + 1 + Double(GardenSceneLayout.frontHeightFraction)
        return Int((area * layers * 4 * Double(scale * scale)).rounded(.up))
    }

    /// The NSCache totalCostLimit (≈ 19 MB at 351 pt, ≈ 22 MB at 416 pt).
    static func memoryCostLimit(band: CGSize, scale: Int) -> Int {
        pagesInMemory * variantsPerPage * bytesPerPageVariant(band: band, scale: scale)
    }
}

/// P5's GardenBackdropCache (singleton `GardenBackdropCache.shared`).
@MainActor
protocol GardenBackdropProviding: AnyObject {
    /// Memory tier, else disk tier (decoded off the main actor), else a render
    /// with ImageRenderer on the main actor (≤ 8 ms on an A12, at most one per
    /// frame across all callers), then written to disk in the background.
    func image(for key: GardenBackdropKey) async -> CGImage?
    /// Memory tier only; never loads or renders (a page mid-swipe).
    func cachedImage(for key: GardenBackdropKey) -> CGImage?
    /// Brings `keys` into memory at low priority, one per run-loop turn; a
    /// new call replaces the previous queue (the pager's neighbours).
    func prewarm(_ keys: [GardenBackdropKey])
    /// Sets the memory tier's limit to GardenBackdropBudget.memoryCostLimit.
    func configure(band: CGSize, scale: Int)
    /// A small day-variant swatch for look chips, the shelf and map annotations.
    func swatch(scene: GardenSceneID, season: GardenSceneSeason, size: CGSize) -> CGImage?
    /// Clears the memory tier (the disk tier holds only our own art).
    func removeAll()
}

// MARK: - Watering effects (P8 implements `WateringEffectPainter`)

nonisolated struct GardenEffectFrame: Equatable, Sendable {
    var playback: GardenEffectPlayback
    /// Seconds since `playback.startTime` (the golden first drop included).
    var elapsed: TimeInterval
    /// In the scene page's coordinates.
    var anchors: TreeCanvasAnchors
    var size: CGSize
    var sky: GardenSkyState
}

nonisolated protocol WateringEffectDrawing {
    /// Draws one frame of `frame.playback.effect`; nothing after it ends.
    static func draw(in context: GraphicsContext, frame: GardenEffectFrame)
}

// MARK: - Maps (P9 implements `GardenMapSnapshotter.shared`)

nonisolated struct GardenSnapshotRequest: Hashable, Sendable {
    var latitude: Double
    var longitude: Double
    var precision: GardenPlacePrecision
    var width: Int
    var height: Int
    var isDark: Bool

    init(place: GardenPlace, size: CGSize, isDark: Bool) {
        latitude = place.latitude
        longitude = place.longitude
        precision = place.precision
        width = Int(size.width.rounded())
        height = Int(size.height.rounded())
        self.isDark = isDark
    }
}

@MainActor
protocol GardenMapSnapshotting: AnyObject {
    /// Exact: an 800 m span with a tree pin drawn at the spot. Area: a 6 km
    /// span with a soft circle, never a pin. nil offline or on failure (the
    /// caller then shows the scene swatch). Never a live map in a list.
    func snapshot(_ request: GardenSnapshotRequest) async -> CGImage?
    func purge()
}

// MARK: - Services (P3 implements FirestoreGardenService and InMemoryGardenService)

@MainActor
protocol GardenSubscription: AnyObject {
    func cancel()
}

@MainActor
protocol GardenConnectivityMonitoring: AnyObject {
    var isOnline: Bool { get }
}

@MainActor
protocol GardenServicing: AnyObject {
    // Reads
    func probe() async -> GardenProbeResult
    func observeAnchor(coupleId: String, onUpdate: @escaping (GardenAnchorState) -> Void,
                       onError: @escaping (Error) -> Void) -> GardenSubscription
    /// docType in [tree, proposal, waterer]; metadata changes included.
    func observeGarden(coupleId: String, onUpdate: @escaping (GardenDocsSnapshot) -> Void,
                       onError: @escaping (Error) -> Void) -> GardenSubscription
    /// Ordered by wateredAt desc, limit GardenLimits.wateringListen; metadata changes included.
    func observeWaterings(coupleId: String, onUpdate: @escaping (GardenWateringsSnapshot) -> Void,
                          onError: @escaping (Error) -> Void) -> GardenSubscription
    func observePartner(partnerId: String, onUpdate: @escaping (GardenPartnerInfo) -> Void,
                        onError: @escaping (Error) -> Void) -> GardenSubscription
    func journalPage(coupleId: String, before: Date?, limit: Int) async throws -> [GardenWatering]

    // Writes that may queue offline (batch / confirmed write; ≤ 2.5 s)
    func announceCapability(userId: String) async
    /// `wateringId` comes from GardenDocID.newWatering(), never from a service.
    func water(coupleId: String, by me: String, wateringId: String, note: String?, effect: GardenEffect) async throws
    func changeLook(coupleId: String, slot: GardenSlot, by me: String, look: GardenLook, previous: GardenLook) async throws

    // Proposals and consent: transactions, offline fail-fast, 10 s timeout,
    // typed errors. Every carry-out compares the version the user saw.
    /// A place seed: takes my first free seed_<me>_n (.tooManySeeds when all
    /// three exist). Returns its id.
    func proposePlaceSeed(coupleId: String, by me: String, draft: GardenDraft) async throws -> String
    func proposeOurTree(coupleId: String, by me: String, draft: GardenDraft) async throws
    func editProposal(coupleId: String, id: String, by me: String, draft: GardenDraft,
                      seen: GardenProposalVersion) async throws
    /// `key` is the proposal's key as last seen: a take-back that lost the race
    /// to a planting reads as "already planted" (a tree carries the key)
    /// instead of "gone" (T4).
    func takeBack(coupleId: String, id: String, by me: String, key: String?) async throws
    func letGo(coupleId: String, id: String) async throws
    /// Plants a seed (seed_our also writes `config`). `alsoDelete` drops my own
    /// duplicate seed in the same transaction ("Plant Sam's") if it is still
    /// mine. `key` is the seed's key as last seen ("already planted" vs
    /// "gone", T6/T7). Returns the slot.
    func plant(coupleId: String, proposalId: String, by me: String, seen: GardenProposalVersion,
               proposerName: String?, alsoDelete: String?, key: String?) async throws -> GardenSlot
    func proposeChange(coupleId: String, slot: GardenSlot, by me: String, draft: GardenDraft) async throws
    func proposeRest(coupleId: String, slot: GardenSlot, by me: String, note: String?) async throws
    func proposeStartDate(coupleId: String, by me: String, day: Date, note: String?) async throws
    /// Carries out change_<slot>, startdate or rest_<slot>.
    func agree(coupleId: String, proposalId: String, by me: String, seen: GardenProposalVersion) async throws
    func recordOurTree(coupleId: String, by me: String) async throws
    func recordStartDate(coupleId: String, by me: String) async throws
    func deleteVoidProposal(coupleId: String, id: String) async throws
}

// MARK: - Local reminders (P4 implements GardenReminderScheduler)

nonisolated struct GardenReminderPlan: Equatable, Sendable {
    var coupleId: String
    /// Server time of the latest CONFIRMED watering by either partner (never a
    /// pending write; my own watering re-plans once the server confirms it).
    var lastWateredAt: Date?
    var lastWateringId: String?
    /// Our tree exists (a start date is set). Built only from a RESOLVED anchor.
    var hasOurTree: Bool
    /// The Garden notification toggle (its UserDefaults mirror, default
    /// true), and false while the garden is switched off remotely
    /// (GardenReminderScheduler.remindersAllowed). The scheduler also no-ops
    /// without notification authorization.
    var isEnabled: Bool

    /// Whole milliseconds: the unit of GardenDefaultsKey.lastWateringMs.
    var lastWateredAtMs: Int64? {
        lastWateredAt.map { Int64(($0.timeIntervalSince1970 * 1000).rounded()) }
    }

    /// Monotonic re-planning. A plan that would schedule (Our tree, toggle on)
    /// but knows an OLDER watering than the one already planned for this
    /// couple (or none at all) is stale and ignored: a queued step built from
    /// an older cached snapshot can never restore a reminder a newer watering
    /// removed. Plans that only cancel (no Our tree, toggle off) are never stale.
    func isStale(storedLastWateringMs stored: Int64?) -> Bool {
        guard hasOurTree, isEnabled, let stored else { return false }
        guard let mine = lastWateredAtMs else { return true }
        return mine < stored
    }
}

@MainActor
protocol GardenReminderScheduling: AnyObject {
    /// Ignores a stale plan (GardenReminderPlan.isStale against the stored
    /// lastWateringMs); otherwise replaces tt.garden.ready / tt.garden.rest,
    /// removes delivered ones that are no longer true and stores the plan's
    /// time. Never schedules for a never-watered garden.
    func reschedule(_ plan: GardenReminderPlan) async
    /// Pending AND delivered tt.garden.*.
    func cancelAll() async
}

// MARK: - View-facing values (P3 produces, P9/P10 render)

nonisolated enum GardenFocus: Equatable, Sendable {
    case overview
    case watering(id: String)
    case proposal(id: String)
    case tree(slot: GardenSlot)

    /// From a tapped push or reminder's own userInfo. nil if not a garden one.
    init?(notificationUserInfo info: [AnyHashable: Any]) {
        guard let type = info[GardenNotification.typeKey] as? String,
              GardenNotification.allTypes.contains(type) else { return nil }
        let focus = info[GardenNotification.focusKey] as? String
        if focus == GardenNotification.focusWatering, let id = info[GardenNotification.wateringIdKey] as? String, !id.isEmpty {
            self = .watering(id: id)
        } else if focus == GardenNotification.focusProposal, let id = info[GardenNotification.proposalIdKey] as? String, !id.isEmpty {
            self = .proposal(id: id)
        } else if focus == GardenNotification.focusTree,
                  let raw = info[GardenNotification.treeSlotKey] as? String, let slot = GardenSlot(rawValue: raw) {
            self = .tree(slot: slot)
        } else {
            self = .overview
        }
    }
}

nonisolated enum GardenNoticeKind: Equatable, Sendable {
    case seedSetAside(title: String)
    case startDateChangedElsewhere(storedDay: Date)
    case lookChanged(slot: GardenSlot, treeTitle: String)
    case wateringRefused(at: Date)
    case homeInvite
}

nonisolated struct GardenNotice: Identifiable, Equatable, Sendable {
    let id: String
    let kind: GardenNoticeKind
    let text: String
    /// "OK", "Change it back", "Water again", "Choose a place"…
    let actionTitle: String?
    let dismissTitle: String?
    /// A heading above `text`, for notices shown as a card (the home invite).
    var title: String? = nil
}

nonisolated enum GardenRestingCans: Equatable, Sendable {
    case none, mine, partners, both
}

/// One pager page (garden data only; Journey adds Our tree's day count,
/// stage, letters and stars).
nonisolated struct GardenPageModel: Identifiable, Equatable, Sendable {
    let slot: GardenSlot
    let key: String
    var title: String
    var preset: GardenPreset
    var look: GardenLook
    var place: GardenPlace?
    var environment: GardenSceneEnvironment
    /// This tree's look only: GardenTreeVisual.forTree(lastWateredAt: L, plantedAt:, now:).
    var visual: GardenTreeVisual
    /// Place trees: the stored instant they grow from (nil for Our tree).
    var growthStart: Date?
    var restingCans: GardenRestingCans
    var showsRainbow: Bool
    var noteTag: TreeNoteTag?
    /// "Café Giảng", "Where we first met · Café Giảng", "Add a place", or nil.
    var placeChip: String?
    var placeChipIsAction: Bool
    var hasPendingWrites: Bool

    var id: String { slot.rawValue }
}

nonisolated struct GardenNoteModel: Equatable, Sendable {
    let wateringId: String
    let text: String
    /// "Sam · today at 9:14 PM"
    let attribution: String
}

nonisolated struct GardenStatusModel: Equatable, Sendable {
    /// One line, B3 table.
    let line: String
    /// Accent-tinted for 2 s when a partner watering is first seen.
    let isNews: Bool
    let note: GardenNoteModel?
}

/// The planting hero (no start date). Its button shows only when
/// GardenPrimaryAction.emptyHeroShowsButton(availability:) is true.
nonisolated enum GardenEmptyHero: Equatable, Sendable {
    case plantSeed(partnerCanAnswer: Bool?)
    case mySeedWaiting(storedStartDay: Date, partnerCanAnswer: Bool?)
    case partnersSeed(proposalId: String, storedStartDay: Date, note: String?)
}

nonisolated struct GardenHeroModel: Equatable, Sendable {
    var availability: GardenAvailability
    /// Non-nil when there is no start date (resolved).
    var empty: GardenEmptyHero?
    /// Per-tree looks (GardenTreeVisual.forTree) live in the pages.
    var pages: [GardenPageModel]
    var selectedSlot: GardenSlot
    /// Garden-level (GardenWaterState.garden, L alone): independent of the selected page.
    var status: GardenStatusModel?
    /// Garden-level, like `status`.
    var waterAction: GardenWaterAction
    /// "Give it its first water", "Water back", "Water your tree", "Water all 4 trees", "Water now".
    var waterTitle: String?
    var primary: GardenPrimaryAction
    var treeCount: Int
    var requestWaitingForMe: Bool
    var partnerCanGarden: Bool?
}

nonisolated enum GardenRequestKind: Equatable, Sendable {
    case seed, ourTreeSeed, change, startDate, rest
}

nonisolated struct GardenRequestModel: Identifiable, Equatable, Sendable {
    let id: String              // proposal id
    let kind: GardenRequestKind
    let isMine: Bool            // waiting for the partner (quiet row) vs for me (card)
    let title: String
    let lines: [String]
    let primaryTitle: String
    let secondaryTitle: String?
    /// The version shown, passed to plant/agree/editProposal. nil while the
    /// proposal has pending writes: its actions are disabled until then.
    let seen: GardenProposalVersion?
    let isSnoozed: Bool
}

nonisolated struct GardenHomeLine: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case request, watered }
    let kind: Kind
    let title: String
    let subtitle: String?
    let focus: GardenFocus
    let spokenLabel: String
}

nonisolated struct GardenJournalEntry: Identifiable, Equatable, Sendable {
    let id: String
    let byMe: Bool
    let name: String
    let when: String
    let partnerLocalTime: String?
    let note: String?
    /// Starts a "Together" pair with the next (older) entry.
    let pairsWithNext: Bool
    /// The watering's server time (nil while pending): month grouping and
    /// the journal's paging cursor.
    var wateredAt: Date? = nil
}

nonisolated struct GardenCeremony: Identifiable, Equatable, Sendable {
    let slot: GardenSlot
    let key: String
    /// The display title (`GardenTree.displayTitle`), shown as given.
    let title: String
    /// The tree's place (its name for the subtitle, its time zone and
    /// latitude for the ceremony's sky and season).
    let place: GardenPlace?
    let look: GardenLook
    /// The stored instant it grows from (nil: from today).
    let growthStart: Date?
    /// A place tree's remembered moment (a stored calendar day, 10:00 UTC):
    /// "Planted 14 Nov 2026 · for 12 March 2023". Never changes growth.
    var momentDay: Date? = nil
    let plantedAt: Date?
    let plantedByNames: [String]
    let isOurTree: Bool

    var id: String { key }
}

// MARK: - Notifications

nonisolated enum GardenNotification {
    static let typeKey = "type"
    // Pushes (Cloud Functions)
    static let wateredType = "garden_watered"
    static let proposalType = "garden_proposal"
    static let agreedType = "garden_agreed"
    // Local reminders (GardenReminderScheduler)
    static let readyReminderType = "gardenReady"
    static let restReminderType = "gardenRest"

    static let allTypes: Set<String> = [wateredType, proposalType, agreedType, readyReminderType, restReminderType]

    // Payload / userInfo keys (all string values)
    static let coupleIdKey = "coupleId"
    static let focusKey = "gardenFocus"
    static let wateringIdKey = "wateringId"
    static let proposalIdKey = "proposalId"
    static let treeSlotKey = "treeSlot"
    static let momentKey = "moment"
    static let kindKey = "kind"
    static let wateredAtMsKey = "wateredAtMs"
    static let bodyKey = "body"

    // gardenFocus values
    static let focusWatering = "watering"
    static let focusProposal = "proposal"
    static let focusTree = "tree"
    static let focusOverview = "overview"

    // Local reminder identifiers (2 of iOS's 64 pending requests)
    static let reminderPrefix = "tt.garden."
    static let readyReminderId = "tt.garden.ready"
    static let restReminderId = "tt.garden.rest"

    static let pushThreadPrefix = "coupley-garden-"
    static let reminderThread = "coupley-journey"
}

// MARK: - Device storage

/// Every key starts with `coupley.garden.`. GardenViewModel.purgeLocalCaches()
/// removes all of them except those `isKeptOnPurge` names when the app
/// leaves .ready.
nonisolated enum GardenDefaultsKey {
    static let prefix = "coupley.garden."
    /// Written by WidgetSyncService on bind, removed on unbind; a background
    /// push re-plans reminders only for this couple.
    static let activeCoupleId = prefix + "activeCoupleId"
    /// Mirror of users/{me}.notificationPreferences.garden (default true).
    static let notificationsEnabled = prefix + "notificationsEnabled"

    // What this install remembers about one backend (GardenBackendState):
    // `backend` is "<Firebase project id>@<Firestore host>", so a DEBUG
    // emulator run never vouches for production. Only the real backend
    // writes them; the DEBUG lab and previews keep their answers in memory.

    /// The rules probe answered (enabled or switched off) from this backend.
    static func rulesVerified(backend: String) -> String { prefix + "rulesVerified." + backend }
    /// The backend's last definitive answer was `appConfig/garden {enabled: false}`:
    /// the garden stays off through an offline or slow probe, and its
    /// reminders with it, until the backend answers enabled.
    static func remoteDisabled(backend: String) -> String { prefix + "remoteDisabled." + backend }
    /// Estimated server clock offset (seconds), clamped to ±600.
    static func serverOffset(backend: String) -> String { prefix + "serverOffset." + backend }

    static func lastWateringMs(_ coupleId: String) -> String { prefix + "lastWateringMs." + coupleId }
    static func cache(_ coupleId: String) -> String { prefix + "cache." + coupleId }
    static func seenWatering(_ coupleId: String) -> String { prefix + "seenWatering." + coupleId }
    static func ceremonySeen(_ coupleId: String, key: String) -> String { prefix + "ceremonySeen." + coupleId + "." + key }
    static func inviteDismissed(_ coupleId: String) -> String { prefix + "inviteDismissed." + coupleId }
    /// Seeds only, keyed by the seed's key (a UUID): place-seed ids are reused.
    static func snoozed(_ coupleId: String, seedKey: String) -> String { prefix + "snoozed." + coupleId + "." + seedKey }
    static func noticeSeen(_ coupleId: String, id: String) -> String { prefix + "noticeSeen." + coupleId + "." + id }
    static func homeDraft(_ coupleId: String) -> String { prefix + "homeDraft." + coupleId }
    static func selectedSlot(_ coupleId: String) -> String { prefix + "selectedSlot." + coupleId }
    /// JSON object seed key -> {id, title, preset, setAside} of the seeds I
    /// sent, keyed by the key because place-seed ids are reused ("set aside"
    /// detection and its notice's title).
    static func myOpenSeeds(_ coupleId: String) -> String { prefix + "myOpenSeeds." + coupleId }
    /// The start date (seconds since 1970) this device last saw agreed or
    /// acknowledged: a start date changed any other way is told once per
    /// device, even after another device has recorded it.
    static func startDateSeen(_ coupleId: String) -> String { prefix + "startDateSeen." + coupleId }

    /// Kept when the app leaves .ready: what the install knows about the
    /// backend (its rules answered; it switched the garden off).
    static func isKeptOnPurge(_ key: String) -> Bool {
        key.hasPrefix(prefix + "rulesVerified.") || key.hasPrefix(prefix + "remoteDisabled.")
    }
}
