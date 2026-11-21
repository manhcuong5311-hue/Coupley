//
//  InMemoryGardenService.swift
//  Coupley
//
//  DEBUG only: a GardenServicing that never touches Firestore, for the
//  garden lab (GardenLabView) and DEBUG-only previews. It scripts the
//  partner's actions and moves the clock, so every flow can be driven on
//  one device (spec K6). Anything that builds it sits inside #if DEBUG.
//
//  It keeps raw document dictionaries exactly as Firestore would (Timestamps,
//  the `place` map), decodes them with GardenCodec and carries out every
//  consent action with the same GardenTransactions plans as the real
//  service, so the lab exercises the real logic: versions, seed ids, slots,
//  the 12-hour turn. Watering ids come from the one generator both use
//  (GardenDocID.newWatering), so the lab cannot hide an id the rules refuse.
//

#if DEBUG

import Foundation
import FirebaseFirestore

/// What the lab's scripted partner can do.
enum GardenLabAction {
    case water(note: String?)
    case sendSeed(GardenPreset)
    case counterLatestSeed
    /// Takes the latest seed back and re-sends it under the same id (ABA).
    case recreateLatestSeed
    case askRest(GardenSlot)
    case suggestStartDate(Date)
    /// "Pretend Sam is on 1.2": the partner loses the garden capability.
    case pretendLegacy(Bool)
    /// Writes `config.startDate` the way a 1.2 app does (no garden documents).
    case writeStartDateLikeLegacy(Date)
}

final class InMemoryGardenService: GardenServicing {

    /// Moves the garden's clock: changing it by +71 h makes every stored
    /// server time (waterings, turns, plantings, proposals) 71 h older, so
    /// the garden reads as if that much time had passed. Calendar days
    /// (start date, moments) never move. The lab's slider: 0, +47, +71,
    /// +167, +200 h.
    var clockOffset: TimeInterval = 0 {
        didSet { age(by: clockOffset - oldValue) }
    }
    /// The next commit of this user waits 3 s before it lands ("Delay the
    /// next commit 3 s"), so a scripted partner action can race it.
    var delayNextCommit: Bool = false

    /// The partner's id until the view model observes the real one.
    private static let defaultPartnerId = "labpartner"

    private var documents: [String: [String: Any]] = [:]
    private var pendingIds: Set<String> = []
    private var users: [String: [String: Any]] = [:]
    private var partnerId = InMemoryGardenService.defaultPartnerId

    private var anchorListeners: [UUID: (GardenAnchorState) -> Void] = [:]
    private var gardenListeners: [UUID: (GardenDocsSnapshot) -> Void] = [:]
    private var wateringListeners: [UUID: (GardenWateringsSnapshot) -> Void] = [:]
    private var partnerListeners: [UUID: (GardenPartnerInfo) -> Void] = [:]
    private var deliveryScheduled = false

    /// Marks a field an update removes (Firestore's `FieldValue.delete()`).
    private final class DeleteMarker {}
    private let deleteMarker = DeleteMarker()

    /// Server times the clock offset ages. Calendar days are not among them.
    private static let serverTimeFields: Set<String> = [
        GardenField.at, GardenField.plantedAt, GardenField.agreementAt, GardenField.lookAt,
        GardenField.updatedAt, GardenField.wateredAt, GardenField.lastWateredAt, "setAt"
    ]

    /// An existing couple whose start date was set 300 days ago.
    convenience init() {
        let day = Calendar.current.date(byAdding: .day, value: -300, to: Date()) ?? Date()
        self.init(startDay: day)
    }

    /// `startDay` is a local day; nil starts a couple without a start date
    /// (the "Plant your first tree together" flow).
    init(startDay: Date?) {
        if let startDay {
            let now = Timestamp(date: Date())
            documents[GardenDocID.config] = [
                "startDate": Timestamp(date: JourneyCalendarDay.storedMoment(forLocalDay: startDay)),
                "setBy": Self.defaultPartnerId,
                "setAt": now,
                "updatedAt": now
            ]
        }
        users[Self.defaultPartnerId] = Self.partnerDocument(name: "Sam", canGarden: true)
    }

    private static func partnerDocument(name: String, canGarden: Bool) -> [String: Any] {
        var document: [String: Any] = ["displayName": name, "timezone": TimeZone.current.identifier]
        if canGarden {
            document[GardenField.capabilities] = [GardenField.capabilityGarden: GardenFeature.capabilityLevel]
        }
        return document
    }

    // MARK: Scripted partner

    func simulatePartner(_ action: GardenLabAction) {
        let partner = partnerId
        switch action {
        case .water(let note):
            partnerWaters(note: note)
        case .sendSeed(let preset):
            let hasStartDate = documents[GardenDocID.config] != nil
            if preset == .ourTree || !hasStartDate {
                let threeMonthsAgo = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()
                let content = GardenTransactions.Content(
                    title: GardenPreset.ourTree.storedDefaultTitle, preset: .ourTree,
                    scene: .meadow, species: .oak, place: nil, momentDay: nil,
                    startDay: JourneyCalendarDay.storedMoment(forLocalDay: threeMonthsAgo), note: nil)
                apply(.proposeOurTree(me: partner, content: content, newKey: UUID().uuidString))
            } else {
                let look = GardenLook.suggested(scene: preset.fallbackScene, forOurTree: false)
                let title = preset == .custom ? "Our rainy café" : preset.storedDefaultTitle
                let content = GardenTransactions.Content(
                    title: title, preset: preset, scene: look.scene, species: look.species,
                    place: nil, momentDay: nil, startDay: nil, note: nil)
                apply(.proposePlaceSeed(me: partner, content: content, newKey: UUID().uuidString))
            }
        case .counterLatestSeed:
            guard let (id, data) = latestProposal(where: { $0[GardenField.by] as? String != partner && $0[GardenField.kind] as? String == GardenProposalKind.plant.rawValue }),
                  let seen = GardenCodec.version(of: data),
                  let seed = GardenCodec.proposal(id: id, data: data, hasPendingWrites: false),
                  let look = seed.look else { return }
            let scenes = GardenSceneID.allCases
            let next = scenes[((scenes.firstIndex(of: look.scene) ?? 0) + 1) % scenes.count]
            let counterLook = GardenLook.suggested(scene: next, forOurTree: seed.slot == GardenSlot.our.rawValue)
            let content = GardenTransactions.Content(
                title: seed.title ?? "", preset: seed.preset ?? .custom, scene: counterLook.scene,
                species: counterLook.species, place: seed.place, momentDay: seed.momentDay,
                startDay: seed.startDay, note: nil)
            apply(.editProposal(id: id, me: partner, content: content, seen: seen, isCounter: true))
        case .recreateLatestSeed:
            guard let (id, data) = latestProposal(where: { $0[GardenField.by] as? String == partner }) else { return }
            var recreated = data
            recreated[GardenField.rev] = 1
            recreated[GardenField.at] = Timestamp(date: Date())
            if id == GardenDocID.seedOurTree { recreated[GardenField.key] = UUID().uuidString }
            documents[id] = recreated
            pendingIds.remove(id)
            scheduleDelivery()
        case .askRest(let slot):
            guard !slot.isOurTree else { return }
            apply(.proposeRest(slot: slot, me: partner, note: nil))
        case .suggestStartDate(let day):
            apply(.proposeStartDate(me: partner, day: JourneyCalendarDay.storedMoment(forLocalDay: day), note: nil))
        case .pretendLegacy(let isLegacy):
            let name = users[partner]?["displayName"] as? String ?? "Sam"
            users[partner] = Self.partnerDocument(name: name, canGarden: !isLegacy)
            scheduleDelivery()
        case .writeStartDateLikeLegacy(let instant):
            let now = Timestamp(date: Date())
            var config = documents[GardenDocID.config] ?? ["setAt": now]
            config["startDate"] = Timestamp(date: instant)
            config["setBy"] = partner
            config["updatedAt"] = now
            documents[GardenDocID.config] = config
            scheduleDelivery()
        }
    }

    /// The partner waters whatever their turn says: the lab drives them freely.
    private func partnerWaters(note: String?) {
        guard documents[GardenDocID.config] != nil else { return }
        let partner = partnerId
        let id = GardenDocID.newWatering()
        let now = Date()
        let others = decodedWaterings().filter { !$0.hasPendingWrites }
        let moment = GardenMoment.of(at: now, by: partner, others: others)
        let hour = Calendar.current.component(.hour, from: now)
        let effect = GardenEffect.choose(wateringId: id, moment: moment, localHour: hour,
                                         previous: decodedWaterings().first?.effect)
        writeWatering(id: id, by: partner, note: note, effect: effect, at: Timestamp(date: now))
        scheduleDelivery()
    }

    private func latestProposal(where matches: ([String: Any]) -> Bool) -> (String, [String: Any])? {
        documents
            .filter { $0.value[GardenField.docType] as? String == GardenDocType.proposal.rawValue && matches($0.value) }
            .max { (GardenCodec.date($0.value[GardenField.at]) ?? .distantPast) < (GardenCodec.date($1.value[GardenField.at]) ?? .distantPast) }
            .map { ($0.key, $0.value) }
    }

    /// Runs a partner plan at once; a refused one changes nothing.
    private func apply(_ operation: GardenTransactions.Operation) {
        _ = try? commit(operation)
    }

    // MARK: Reads

    func probe() async -> GardenProbeResult { .enabled }

    func observeAnchor(coupleId: String, onUpdate: @escaping (GardenAnchorState) -> Void,
                       onError: @escaping (Error) -> Void) -> GardenSubscription {
        let token = UUID()
        anchorListeners[token] = onUpdate
        scheduleDelivery()
        return InMemoryGardenSubscription { [weak self] in self?.anchorListeners[token] = nil }
    }

    func observeGarden(coupleId: String, onUpdate: @escaping (GardenDocsSnapshot) -> Void,
                       onError: @escaping (Error) -> Void) -> GardenSubscription {
        let token = UUID()
        gardenListeners[token] = onUpdate
        scheduleDelivery()
        return InMemoryGardenSubscription { [weak self] in self?.gardenListeners[token] = nil }
    }

    func observeWaterings(coupleId: String, onUpdate: @escaping (GardenWateringsSnapshot) -> Void,
                          onError: @escaping (Error) -> Void) -> GardenSubscription {
        let token = UUID()
        wateringListeners[token] = onUpdate
        scheduleDelivery()
        return InMemoryGardenSubscription { [weak self] in self?.wateringListeners[token] = nil }
    }

    /// The lab's partner takes the id the view model observes.
    func observePartner(partnerId: String, onUpdate: @escaping (GardenPartnerInfo) -> Void,
                        onError: @escaping (Error) -> Void) -> GardenSubscription {
        if !partnerId.isEmpty, partnerId != self.partnerId {
            users[partnerId] = users[self.partnerId] ?? Self.partnerDocument(name: "Sam", canGarden: true)
            self.partnerId = partnerId
        }
        let token = UUID()
        partnerListeners[token] = onUpdate
        scheduleDelivery()
        return InMemoryGardenSubscription { [weak self] in self?.partnerListeners[token] = nil }
    }

    func journalPage(coupleId: String, before: Date?, limit: Int) async throws -> [GardenWatering] {
        let all = decodedWaterings()
        guard let before else { return Array(all.prefix(limit)) }
        return Array(all.filter { ($0.wateredAt ?? .distantFuture) < before }.prefix(limit))
    }

    // MARK: Writes that may queue offline

    func announceCapability(userId: String) async {
        var user = users[userId] ?? [:]
        user[GardenField.capabilities] = [GardenField.capabilityGarden: GardenFeature.capabilityLevel]
        users[userId] = user
    }

    /// Shows the watering as pending at once, confirms it a moment later (or
    /// after 3 s with "Delay the next commit"), and refuses it like the
    /// rules do: no start date, or my turn within 11 h 50 min.
    func water(coupleId: String, by me: String, wateringId: String, note: String?,
               effect: GardenEffect) async throws {
        guard documents[GardenDocID.config] != nil else { throw GardenError.denied }
        if let last = GardenCodec.date(documents[GardenDocID.waterer(uid: me)]?[GardenField.lastWateredAt]),
           Date().timeIntervalSince(last) < GardenCadence.ruleCooldown {
            throw GardenError.denied
        }
        writeWatering(id: wateringId, by: me, note: note, effect: effect, at: Timestamp(date: Date()))
        pendingIds.formUnion([wateringId, GardenDocID.waterer(uid: me)])
        scheduleDelivery()
        let delay: TimeInterval = delayNextCommit ? 3 : 0.6
        delayNextCommit = false
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            self?.pendingIds.subtract([wateringId, GardenDocID.waterer(uid: me)])
            self?.scheduleDelivery()
        }
    }

    private func writeWatering(id: String, by uid: String, note: String?, effect: GardenEffect, at: Timestamp) {
        var water: [String: Any] = [
            GardenField.docType: GardenDocType.water.rawValue,
            GardenField.by: uid,
            GardenField.wateredAt: at,
            GardenField.effect: effect.rawValue
        ]
        if let note = GardenLimits.wateringNote.clean(note) {
            water[GardenField.note] = GardenLimits.wateringNote.truncate(note)
        }
        documents[id] = water
        documents[GardenDocID.waterer(uid: uid)] = [
            GardenField.docType: GardenDocType.waterer.rawValue,
            GardenField.lastWateredAt: at,
            GardenField.lastWateringId: id
        ]
    }

    func changeLook(coupleId: String, slot: GardenSlot, by me: String, look: GardenLook,
                    previous: GardenLook) async throws {
        try await waitIfDelayed()
        let id = GardenDocID.tree(slot)
        guard var tree = documents[id] else { throw GardenError.other }
        let now = Timestamp(date: Date())
        tree[GardenField.scene] = look.scene.rawValue
        tree[GardenField.species] = look.species.rawValue
        tree[GardenField.prevScene] = previous.scene.rawValue
        tree[GardenField.prevSpecies] = previous.species.rawValue
        tree[GardenField.lookBy] = me
        tree[GardenField.lookAt] = now
        tree[GardenField.updatedAt] = now
        documents[id] = tree
        scheduleDelivery()
    }

    // MARK: Proposals and consent

    func proposePlaceSeed(coupleId: String, by me: String, draft: GardenDraft) async throws -> String {
        guard let content = GardenCodec.content(from: draft) else { throw GardenError.invalid }
        guard let id = try await run(.proposePlaceSeed(me: me, content: content, newKey: UUID().uuidString)) else {
            throw GardenError.other
        }
        return id
    }

    func proposeOurTree(coupleId: String, by me: String, draft: GardenDraft) async throws {
        guard let content = GardenCodec.content(from: draft), content.startDay != nil else { throw GardenError.invalid }
        _ = try await run(.proposeOurTree(me: me, content: content, newKey: UUID().uuidString))
    }

    func editProposal(coupleId: String, id: String, by me: String, draft: GardenDraft,
                      seen: GardenProposalVersion) async throws {
        let isCounter: Bool
        switch draft.mode {
        case .counter: isCounter = true
        case .editSeed, .editChange: isCounter = false
        case .newPlaceTree, .ourTreeFirstPlanting, .changeTree: throw GardenError.invalid
        }
        guard let content = GardenCodec.content(from: draft) else { throw GardenError.invalid }
        _ = try await run(.editProposal(id: id, me: me, content: content, seen: seen, isCounter: isCounter))
    }

    func takeBack(coupleId: String, id: String, by me: String, key: String?) async throws {
        _ = try await run(.takeBack(id: id, me: me, key: key))
    }

    func letGo(coupleId: String, id: String) async throws {
        _ = try await run(.letGo(id: id))
    }

    func plant(coupleId: String, proposalId: String, by me: String, seen: GardenProposalVersion,
               proposerName: String?, alsoDelete: String?, key: String?) async throws -> GardenSlot {
        let result = try await run(.plant(id: proposalId, me: me, seen: seen, proposerName: proposerName,
                                          alsoDelete: alsoDelete, key: key))
        guard let slot = result.flatMap(GardenSlot.init(rawValue:)) else { throw GardenError.other }
        return slot
    }

    func proposeChange(coupleId: String, slot: GardenSlot, by me: String, draft: GardenDraft) async throws {
        guard let content = GardenCodec.content(from: draft) else { throw GardenError.invalid }
        _ = try await run(.proposeChange(slot: slot, me: me, content: content))
    }

    func proposeRest(coupleId: String, slot: GardenSlot, by me: String, note: String?) async throws {
        _ = try await run(.proposeRest(slot: slot, me: me, note: note))
    }

    func proposeStartDate(coupleId: String, by me: String, day: Date, note: String?) async throws {
        _ = try await run(.proposeStartDate(me: me, day: JourneyCalendarDay.storedMoment(forLocalDay: day), note: note))
    }

    func agree(coupleId: String, proposalId: String, by me: String, seen: GardenProposalVersion) async throws {
        _ = try await run(.agree(id: proposalId, me: me, seen: seen))
    }

    func recordOurTree(coupleId: String, by me: String) async throws {
        _ = try await run(.recordOurTree(me: me, newKey: UUID().uuidString))
    }

    func recordStartDate(coupleId: String, by me: String) async throws {
        _ = try await run(.recordStartDate(me: me, newKey: UUID().uuidString))
    }

    func deleteVoidProposal(coupleId: String, id: String) async throws {
        guard GardenDocID.isProposal(id) else { throw GardenError.denied }
        documents[id] = nil
        scheduleDelivery()
    }

    // MARK: Committing

    /// This user's transaction: honours "Delay the next commit", then plans
    /// against the store as it is THEN (a partner action may have landed).
    private func run(_ operation: GardenTransactions.Operation) async throws -> String? {
        try await waitIfDelayed()
        return try commit(operation)
    }

    private func waitIfDelayed() async throws {
        guard delayNextCommit else { return }
        delayNextCommit = false
        try await Task.sleep(for: .seconds(3))
    }

    private func commit(_ operation: GardenTransactions.Operation) throws -> String? {
        var reads: GardenTransactions.Reads = [:]
        for id in GardenTransactions.reads(for: operation) {
            if let data = documents[id] { reads[id] = data }
        }
        let stamps = GardenTransactions.Stamps(server: Timestamp(date: Date()), delete: deleteMarker)
        switch GardenTransactions.plan(operation, reads: reads, stamps: stamps) {
        case .failure(let error):
            throw error
        case .success(let plan):
            for write in plan.writes {
                switch write {
                case .set(let id, let data):
                    documents[id] = data
                case .update(let id, let fields):
                    guard var document = documents[id] else { continue }
                    for (field, value) in fields {
                        if (value as AnyObject) === deleteMarker {
                            document[field] = nil
                        } else {
                            document[field] = value
                        }
                    }
                    documents[id] = document
                case .delete(let id):
                    documents[id] = nil
                }
            }
            scheduleDelivery()
            return plan.result
        }
    }

    // MARK: Clock

    private func age(by delta: TimeInterval) {
        guard delta != 0 else { return }
        for (id, document) in documents {
            var aged = document
            for field in Self.serverTimeFields {
                if let time = GardenCodec.date(document[field]) {
                    aged[field] = Timestamp(date: time.addingTimeInterval(-delta))
                }
            }
            documents[id] = aged
        }
        scheduleDelivery()
    }

    // MARK: Delivery

    /// Listeners hear about changes on the next main-actor turn, coalesced,
    /// the way Firestore delivers snapshots after a write returns.
    private func scheduleDelivery() {
        guard !deliveryScheduled else { return }
        deliveryScheduled = true
        Task { [weak self] in self?.deliver() }
    }

    private func deliver() {
        deliveryScheduled = false
        let anchor = GardenCodec.anchor(data: documents[GardenDocID.config])
        anchorListeners.values.forEach { $0(anchor) }

        var snapshot = GardenDocsSnapshot(trees: [], proposals: [], waterers: [], isFromCache: false)
        for (id, data) in documents {
            let pending = pendingIds.contains(id)
            if let tree = GardenCodec.tree(id: id, data: data, hasPendingWrites: pending) {
                snapshot.trees.append(tree)
            } else if let proposal = GardenCodec.proposal(id: id, data: data, hasPendingWrites: pending) {
                snapshot.proposals.append(proposal)
            } else if let waterer = GardenCodec.waterer(id: id, data: data) {
                snapshot.waterers.append(waterer)
            }
        }
        gardenListeners.values.forEach { $0(snapshot) }

        let waterings = GardenWateringsSnapshot(waterings: Array(decodedWaterings().prefix(GardenLimits.wateringListen)),
                                                isFromCache: false)
        wateringListeners.values.forEach { $0(waterings) }

        let partner = GardenCodec.partner(data: users[partnerId])
        partnerListeners.values.forEach { $0(partner) }
    }

    /// Newest first.
    private func decodedWaterings() -> [GardenWatering] {
        documents
            .compactMap { GardenCodec.watering(id: $0.key, data: $0.value, hasPendingWrites: pendingIds.contains($0.key)) }
            .sorted { ($0.wateredAt ?? .distantPast) > ($1.wateredAt ?? .distantPast) }
    }
}

private final class InMemoryGardenSubscription: GardenSubscription {
    private var onCancel: (() -> Void)?

    init(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
    }

    func cancel() {
        onCancel?()
        onCancel = nil
    }
}

#endif
