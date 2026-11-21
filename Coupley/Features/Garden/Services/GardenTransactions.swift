//
//  GardenTransactions.swift
//  Coupley
//
//  The pure bodies of the garden's consent transactions (spec I4, T0–T13):
//  raw snapshot dictionaries and Sendable values in, writes out. They run
//  on Firestore's queue, so everything here is nonisolated and never
//  touches main-actor state. Every carry-out compares the version the user
//  saw (GardenProposalVersion) with the one read inside the transaction.
//
//  A plan never decodes a value it copies: a carried-out tree (and `config`)
//  is built from the proposal's RAW dictionary, Timestamps and the `place`
//  map copied as they are, so the rules' equality checks hold.
//
//  `plan(_:reads:stamps:)` is the whole logic. `firestoreBody(for:in:)`
//  wraps it for `Firestore.runTransaction`; InMemoryGardenService (DEBUG)
//  runs the same plans against its own store, so the lab exercises them too.
//

import Foundation
import FirebaseFirestore

nonisolated enum GardenTransactions {

    // MARK: - Inputs

    /// What a seed or a change request proposes, already in stored form
    /// (GardenCodec.content(from:)): days are stored calendar days.
    struct Content: Equatable, Sendable {
        var title: String
        var preset: GardenPreset
        var scene: GardenSceneID
        var species: GardenSpecies
        var place: GardenPlace?
        var momentDay: Date?
        /// Our tree's seed and a start-date suggestion only.
        var startDay: Date?
        var note: String?
    }

    enum Operation: Sendable {
        /// T0. `newKey` becomes the future tree's key.
        case proposePlaceSeed(me: String, content: Content, newKey: String)
        /// T1.
        case proposeOurTree(me: String, content: Content, newKey: String)
        /// T2. `day` is a stored calendar day.
        case proposeStartDate(me: String, day: Date, note: String?)
        /// T3: my own proposal (edit) or the partner's, answered with my version (counter).
        case editProposal(id: String, me: String, content: Content, seen: GardenProposalVersion, isCounter: Bool)
        /// T4. `key` is the proposal's key as last seen ("already planted" detection).
        case takeBack(id: String, me: String, key: String?)
        /// T5: let a seed go, or keep things as they are (change, start date, rest).
        case letGo(id: String)
        /// T6 (seed_our) and T7 (a place seed).
        case plant(id: String, me: String, seen: GardenProposalVersion, proposerName: String?,
                   alsoDelete: String?, key: String?)
        /// T8.
        case proposeChange(slot: GardenSlot, me: String, content: Content)
        /// T9.
        case proposeRest(slot: GardenSlot, me: String, note: String?)
        /// T10 (change_<slot>), T11 (startdate), T12 (rest_<slot>).
        case agree(id: String, me: String, seen: GardenProposalVersion)
        /// T13: Our tree from an existing start date.
        case recordOurTree(me: String, newKey: String)
        /// T13: Our tree's agreed day re-recorded after a legacy edit.
        case recordStartDate(me: String, newKey: String)
    }

    /// Raw document data by id, as read inside the transaction. A missing
    /// document is absent.
    typealias Reads = [String: [String: Any]]

    /// The two sentinels a write may carry: Firestore passes
    /// `FieldValue.serverTimestamp()` and `FieldValue.delete()`; the DEBUG
    /// in-memory service passes its own clock's Timestamp and a marker.
    struct Stamps {
        let server: Any
        let delete: Any
    }

    // MARK: - Outputs

    enum Write {
        case set(String, [String: Any])
        case update(String, [String: Any])
        case delete(String)
    }

    struct Plan {
        var writes: [Write] = []
        /// A place seed's new id (T0) or the planted slot's raw value (T6/T7).
        var result: String?
    }

    // MARK: - Reads

    private static let allTreeIds = GardenSlot.allCases.map(GardenDocID.tree)
    private static let placeTreeIds = GardenSlot.placeSlots.map(GardenDocID.tree)

    /// Every document `plan` may look at for `operation`.
    static func reads(for operation: Operation) -> [String] {
        switch operation {
        case .proposePlaceSeed(let me, _, _):
            return GardenDocID.placeSeedNumbers.map { GardenDocID.placeSeed(creator: me, number: $0) } + [GardenDocID.config]
        case .proposeOurTree:
            return [GardenDocID.seedOurTree, GardenDocID.config]
        case .proposeStartDate:
            return [GardenDocID.startDate, GardenDocID.config, GardenDocID.tree(.our)]
        case .editProposal(let id, _, _, _, _), .letGo(let id):
            return [id]
        case .takeBack(let id, _, _):
            return [id] + allTreeIds
        case .plant(let id, _, _, _, let alsoDelete, _):
            if id == GardenDocID.seedOurTree {
                return [id, GardenDocID.config, GardenDocID.tree(.our)]
            }
            return [id] + placeTreeIds + (alsoDelete.map { [$0] } ?? [])
        case .proposeChange(let slot, _, _):
            return [GardenDocID.change(slot), GardenDocID.tree(slot)]
        case .proposeRest(let slot, _, _):
            return slot.isOurTree ? [] : [GardenDocID.rest(slot), GardenDocID.tree(slot)]
        case .agree(let id, _, _):
            if id == GardenDocID.startDate {
                return [id, GardenDocID.config, GardenDocID.tree(.our)]
            }
            return [id] + (targetTreeId(ofRequest: id).map { [$0] } ?? [])
        case .recordOurTree, .recordStartDate:
            return [GardenDocID.tree(.our), GardenDocID.config, GardenDocID.startDate]
        }
    }

    /// `change_p3` / `rest_p3` → `tree_p3`.
    private static func targetTreeId(ofRequest id: String) -> String? {
        for prefix in ["change_", "rest_"] where id.hasPrefix(prefix) {
            return GardenSlot(rawValue: String(id.dropFirst(prefix.count))).map(GardenDocID.tree)
        }
        return nil
    }

    // MARK: - Plans

    static func plan(_ operation: Operation, reads: Reads, stamps: Stamps) -> Result<Plan, GardenError> {
        switch operation {
        case .proposePlaceSeed(let me, let content, let newKey):
            return proposePlaceSeed(me: me, content: content, newKey: newKey, reads: reads, stamps: stamps)
        case .proposeOurTree(let me, let content, let newKey):
            return proposeOurTree(me: me, content: content, newKey: newKey, reads: reads, stamps: stamps)
        case .proposeStartDate(let me, let day, let note):
            return proposeStartDate(me: me, day: day, note: note, reads: reads, stamps: stamps)
        case .editProposal(let id, let me, let content, let seen, let isCounter):
            return editProposal(id: id, me: me, content: content, seen: seen, isCounter: isCounter, reads: reads, stamps: stamps)
        case .takeBack(let id, let me, let key):
            return takeBack(id: id, me: me, key: key, reads: reads)
        case .letGo(let id):
            guard reads[id] != nil else { return .failure(.gone) }
            return .success(Plan(writes: [.delete(id)]))
        case .plant(let id, let me, let seen, let proposerName, let alsoDelete, let key):
            if id == GardenDocID.seedOurTree {
                return plantOurTree(me: me, seen: seen, proposerName: proposerName, key: key, reads: reads, stamps: stamps)
            }
            return plantPlaceTree(id: id, me: me, seen: seen, alsoDelete: alsoDelete, key: key, reads: reads, stamps: stamps)
        case .proposeChange(let slot, let me, let content):
            return proposeChange(slot: slot, me: me, content: content, reads: reads, stamps: stamps)
        case .proposeRest(let slot, let me, let note):
            return proposeRest(slot: slot, me: me, note: note, reads: reads, stamps: stamps)
        case .agree(let id, let me, let seen):
            if id == GardenDocID.startDate {
                return agreeStartDate(me: me, seen: seen, reads: reads, stamps: stamps)
            }
            if id.hasPrefix("change_") {
                return agreeChange(id: id, me: me, seen: seen, reads: reads, stamps: stamps)
            }
            if id.hasPrefix("rest_") {
                return agreeRest(id: id, me: me, seen: seen, reads: reads)
            }
            return .failure(.invalid)
        case .recordOurTree(let me, let newKey):
            return record(me: me, newKey: newKey, reRecord: false, reads: reads, stamps: stamps)
        case .recordStartDate(let me, let newKey):
            return record(me: me, newKey: newKey, reRecord: true, reads: reads, stamps: stamps)
        }
    }

    // MARK: T0 – T2: new proposals

    private static func proposePlaceSeed(me: String, content: Content, newKey: String,
                                         reads: Reads, stamps: Stamps) -> Result<Plan, GardenError> {
        guard reads[GardenDocID.config] != nil, content.preset != .ourTree else { return .failure(.invalid) }
        let open = Set(reads.keys.filter(GardenDocID.isPlaceSeed))
        guard let id = GardenDocID.firstFreePlaceSeed(creator: me, existing: open) else {
            return .failure(.tooManySeeds)
        }
        let fields = proposal(kind: .plant, slot: "new", key: newKey, by: me, rev: 1, note: content.note,
                              stamps: stamps, content: contentFields(content, isOurTree: false))
        return .success(Plan(writes: [.set(id, fields)], result: id))
    }

    private static func proposeOurTree(me: String, content: Content, newKey: String,
                                       reads: Reads, stamps: Stamps) -> Result<Plan, GardenError> {
        guard reads[GardenDocID.config] == nil else { return .failure(.startDateSetElsewhere) }
        guard let startDay = content.startDay else { return .failure(.invalid) }
        var key = newKey, rev = 1
        if let existing = reads[GardenDocID.seedOurTree] {
            // Mine already (another of my devices): this send becomes its next version.
            guard GardenCodec.string(existing[GardenField.by]) == me else { return .failure(.partnerProposedFirst) }
            guard let existingKey = GardenCodec.string(existing[GardenField.key]),
                  let existingRev = GardenCodec.int(existing[GardenField.rev]) else { return .failure(.invalid) }
            key = existingKey
            rev = existingRev + 1
        }
        var fields = proposal(kind: .plant, slot: GardenSlot.our.rawValue, key: key, by: me, rev: rev,
                              note: content.note, stamps: stamps, content: contentFields(content, isOurTree: true))
        fields[GardenField.startDay] = Timestamp(date: startDay)
        return .success(Plan(writes: [.set(GardenDocID.seedOurTree, fields)]))
    }

    private static func proposeStartDate(me: String, day: Date, note: String?,
                                         reads: Reads, stamps: Stamps) -> Result<Plan, GardenError> {
        guard let config = reads[GardenDocID.config],
              let currentStart = GardenCodec.timestamp(config["startDate"]),
              let tree = reads[GardenDocID.tree(.our)],
              let treeKey = GardenCodec.string(tree[GardenField.key]) else { return .failure(.invalid) }
        var rev = 1
        if let existing = reads[GardenDocID.startDate] {
            guard GardenCodec.string(existing[GardenField.by]) == me else { return .failure(.partnerProposedFirst) }
            guard GardenCodec.string(existing[GardenField.key]) == treeKey,
                  let existingRev = GardenCodec.int(existing[GardenField.rev]) else { return .failure(.invalid) }
            rev = existingRev + 1
        }
        var fields = proposal(kind: .startDate, slot: GardenSlot.our.rawValue, key: treeKey, by: me, rev: rev,
                              note: note, stamps: stamps, content: [:])
        fields[GardenField.startDay] = Timestamp(date: day)
        // Raw copy: the rules compare it with config.startDate.
        fields[GardenField.fromStartDay] = currentStart
        return .success(Plan(writes: [.set(GardenDocID.startDate, fields)]))
    }

    // MARK: T3 – T5: edit, counter, take back

    private static func editProposal(id: String, me: String, content: Content, seen: GardenProposalVersion,
                                     isCounter: Bool, reads: Reads, stamps: Stamps) -> Result<Plan, GardenError> {
        guard let existing = reads[id] else { return .failure(.gone) }
        guard GardenCodec.version(of: existing) == seen else { return .failure(.changed) }
        let by = GardenCodec.string(existing[GardenField.by])
        if isCounter {
            guard by != me else { return .failure(.invalid) }
        } else {
            guard by == me else { return .failure(.notYours) }
        }
        guard let kind = GardenCodec.string(existing[GardenField.kind]).flatMap(GardenProposalKind.init(rawValue:)),
              let slot = GardenCodec.string(existing[GardenField.slot]),
              let key = GardenCodec.string(existing[GardenField.key]) else { return .failure(.invalid) }
        let isOurTree = slot == GardenSlot.our.rawValue
        var body: [String: Any] = [:]
        switch kind {
        case .plant, .change:
            body = contentFields(content, isOurTree: isOurTree)
            if kind == .plant, isOurTree {
                guard let startDay = content.startDay else { return .failure(.invalid) }
                body[GardenField.startDay] = Timestamp(date: startDay)
            }
        case .rest:
            break
        case .startDate:
            guard let startDay = content.startDay,
                  let from = existing[GardenField.fromStartDay] else { return .failure(.invalid) }
            body[GardenField.startDay] = Timestamp(date: startDay)
            body[GardenField.fromStartDay] = from
        }
        let fields = proposal(kind: kind, slot: slot, key: key, by: me, rev: seen.rev + 1,
                              note: content.note, stamps: stamps, content: body)
        return .success(Plan(writes: [.set(id, fields)]))
    }

    private static func takeBack(id: String, me: String, key: String?, reads: Reads) -> Result<Plan, GardenError> {
        guard let existing = reads[id] else {
            return .failure(treeCarries(key: key, among: allTreeIds, reads: reads) ? .alreadyPlanted : .gone)
        }
        guard GardenCodec.string(existing[GardenField.by]) == me else { return .failure(.notYours) }
        return .success(Plan(writes: [.delete(id)]))
    }

    // MARK: T6 – T7: planting

    private static func plantOurTree(me: String, seen: GardenProposalVersion, proposerName: String?, key: String?,
                                     reads: Reads, stamps: Stamps) -> Result<Plan, GardenError> {
        let id = GardenDocID.seedOurTree
        guard let seed = reads[id] else {
            return .failure(treeCarries(key: key, among: [GardenDocID.tree(.our)], reads: reads) ? .alreadyPlanted : .gone)
        }
        guard let proposer = GardenCodec.string(seed[GardenField.by]), proposer != me else { return .failure(.invalid) }
        guard GardenCodec.version(of: seed) == seen else { return .failure(.changed) }
        guard reads[GardenDocID.config] == nil else { return .failure(.startDateSetElsewhere) }
        guard let startDay = seed[GardenField.startDay] as? Timestamp,
              var tree = plantedTree(from: seed, slot: .our, proposalId: id, proposer: proposer, me: me, stamps: stamps)
        else { return .failure(.invalid) }
        tree[GardenField.agreedStartDay] = startDay

        // The 1.2 format, so a partner on 1.2 reads the same start date.
        var config: [String: Any] = [
            "startDate": startDay,
            "setBy": proposer,
            "setAt": stamps.server,
            "updatedAt": stamps.server
        ]
        if let proposerName, !proposerName.isEmpty { config["setByName"] = proposerName }

        return .success(Plan(writes: [.set(GardenDocID.config, config),
                                      .set(GardenDocID.tree(.our), tree),
                                      .delete(id)],
                             result: GardenSlot.our.rawValue))
    }

    private static func plantPlaceTree(id: String, me: String, seen: GardenProposalVersion, alsoDelete: String?,
                                       key: String?, reads: Reads, stamps: Stamps) -> Result<Plan, GardenError> {
        guard GardenDocID.isPlaceSeed(id) else { return .failure(.invalid) }
        guard let seed = reads[id] else {
            return .failure(treeCarries(key: key, among: placeTreeIds, reads: reads) ? .alreadyPlanted : .gone)
        }
        guard let proposer = GardenCodec.string(seed[GardenField.by]), proposer != me else { return .failure(.invalid) }
        guard GardenCodec.version(of: seed) == seen else { return .failure(.changed) }
        guard let slot = GardenSlot.placeSlots.first(where: { reads[GardenDocID.tree($0)] == nil }) else {
            return .failure(.full)
        }
        guard let tree = plantedTree(from: seed, slot: slot, proposalId: id, proposer: proposer, me: me, stamps: stamps)
        else { return .failure(.invalid) }

        var writes: [Write] = [.set(GardenDocID.tree(slot), tree), .delete(id)]
        // "Plant Sam's": my own duplicate goes too, but only while it is still mine.
        if let alsoDelete, alsoDelete != id, let duplicate = reads[alsoDelete],
           GardenCodec.string(duplicate[GardenField.by]) == me {
            writes.append(.delete(alsoDelete))
        }
        return .success(Plan(writes: writes, result: slot.rawValue))
    }

    /// The tree a seed becomes: its content copied RAW, both names, the
    /// server's time. Our tree's `agreedStartDay` is added by the caller.
    private static func plantedTree(from seed: [String: Any], slot: GardenSlot, proposalId: String,
                                    proposer: String, me: String, stamps: Stamps) -> [String: Any]? {
        guard let key = GardenCodec.string(seed[GardenField.key]) else { return nil }
        var tree: [String: Any] = [
            GardenField.docType: GardenDocType.tree.rawValue,
            GardenField.slot: slot.rawValue,
            GardenField.key: key,
            GardenField.origin: GardenTreeOrigin.together.rawValue,
            GardenField.plantedAt: stamps.server,
            GardenField.plantedBy: [proposer, me],
            GardenField.agreementKind: GardenAgreementKind.plant.rawValue,
            GardenField.agreementBy: [proposer, me],
            GardenField.agreementAt: stamps.server,
            GardenField.fromProposal: proposalId,
            GardenField.updatedAt: stamps.server
        ]
        guard copyContent(from: seed, into: &tree, slot: slot) else { return nil }
        return tree
    }

    // MARK: T8 – T9: requests about a planted tree

    private static func proposeChange(slot: GardenSlot, me: String, content: Content,
                                      reads: Reads, stamps: Stamps) -> Result<Plan, GardenError> {
        let id = GardenDocID.change(slot)
        guard let tree = reads[GardenDocID.tree(slot)],
              let treeKey = GardenCodec.string(tree[GardenField.key]) else { return .failure(.gone) }
        let rev: Int
        switch nextRev(of: reads[id], me: me, treeKey: treeKey) {
        case .success(let value): rev = value
        case .failure(let error): return .failure(error)
        }
        let fields = proposal(kind: .change, slot: slot.rawValue, key: treeKey, by: me, rev: rev, note: content.note,
                              stamps: stamps, content: contentFields(content, isOurTree: slot.isOurTree))
        return .success(Plan(writes: [.set(id, fields)]))
    }

    private static func proposeRest(slot: GardenSlot, me: String, note: String?,
                                    reads: Reads, stamps: Stamps) -> Result<Plan, GardenError> {
        guard !slot.isOurTree else { return .failure(.invalid) }
        let id = GardenDocID.rest(slot)
        guard let tree = reads[GardenDocID.tree(slot)],
              let treeKey = GardenCodec.string(tree[GardenField.key]) else { return .failure(.gone) }
        let rev: Int
        switch nextRev(of: reads[id], me: me, treeKey: treeKey) {
        case .success(let value): rev = value
        case .failure(let error): return .failure(error)
        }
        let fields = proposal(kind: .rest, slot: slot.rawValue, key: treeKey, by: me, rev: rev, note: note,
                              stamps: stamps, content: [:])
        return .success(Plan(writes: [.set(id, fields)]))
    }

    /// A fixed-id request: the partner's existing one wins (the second sender
    /// sees it and may answer it); my own becomes its next version.
    private static func nextRev(of existing: [String: Any]?, me: String, treeKey: String) -> Result<Int, GardenError> {
        guard let existing else { return .success(1) }
        guard GardenCodec.string(existing[GardenField.by]) == me else { return .failure(.partnerProposedFirst) }
        guard GardenCodec.string(existing[GardenField.key]) == treeKey,
              let rev = GardenCodec.int(existing[GardenField.rev]) else { return .failure(.invalid) }
        return .success(rev + 1)
    }

    // MARK: T10 – T12: agreeing

    private static func agreeChange(id: String, me: String, seen: GardenProposalVersion,
                                    reads: Reads, stamps: Stamps) -> Result<Plan, GardenError> {
        guard let request = reads[id], let treeId = targetTreeId(ofRequest: id),
              let slot = GardenDocID.slot(ofTreeDocument: treeId) else { return .failure(.gone) }
        guard let proposer = GardenCodec.string(request[GardenField.by]), proposer != me else { return .failure(.invalid) }
        guard GardenCodec.version(of: request) == seen else { return .failure(.changed) }
        guard let tree = reads[treeId] else { return .failure(.gone) }
        guard GardenCodec.string(request[GardenField.key]) == GardenCodec.string(tree[GardenField.key]) else {
            return .failure(.changed)
        }
        var update: [String: Any] = [
            GardenField.fromProposal: id,
            GardenField.agreementKind: GardenAgreementKind.change.rawValue,
            GardenField.agreementBy: [proposer, me],
            GardenField.agreementAt: stamps.server,
            GardenField.updatedAt: stamps.server
        ]
        guard copyContent(from: request, into: &update, slot: slot) else { return .failure(.invalid) }
        // An absent place or day in the request means "none": remove it.
        for field in [GardenField.place, GardenField.momentDay] where update[field] == nil {
            update[field] = stamps.delete
        }
        return .success(Plan(writes: [.update(treeId, update), .delete(id)]))
    }

    private static func agreeStartDate(me: String, seen: GardenProposalVersion,
                                       reads: Reads, stamps: Stamps) -> Result<Plan, GardenError> {
        let id = GardenDocID.startDate
        guard let request = reads[id] else { return .failure(.gone) }
        guard let proposer = GardenCodec.string(request[GardenField.by]), proposer != me else { return .failure(.invalid) }
        guard GardenCodec.version(of: request) == seen else { return .failure(.changed) }
        guard let config = reads[GardenDocID.config], let tree = reads[GardenDocID.tree(.our)],
              let startDay = request[GardenField.startDay] as? Timestamp else { return .failure(.invalid) }
        guard GardenCodec.string(request[GardenField.key]) == GardenCodec.string(tree[GardenField.key]) else {
            return .failure(.changed)
        }
        // Void once config moved any other way (a legacy app's direct edit).
        guard GardenCodec.sameInstant(GardenCodec.date(config["startDate"]),
                                      GardenCodec.date(request[GardenField.fromStartDay])) else {
            return .failure(.startDateChanged)
        }
        let configUpdate: [String: Any] = ["startDate": startDay, "updatedAt": stamps.server]
        let treeUpdate: [String: Any] = [
            GardenField.agreedStartDay: startDay,
            GardenField.fromProposal: id,
            GardenField.agreementKind: GardenAgreementKind.startDate.rawValue,
            GardenField.agreementBy: [proposer, me],
            GardenField.agreementAt: stamps.server,
            GardenField.updatedAt: stamps.server
        ]
        return .success(Plan(writes: [.update(GardenDocID.config, configUpdate),
                                      .update(GardenDocID.tree(.our), treeUpdate),
                                      .delete(id)]))
    }

    private static func agreeRest(id: String, me: String, seen: GardenProposalVersion,
                                  reads: Reads) -> Result<Plan, GardenError> {
        guard let request = reads[id], let treeId = targetTreeId(ofRequest: id) else { return .failure(.gone) }
        guard let proposer = GardenCodec.string(request[GardenField.by]), proposer != me else { return .failure(.invalid) }
        guard GardenCodec.version(of: request) == seen else { return .failure(.changed) }
        guard let tree = reads[treeId] else { return .failure(.gone) }
        guard GardenCodec.string(request[GardenField.key]) == GardenCodec.string(tree[GardenField.key]) else {
            return .failure(.changed)
        }
        return .success(Plan(writes: [.delete(treeId), .delete(id)]))
    }

    // MARK: T13: recording

    /// Our tree from the start date as it is: created when missing, its
    /// agreed day re-recorded when a legacy app moved the date (`reRecord`).
    /// Nothing is written when it already matches. A start-date suggestion
    /// made against the old date is void and goes in the same transaction.
    private static func record(me: String, newKey: String, reRecord: Bool,
                               reads: Reads, stamps: Stamps) -> Result<Plan, GardenError> {
        guard let config = reads[GardenDocID.config],
              let start = config["startDate"] as? Timestamp else { return .success(Plan()) }
        var writes: [Write] = []
        if let tree = reads[GardenDocID.tree(.our)] {
            guard reRecord else { return .success(Plan()) }
            if !GardenCodec.sameInstant(GardenCodec.date(tree[GardenField.agreedStartDay]), start.dateValue()) {
                writes.append(.update(GardenDocID.tree(.our), [
                    GardenField.agreedStartDay: start,
                    GardenField.agreementKind: GardenAgreementKind.recorded.rawValue,
                    GardenField.agreementBy: [me],
                    GardenField.agreementAt: stamps.server,
                    GardenField.updatedAt: stamps.server
                ]))
            }
        } else {
            writes.append(.set(GardenDocID.tree(.our), [
                GardenField.docType: GardenDocType.tree.rawValue,
                GardenField.slot: GardenSlot.our.rawValue,
                GardenField.key: newKey,
                GardenField.title: GardenPreset.ourTree.storedDefaultTitle,
                GardenField.preset: GardenPreset.ourTree.rawValue,
                GardenField.scene: GardenLook.ourTreeDefault.scene.rawValue,
                GardenField.species: GardenLook.ourTreeDefault.species.rawValue,
                GardenField.origin: GardenTreeOrigin.legacy.rawValue,
                GardenField.agreedStartDay: start,
                GardenField.agreementKind: GardenAgreementKind.recorded.rawValue,
                GardenField.agreementBy: [me],
                GardenField.agreementAt: stamps.server,
                GardenField.updatedAt: stamps.server
            ]))
        }
        if reRecord, let suggestion = reads[GardenDocID.startDate],
           !GardenCodec.sameInstant(GardenCodec.date(suggestion[GardenField.fromStartDay]), start.dateValue()) {
            writes.append(.delete(GardenDocID.startDate))
        }
        return .success(Plan(writes: writes))
    }

    // MARK: - Field builders

    /// A whole proposal document. `content` carries the kind-specific fields.
    private static func proposal(kind: GardenProposalKind, slot: String, key: String, by: String, rev: Int,
                                 note: String?, stamps: Stamps, content: [String: Any]) -> [String: Any] {
        var fields = content
        fields[GardenField.docType] = GardenDocType.proposal.rawValue
        fields[GardenField.kind] = kind.rawValue
        fields[GardenField.slot] = slot
        fields[GardenField.key] = key
        fields[GardenField.by] = by
        fields[GardenField.at] = stamps.server
        fields[GardenField.rev] = rev
        if let note = GardenLimits.seedNote.clean(note) {
            fields[GardenField.note] = GardenLimits.seedNote.truncate(note)
        }
        return fields
    }

    /// A tree's identity and look as a seed or change proposes it. Our tree
    /// keeps its fixed title and preset and never has a moment's day.
    private static func contentFields(_ content: Content, isOurTree: Bool) -> [String: Any] {
        var fields: [String: Any] = [
            GardenField.title: isOurTree ? GardenPreset.ourTree.storedDefaultTitle : content.title,
            GardenField.preset: isOurTree ? GardenPreset.ourTree.rawValue : content.preset.rawValue,
            GardenField.scene: content.scene.rawValue,
            GardenField.species: (isOurTree && !content.species.canBeOurTree ? GardenSpecies.oak : content.species).rawValue
        ]
        if let place = content.place, let map = GardenCodec.placeFields(place) {
            fields[GardenField.place] = map
        }
        if !isOurTree, let day = content.momentDay {
            fields[GardenField.momentDay] = Timestamp(date: day)
        }
        return fields
    }

    /// Copies a proposal's content RAW into a tree write. False when a
    /// required field is missing.
    private static func copyContent(from proposal: [String: Any], into tree: inout [String: Any], slot: GardenSlot) -> Bool {
        for field in [GardenField.title, GardenField.preset, GardenField.scene, GardenField.species] {
            guard let value = proposal[field] else { return false }
            tree[field] = value
        }
        if let place = proposal[GardenField.place] { tree[GardenField.place] = place }
        if !slot.isOurTree, let day = proposal[GardenField.momentDay] { tree[GardenField.momentDay] = day }
        return true
    }

    private static func treeCarries(key: String?, among ids: [String], reads: Reads) -> Bool {
        guard let key else { return false }
        return ids.contains { GardenCodec.string(reads[$0]?[GardenField.key]) == key }
    }

    // MARK: - Errors through Firestore

    /// A GardenError travels out of a transaction body as an NSError in this
    /// domain (Firestore hands a body's error back unchanged).
    static let errorDomain = "GardenError"

    private static let codedErrors: [GardenError] = [
        .offline, .timedOut, .changed, .gone, .alreadyPlanted, .notYours, .partnerProposedFirst,
        .full, .tooManySeeds, .startDateChanged, .startDateSetElsewhere, .denied, .invalid, .other
    ]

    static func nsError(_ error: GardenError) -> NSError {
        NSError(domain: errorDomain, code: codedErrors.firstIndex(of: error) ?? codedErrors.count - 1)
    }

    static func gardenError(from error: NSError) -> GardenError? {
        guard error.domain == errorDomain, codedErrors.indices.contains(error.code) else { return nil }
        return codedErrors[error.code]
    }

    // MARK: - Firestore adapter

    /// The body for `Firestore.runTransaction`: reads every document the plan
    /// may need, plans, then writes. Built here, outside any actor, so the
    /// closure Firestore runs on its own queue is nonisolated; it captures
    /// only the operation (Sendable) and the collection reference.
    static func firestoreBody(for operation: Operation,
                              in collection: CollectionReference) -> (Transaction, NSErrorPointer) -> Any? {
        { transaction, errorPointer in
            var found: Reads = [:]
            do {
                for id in reads(for: operation) {
                    let snapshot = try transaction.getDocument(collection.document(id))
                    if snapshot.exists, let data = snapshot.data() { found[id] = data }
                }
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
            switch plan(operation, reads: found,
                        stamps: Stamps(server: FieldValue.serverTimestamp(), delete: FieldValue.delete())) {
            case .failure(let error):
                errorPointer?.pointee = nsError(error)
                return nil
            case .success(let plan):
                for write in plan.writes {
                    switch write {
                    case .set(let id, let data):
                        transaction.setData(data, forDocument: collection.document(id))
                    case .update(let id, let fields):
                        transaction.updateData(fields, forDocument: collection.document(id))
                    case .delete(let id):
                        transaction.deleteDocument(collection.document(id))
                    }
                }
                return plan.result
            }
        }
    }
}
