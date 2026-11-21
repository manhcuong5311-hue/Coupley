//
//  GardenCodec.swift
//  Coupley
//
//  Dictionary encoders and decoders for every garden document (spec E),
//  raw-copy helpers for the consent transactions, and defensive decoding
//  (spec I7): documents with missing or mistyped fields are skipped, unknown
//  tokens decode to fallbacks, and a proposal's shown version is computed
//  from its raw `at` Timestamp exactly as GardenTransactions computes it.
//
//  Membership checks (a tree planted by two members, a watering or a
//  proposal by a member) need the couple, so GardenViewModel applies them on
//  top of what decodes here.
//
//  Also the device cache (`GardenDefaultsKey.cache`): trees and the last
//  waterings without notes, for an offline first paint.
//

import Foundation
import FirebaseFirestore

nonisolated enum GardenCodec {

    // MARK: - Field readers

    /// A non-empty string.
    static func string(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        return text
    }

    static func int(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        return value as? Int
    }

    static func double(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        return value as? Double
    }

    static func timestamp(_ value: Any?) -> Timestamp? {
        value as? Timestamp
    }

    static func date(_ value: Any?) -> Date? {
        timestamp(value)?.dateValue()
    }

    static func strings(_ value: Any?) -> [String] {
        (value as? [Any])?.compactMap { $0 as? String } ?? []
    }

    // MARK: - Versions and instants

    /// Whole milliseconds of a raw Timestamp: the unit of GardenProposalVersion.
    static func millis(_ timestamp: Timestamp) -> Int64 {
        GardenProposalVersion.millis(seconds: timestamp.seconds, nanoseconds: timestamp.nanoseconds)
    }

    /// The version a proposal's raw data names: its `rev` and the whole
    /// milliseconds of its raw `at`. The codec (what the user was shown) and
    /// the transactions (what is read before carrying it out) both call this,
    /// so the two agree exactly when it is the same version.
    static func version(of data: [String: Any]) -> GardenProposalVersion? {
        guard let rev = int(data[GardenField.rev]), let at = timestamp(data[GardenField.at]) else { return nil }
        return GardenProposalVersion(rev: rev, atMillis: millis(at))
    }

    /// The rules' `sameInstant`: within a second, because a Date round trip
    /// can move an instant by a microsecond and 1.1/1.2 store raw instants.
    static func sameInstant(_ a: Date?, _ b: Date?) -> Bool {
        guard let a, let b else { return false }
        return abs(a.timeIntervalSince(b)) < 1
    }

    // MARK: - Places

    /// The `place` map, or nil for a malformed one (the tree keeps no place).
    static func place(_ value: Any?) -> GardenPlace? {
        guard let map = value as? [String: Any],
              let name = string(map[GardenField.placeName]),
              let latitude = double(map[GardenField.placeLat]),
              let longitude = double(map[GardenField.placeLng]),
              let precisionToken = string(map[GardenField.placePrecision]),
              let precision = GardenPlacePrecision(rawValue: precisionToken),
              (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        return GardenPlace(name: name, locality: string(map[GardenField.placeLocality]),
                           latitude: latitude, longitude: longitude, precision: precision,
                           poiCategory: string(map[GardenField.placePOI]),
                           timeZoneId: string(map[GardenField.placeTimeZone]))
    }

    /// The `place` map as the rules accept it: name and locality capped,
    /// coordinates already rounded to the precision (GardenPlace rounds on
    /// init), category and zone dropped when longer than the rules allow.
    /// nil when the place has neither a name nor a locality to show.
    static func placeFields(_ place: GardenPlace) -> [String: Any]? {
        let name = GardenLimits.placeName.clean(place.name) ?? GardenLimits.locality.clean(place.locality)
        guard let name else { return nil }
        var fields: [String: Any] = [
            GardenField.placeName: GardenLimits.placeName.truncate(name),
            GardenField.placeLat: place.latitude,
            GardenField.placeLng: place.longitude,
            GardenField.placePrecision: place.precision.rawValue
        ]
        if let locality = GardenLimits.locality.clean(place.locality) {
            fields[GardenField.placeLocality] = GardenLimits.locality.truncate(locality)
        }
        if let poi = place.poiCategory, !poi.isEmpty, poi.utf8.count <= 64 {
            fields[GardenField.placePOI] = poi
        }
        if let zone = place.timeZoneId, !zone.isEmpty, zone.utf8.count <= 64 {
            fields[GardenField.placeTimeZone] = zone
        }
        return fields
    }

    // MARK: - Drafts → proposal content

    /// What a draft proposes, in stored form: the title as stored data (the
    /// preset's base-language default or the couple's words), days as stored
    /// calendar days, the note cleaned. nil when it cannot be sent (a custom
    /// tree without a name, Our tree without a start day).
    static func content(from draft: GardenDraft) -> GardenTransactions.Content? {
        let note = GardenLimits.seedNote.clean(draft.note).map(GardenLimits.seedNote.truncate)
        if draft.isOurTree {
            let species = draft.look.species.canBeOurTree ? draft.look.species : .oak
            return GardenTransactions.Content(
                title: GardenPreset.ourTree.storedDefaultTitle, preset: .ourTree,
                scene: draft.look.scene, species: species, place: draft.place, momentDay: nil,
                startDay: draft.startDay.map { JourneyCalendarDay.storedMoment(forLocalDay: $0) },
                note: note)
        }
        let preset: GardenPreset = draft.preset == .ourTree ? .custom : draft.preset
        var copy = draft
        copy.preset = preset
        let title = GardenLimits.title.truncate(copy.storedTitle)
        guard !title.isEmpty else { return nil }
        return GardenTransactions.Content(
            title: title, preset: preset, scene: draft.look.scene, species: draft.look.species,
            place: draft.place,
            momentDay: draft.momentDay.map { JourneyCalendarDay.storedMoment(forLocalDay: $0) },
            startDay: nil, note: note)
    }

    // MARK: - Documents

    /// `tree_<slot>`, or nil when malformed.
    static func tree(id: String, data: [String: Any], hasPendingWrites: Bool) -> GardenTree? {
        guard data[GardenField.docType] as? String == GardenDocType.tree.rawValue,
              let slot = GardenDocID.slot(ofTreeDocument: id),
              data[GardenField.slot] as? String == slot.rawValue,
              let key = string(data[GardenField.key]),
              let title = string(data[GardenField.title]),
              let presetToken = string(data[GardenField.preset]),
              let sceneToken = string(data[GardenField.scene]),
              let speciesToken = string(data[GardenField.species]),
              let origin = string(data[GardenField.origin]).flatMap(GardenTreeOrigin.init(rawValue:)) else { return nil }
        let preset = slot.isOurTree ? .ourTree : GardenPreset(token: presetToken)
        var previousLook: GardenLook?
        if let scene = string(data[GardenField.prevScene]), let species = string(data[GardenField.prevSpecies]) {
            previousLook = GardenLook(scene: GardenSceneID(token: scene), species: GardenSpecies(token: species))
        }
        let agreement = string(data[GardenField.agreementKind]).flatMap(GardenAgreementKind.init(rawValue:))
            ?? (origin == .legacy ? .recorded : .plant)
        return GardenTree(slot: slot, key: key, title: title, preset: preset,
                          momentDay: slot.isOurTree ? nil : date(data[GardenField.momentDay]),
                          place: place(data[GardenField.place]),
                          look: GardenLook(scene: GardenSceneID(token: sceneToken), species: GardenSpecies(token: speciesToken)),
                          origin: origin,
                          plantedAt: date(data[GardenField.plantedAt]),
                          plantedBy: strings(data[GardenField.plantedBy]),
                          agreedStartDay: date(data[GardenField.agreedStartDay]),
                          agreementKind: agreement,
                          agreementBy: strings(data[GardenField.agreementBy]),
                          agreementAt: date(data[GardenField.agreementAt]),
                          fromProposal: string(data[GardenField.fromProposal]),
                          lookBy: string(data[GardenField.lookBy]),
                          lookAt: date(data[GardenField.lookAt]),
                          previousLook: previousLook,
                          updatedAt: date(data[GardenField.updatedAt]),
                          hasPendingWrites: hasPendingWrites)
    }

    /// A proposal, or nil when malformed or under an id that is no proposal.
    static func proposal(id: String, data: [String: Any], hasPendingWrites: Bool) -> GardenProposal? {
        guard data[GardenField.docType] as? String == GardenDocType.proposal.rawValue,
              GardenDocID.isProposal(id),
              let kind = string(data[GardenField.kind]).flatMap(GardenProposalKind.init(rawValue:)),
              let slot = string(data[GardenField.slot]),
              let key = string(data[GardenField.key]),
              let by = string(data[GardenField.by]),
              let rev = int(data[GardenField.rev]), rev >= 1 else { return nil }
        let at = timestamp(data[GardenField.at])
        var look: GardenLook?
        if let scene = string(data[GardenField.scene]), let species = string(data[GardenField.species]) {
            look = GardenLook(scene: GardenSceneID(token: scene), species: GardenSpecies(token: species))
        }
        return GardenProposal(id: id, kind: kind, slot: slot, key: key, by: by,
                              at: at?.dateValue(), atMillis: at.map(millis), rev: rev,
                              note: string(data[GardenField.note]),
                              startDay: date(data[GardenField.startDay]),
                              fromStartDay: date(data[GardenField.fromStartDay]),
                              title: string(data[GardenField.title]),
                              preset: string(data[GardenField.preset]).map(GardenPreset.init(token:)),
                              momentDay: date(data[GardenField.momentDay]),
                              place: place(data[GardenField.place]),
                              look: look,
                              hasPendingWrites: hasPendingWrites)
    }

    static func watering(id: String, data: [String: Any], hasPendingWrites: Bool) -> GardenWatering? {
        guard data[GardenField.docType] as? String == GardenDocType.water.rawValue,
              GardenDocID.isWater(id),
              let by = string(data[GardenField.by]) else { return nil }
        return GardenWatering(id: id, by: by, wateredAt: date(data[GardenField.wateredAt]),
                              note: string(data[GardenField.note]),
                              effect: GardenEffect(token: string(data[GardenField.effect]) ?? ""),
                              hasPendingWrites: hasPendingWrites)
    }

    static func waterer(id: String, data: [String: Any]) -> GardenWaterer? {
        let prefix = GardenDocID.waterer(uid: "")
        guard data[GardenField.docType] as? String == GardenDocType.waterer.rawValue,
              id.hasPrefix(prefix), id.count > prefix.count,
              let wateringId = string(data[GardenField.lastWateringId]) else { return nil }
        return GardenWaterer(uid: String(id.dropFirst(prefix.count)),
                             lastWateredAt: date(data[GardenField.lastWateredAt]),
                             lastWateringId: wateringId)
    }

    /// `config` as the garden reads it: only its start date matters, in any
    /// stored format (10:00 UTC, or a 1.1/1.2 raw instant).
    static func anchor(data: [String: Any]?) -> GardenAnchorState {
        guard let start = date(data?["startDate"]) else {
            return GardenAnchorState(exists: false, startDate: nil, isResolved: true)
        }
        return GardenAnchorState(exists: true, startDate: start, isResolved: true)
    }

    /// The partner's `users/{uid}` document. A missing capability means a
    /// build without the garden (never a version comparison).
    static func partner(data: [String: Any]?) -> GardenPartnerInfo {
        let capabilities = data?[GardenField.capabilities] as? [String: Any]
        let level = int(capabilities?[GardenField.capabilityGarden]) ?? 0
        return GardenPartnerInfo(canGarden: level >= GardenFeature.capabilityLevel,
                                 timeZone: string(data?["timezone"]).flatMap(TimeZone.init(identifier:)),
                                 displayName: string(data?["displayName"]))
    }

    // MARK: - Device cache

    private nonisolated struct CachedTree: Codable {
        var slot: GardenSlot
        var key: String
        var title: String
        var preset: GardenPreset
        var momentDay: Date?
        var place: GardenPlace?
        var look: GardenLook
        var origin: String
        var plantedAt: Date?
        var plantedBy: [String]
        var agreedStartDay: Date?
        var agreementKind: String
        var agreementBy: [String]
        var agreementAt: Date?
        var fromProposal: String?
        var lookBy: String?
        var lookAt: Date?
        var previousLook: GardenLook?
        var updatedAt: Date?
    }

    /// No note: notes stay in Firestore, never in the device cache.
    private nonisolated struct CachedWatering: Codable {
        var id: String
        var by: String
        var wateredAt: Date?
        var effect: GardenEffect
    }

    private nonisolated struct CachedGarden: Codable {
        var trees: [CachedTree]
        var waterings: [CachedWatering]
    }

    /// How many waterings the cache keeps.
    static let cachedWaterings = 10

    static func cacheData(trees: [GardenTree], waterings: [GardenWatering]) -> Data? {
        let cache = CachedGarden(
            trees: trees.map {
                CachedTree(slot: $0.slot, key: $0.key, title: $0.title, preset: $0.preset, momentDay: $0.momentDay,
                           place: $0.place, look: $0.look, origin: $0.origin.rawValue, plantedAt: $0.plantedAt,
                           plantedBy: $0.plantedBy, agreedStartDay: $0.agreedStartDay,
                           agreementKind: $0.agreementKind.rawValue, agreementBy: $0.agreementBy,
                           agreementAt: $0.agreementAt, fromProposal: $0.fromProposal, lookBy: $0.lookBy,
                           lookAt: $0.lookAt, previousLook: $0.previousLook, updatedAt: $0.updatedAt)
            },
            waterings: waterings.filter { !$0.hasPendingWrites }.prefix(cachedWaterings).map {
                CachedWatering(id: $0.id, by: $0.by, wateredAt: $0.wateredAt, effect: $0.effect)
            })
        return try? JSONEncoder().encode(cache)
    }

    static func decodeCache(_ data: Data) -> (trees: [GardenTree], waterings: [GardenWatering])? {
        guard let cache = try? JSONDecoder().decode(CachedGarden.self, from: data) else { return nil }
        let trees = cache.trees.compactMap { t -> GardenTree? in
            guard let origin = GardenTreeOrigin(rawValue: t.origin) else { return nil }
            return GardenTree(slot: t.slot, key: t.key, title: t.title, preset: t.preset, momentDay: t.momentDay,
                              place: t.place, look: t.look, origin: origin, plantedAt: t.plantedAt,
                              plantedBy: t.plantedBy, agreedStartDay: t.agreedStartDay,
                              agreementKind: GardenAgreementKind(rawValue: t.agreementKind) ?? .recorded,
                              agreementBy: t.agreementBy, agreementAt: t.agreementAt, fromProposal: t.fromProposal,
                              lookBy: t.lookBy, lookAt: t.lookAt, previousLook: t.previousLook,
                              updatedAt: t.updatedAt, hasPendingWrites: false)
        }
        let waterings = cache.waterings.map {
            GardenWatering(id: $0.id, by: $0.by, wateredAt: $0.wateredAt, note: nil, effect: $0.effect, hasPendingWrites: false)
        }
        return (trees, waterings)
    }
}
