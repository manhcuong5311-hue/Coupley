//
//  GardenService.swift
//  Coupley
//
//  FirestoreGardenService: the garden's listeners, the watering batch,
//  confirmed writes and the consent-transaction wrapper (spec I4). Main-actor
//  isolated; transaction bodies are the nonisolated statics in
//  GardenTransactions, so nothing main-actor isolated runs on Firestore's
//  queue.
//
//  Every write either queues offline and confirms within 2.5 s (the watering
//  batch, a look change, the capability) or is a transaction that fails
//  fast offline and gives up after GardenCadence.transactionTimeout, so
//  nothing the garden does can hang.
//
//  Also GardenBackendState: what this install remembers about the backend
//  (its rules answered, it switched the garden off, the clock offset).
//

import Foundation
import FirebaseCore
import FirebaseFirestore

final class FirestoreGardenService: GardenServicing {

    private let db = Firestore.firestore()
    private let connectivity: GardenConnectivityMonitoring

    /// `connectivity` decides when consent transactions fail fast; the view
    /// model passes its own monitor so both agree.
    init(connectivity: GardenConnectivityMonitoring? = nil) {
        self.connectivity = connectivity ?? GardenConnectivity()
    }

    // MARK: Paths

    private func meta(_ coupleId: String) -> CollectionReference {
        db.collection(FirestorePath.timeTreeMeta(coupleId: coupleId))
    }

    private func user(_ uid: String) -> DocumentReference {
        db.collection(FirestorePath.users).document(uid)
    }

    // MARK: Reads

    /// `appConfig/garden` from the server. Its rule ships with the garden
    /// rules, so permission-denied means they are not deployed. A probe that
    /// cannot reach the server within a few seconds reports `.offline`.
    func probe() async -> GardenProbeResult {
        guard connectivity.isOnline else { return .offline }
        let reference = db.collection(GardenAppConfig.collection).document(GardenAppConfig.document)
        return await withCheckedContinuation { (continuation: CheckedContinuation<GardenProbeResult, Never>) in
            let once = GardenResumeOnce()
            reference.getDocument(source: .server) { snapshot, error in
                once.run {
                    if let error {
                        continuation.resume(returning: Self.isPermissionDenied(error) ? .rulesMissing : .offline)
                    } else if snapshot?.data()?[GardenAppConfig.enabledField] as? Bool == false {
                        continuation.resume(returning: .disabledRemotely)
                    } else {
                        continuation.resume(returning: .enabled)
                    }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.probeTimeout) {
                once.run { continuation.resume(returning: .offline) }
            }
        }
    }

    private static let probeTimeout: TimeInterval = 6

    /// Reports "no start date" only when the SERVER says so: a document
    /// missing from the local cache says nothing about the server (the
    /// anchor service's rule), so such snapshots are skipped.
    func observeAnchor(coupleId: String, onUpdate: @escaping (GardenAnchorState) -> Void,
                       onError: @escaping (Error) -> Void) -> GardenSubscription {
        let registration = meta(coupleId).document(GardenDocID.config)
            .addSnapshotListener(includeMetadataChanges: true) { snapshot, error in
                if let error {
                    onError(error)
                    return
                }
                guard let snapshot else { return }
                if !snapshot.exists, snapshot.metadata.isFromCache { return }
                onUpdate(GardenCodec.anchor(data: snapshot.data(with: .estimate)))
            }
        return FirestoreGardenSubscription(registration)
    }

    func observeGarden(coupleId: String, onUpdate: @escaping (GardenDocsSnapshot) -> Void,
                       onError: @escaping (Error) -> Void) -> GardenSubscription {
        let types = [GardenDocType.tree, .proposal, .waterer].map(\.rawValue)
        let registration = meta(coupleId).whereField(GardenField.docType, in: types)
            .addSnapshotListener(includeMetadataChanges: true) { snapshot, error in
                if let error {
                    onError(error)
                    return
                }
                guard let snapshot else { return }
                var result = GardenDocsSnapshot(trees: [], proposals: [], waterers: [],
                                                isFromCache: snapshot.metadata.isFromCache)
                for document in snapshot.documents {
                    let data = document.data(with: .estimate)
                    let pending = document.metadata.hasPendingWrites
                    if let tree = GardenCodec.tree(id: document.documentID, data: data, hasPendingWrites: pending) {
                        result.trees.append(tree)
                    } else if let proposal = GardenCodec.proposal(id: document.documentID, data: data, hasPendingWrites: pending) {
                        result.proposals.append(proposal)
                    } else if let waterer = GardenCodec.waterer(id: document.documentID, data: data) {
                        result.waterers.append(waterer)
                    }
                }
                onUpdate(result)
            }
        return FirestoreGardenSubscription(registration)
    }

    func observeWaterings(coupleId: String, onUpdate: @escaping (GardenWateringsSnapshot) -> Void,
                          onError: @escaping (Error) -> Void) -> GardenSubscription {
        let registration = meta(coupleId)
            .order(by: GardenField.wateredAt, descending: true)
            .limit(to: GardenLimits.wateringListen)
            .addSnapshotListener(includeMetadataChanges: true) { snapshot, error in
                if let error {
                    onError(error)
                    return
                }
                guard let snapshot else { return }
                let waterings = snapshot.documents.compactMap {
                    GardenCodec.watering(id: $0.documentID, data: $0.data(with: .estimate),
                                         hasPendingWrites: $0.metadata.hasPendingWrites)
                }
                onUpdate(GardenWateringsSnapshot(waterings: waterings, isFromCache: snapshot.metadata.isFromCache))
            }
        return FirestoreGardenSubscription(registration)
    }

    func observePartner(partnerId: String, onUpdate: @escaping (GardenPartnerInfo) -> Void,
                        onError: @escaping (Error) -> Void) -> GardenSubscription {
        let registration = user(partnerId).addSnapshotListener { snapshot, error in
            if let error {
                onError(error)
                return
            }
            guard let snapshot, snapshot.exists else { return }
            onUpdate(GardenCodec.partner(data: snapshot.data()))
        }
        return FirestoreGardenSubscription(registration)
    }

    /// From the server only: the local cache holds no more than the live
    /// listener's waterings, so a page answered from it offline would look
    /// like the end of the journal. Offline it throws.
    func journalPage(coupleId: String, before: Date?, limit: Int) async throws -> [GardenWatering] {
        var query = meta(coupleId).order(by: GardenField.wateredAt, descending: true)
        if let before { query = query.start(after: [Timestamp(date: before)]) }
        let snapshot = try await query.limit(to: limit).getDocuments(source: .server)
        return snapshot.documents.compactMap {
            GardenCodec.watering(id: $0.documentID, data: $0.data(with: .estimate),
                                 hasPendingWrites: $0.metadata.hasPendingWrites)
        }
    }

    // MARK: Writes that may queue offline

    /// Fire and forget: a capability that does not land is announced again
    /// on the next launch.
    func announceCapability(userId: String) async {
        let fields: [String: Any] = [
            GardenField.capabilities: [GardenField.capabilityGarden: GardenFeature.capabilityLevel]
        ]
        try? await user(userId).setDataConfirmed(fields, merge: true)
    }

    /// The watering and my turn in one batch, both stamped by the server. It
    /// queues offline; a refusal within 2.5 s throws (the SDK rolls the local
    /// write back).
    func water(coupleId: String, by me: String, wateringId: String, note: String?,
               effect: GardenEffect) async throws {
        let collection = meta(coupleId)
        var water: [String: Any] = [
            GardenField.docType: GardenDocType.water.rawValue,
            GardenField.by: me,
            GardenField.wateredAt: FieldValue.serverTimestamp(),
            GardenField.effect: effect.rawValue
        ]
        if let note = GardenLimits.wateringNote.clean(note) {
            water[GardenField.note] = GardenLimits.wateringNote.truncate(note)
        }
        let batch = db.batch()
        batch.setData(water, forDocument: collection.document(wateringId))
        batch.setData([
            GardenField.docType: GardenDocType.waterer.rawValue,
            GardenField.lastWateredAt: FieldValue.serverTimestamp(),
            GardenField.lastWateringId: wateringId
        ], forDocument: collection.document(GardenDocID.waterer(uid: me)))
        do {
            try await batch.commitConfirmed()
        } catch {
            throw Self.gardenError(error)
        }
    }

    /// A look changes directly (no consent); the previous look is kept for
    /// "Change it back". Queues offline: the rules accept it whenever it lands.
    func changeLook(coupleId: String, slot: GardenSlot, by me: String, look: GardenLook,
                    previous: GardenLook) async throws {
        do {
            try await meta(coupleId).document(GardenDocID.tree(slot)).updateDataConfirmed([
                GardenField.scene: look.scene.rawValue,
                GardenField.species: look.species.rawValue,
                GardenField.prevScene: previous.scene.rawValue,
                GardenField.prevSpecies: previous.species.rawValue,
                GardenField.lookBy: me,
                GardenField.lookAt: FieldValue.serverTimestamp(),
                GardenField.updatedAt: FieldValue.serverTimestamp()
            ])
        } catch {
            throw Self.gardenError(error)
        }
    }

    // MARK: Proposals and consent

    func proposePlaceSeed(coupleId: String, by me: String, draft: GardenDraft) async throws -> String {
        guard let content = GardenCodec.content(from: draft) else { throw GardenError.invalid }
        let result = try await transact(coupleId, .proposePlaceSeed(me: me, content: content, newKey: UUID().uuidString))
        guard let id = result else { throw GardenError.other }
        return id
    }

    func proposeOurTree(coupleId: String, by me: String, draft: GardenDraft) async throws {
        guard let content = GardenCodec.content(from: draft), content.startDay != nil else { throw GardenError.invalid }
        _ = try await transact(coupleId, .proposeOurTree(me: me, content: content, newKey: UUID().uuidString))
    }

    /// An edit of my own proposal or a counter to the partner's, by the
    /// draft's mode; every other kind of draft is refused.
    func editProposal(coupleId: String, id: String, by me: String, draft: GardenDraft,
                      seen: GardenProposalVersion) async throws {
        let isCounter: Bool
        switch draft.mode {
        case .counter: isCounter = true
        case .editSeed, .editChange: isCounter = false
        case .newPlaceTree, .ourTreeFirstPlanting, .changeTree: throw GardenError.invalid
        }
        guard let content = GardenCodec.content(from: draft) else { throw GardenError.invalid }
        _ = try await transact(coupleId, .editProposal(id: id, me: me, content: content, seen: seen, isCounter: isCounter))
    }

    /// `key` (the proposal's key as last seen) lets a take-back that lost the
    /// race to a planting say so ("Too late, Sam planted it just now").
    func takeBack(coupleId: String, id: String, by me: String, key: String?) async throws {
        _ = try await transact(coupleId, .takeBack(id: id, me: me, key: key))
    }

    func letGo(coupleId: String, id: String) async throws {
        _ = try await transact(coupleId, .letGo(id: id))
    }

    /// `key` (the seed's key as last seen) tells "already planted" from "gone".
    func plant(coupleId: String, proposalId: String, by me: String, seen: GardenProposalVersion,
               proposerName: String?, alsoDelete: String?, key: String?) async throws -> GardenSlot {
        let result = try await transact(coupleId, .plant(id: proposalId, me: me, seen: seen, proposerName: proposerName,
                                                          alsoDelete: alsoDelete, key: key))
        guard let slot = result.flatMap(GardenSlot.init(rawValue:)) else { throw GardenError.other }
        return slot
    }

    func proposeChange(coupleId: String, slot: GardenSlot, by me: String, draft: GardenDraft) async throws {
        guard let content = GardenCodec.content(from: draft) else { throw GardenError.invalid }
        _ = try await transact(coupleId, .proposeChange(slot: slot, me: me, content: content))
    }

    func proposeRest(coupleId: String, slot: GardenSlot, by me: String, note: String?) async throws {
        let clean = GardenLimits.seedNote.clean(note).map(GardenLimits.seedNote.truncate)
        _ = try await transact(coupleId, .proposeRest(slot: slot, me: me, note: clean))
    }

    /// `day` is the LOCAL day the user picked.
    func proposeStartDate(coupleId: String, by me: String, day: Date, note: String?) async throws {
        let clean = GardenLimits.seedNote.clean(note).map(GardenLimits.seedNote.truncate)
        let stored = JourneyCalendarDay.storedMoment(forLocalDay: day)
        _ = try await transact(coupleId, .proposeStartDate(me: me, day: stored, note: clean))
    }

    func agree(coupleId: String, proposalId: String, by me: String, seen: GardenProposalVersion) async throws {
        _ = try await transact(coupleId, .agree(id: proposalId, me: me, seen: seen))
    }

    func recordOurTree(coupleId: String, by me: String) async throws {
        _ = try await transact(coupleId, .recordOurTree(me: me, newKey: UUID().uuidString))
    }

    func recordStartDate(coupleId: String, by me: String) async throws {
        _ = try await transact(coupleId, .recordStartDate(me: me, newKey: UUID().uuidString))
    }

    /// Any member may delete a proposal; a void one is deleted plainly.
    func deleteVoidProposal(coupleId: String, id: String) async throws {
        do {
            try await meta(coupleId).document(id).deleteConfirmed()
        } catch {
            throw Self.gardenError(error)
        }
    }

    // MARK: The transaction wrapper

    /// Offline: `.offline` at once. Otherwise the transaction races
    /// GardenCadence.transactionTimeout; a timeout throws `.timedOut` (it may
    /// still commit; the listener then shows the truth). Returns the plan's
    /// result (a new seed id or the planted slot).
    private func transact(_ coupleId: String, _ operation: GardenTransactions.Operation) async throws -> String? {
        guard connectivity.isOnline else { throw GardenError.offline }
        let body = GardenTransactions.firestoreBody(for: operation, in: meta(coupleId))
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String?, Error>) in
            let once = GardenResumeOnce()
            db.runTransaction(body) { result, error in
                once.run {
                    if let error {
                        continuation.resume(throwing: Self.gardenError(error))
                    } else {
                        continuation.resume(returning: result as? String)
                    }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + GardenCadence.transactionTimeout) {
                once.run { continuation.resume(throwing: GardenError.timedOut) }
            }
        }
    }

    // MARK: Errors

    /// A GardenError thrown by a plan is itself; Firestore's codes map to
    /// what the user can do about them.
    nonisolated static func gardenError(_ error: Error) -> GardenError {
        if let garden = error as? GardenError { return garden }
        let nsError = error as NSError
        if let garden = GardenTransactions.gardenError(from: nsError) { return garden }
        guard nsError.domain == FirestoreErrorDomain else { return .other }
        switch FirestoreErrorCode.Code(rawValue: nsError.code) {
        case .permissionDenied?:
            return .denied
        case .unavailable?, .deadlineExceeded?:
            return .offline
        case .aborted?, .failedPrecondition?:
            return .changed
        default:
            return .other
        }
    }

    nonisolated private static func isPermissionDenied(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == FirestoreErrorDomain
            && nsError.code == FirestoreErrorCode.Code.permissionDenied.rawValue
    }
}

/// A Firestore listener behind the contract's subscription. Letting go of a
/// ListenerRegistration does not detach it, so releasing the subscription
/// removes the listener too: a view model released without stop() (sign-out,
/// unpairing, a theme change rebuilding ContentView) leaves nothing listening.
private final class FirestoreGardenSubscription: GardenSubscription {
    private let registration: ListenerRegistration

    init(_ registration: ListenerRegistration) {
        self.registration = registration
    }

    deinit {
        // remove() is thread-safe and idempotent (as FirestoreListenerBag relies on).
        registration.remove()
    }

    func cancel() {
        registration.remove()
    }
}

// MARK: - What this install remembers about the backend

/// What this install remembers about the backend the garden talks to:
/// whether its rules answered (an offline launch may then show the cached
/// garden), whether its last definitive answer switched the garden off (the
/// switch then holds through an offline or slow probe, and the garden's
/// reminders follow it), and the device clock's offset from its server.
/// Keyed by the Firebase project and the Firestore host, so a DEBUG emulator
/// run never vouches for production. Only the real backend is remembered:
/// the DEBUG lab and previews run on an injected service, and GardenViewModel
/// keeps their answers in memory.
enum GardenBackendState {

    /// "<project id>@<host>".
    static var backend: String {
        let db = Firestore.firestore()
        return (db.app.options.projectID ?? "") + "@" + db.settings.host
    }

    static var rulesVerified: Bool {
        get { UserDefaults.standard.bool(forKey: GardenDefaultsKey.rulesVerified(backend: backend)) }
        set { store(newValue, forKey: GardenDefaultsKey.rulesVerified(backend: backend)) }
    }

    /// `appConfig/garden {enabled: false}` was the last definitive answer.
    static var isSwitchedOff: Bool {
        get { UserDefaults.standard.bool(forKey: GardenDefaultsKey.remoteDisabled(backend: backend)) }
        set { store(newValue, forKey: GardenDefaultsKey.remoteDisabled(backend: backend)) }
    }

    static var serverOffset: TimeInterval {
        get { UserDefaults.standard.double(forKey: GardenDefaultsKey.serverOffset(backend: backend)) }
        set { UserDefaults.standard.set(newValue, forKey: GardenDefaultsKey.serverOffset(backend: backend)) }
    }

    /// A flag that is off is removed rather than stored as false.
    private static func store(_ isOn: Bool, forKey key: String) {
        if isOn {
            UserDefaults.standard.set(true, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

/// Lets exactly one of several racing callbacks through (an answer and its
/// timeout).
final class GardenResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func run(_ body: () -> Void) {
        lock.lock()
        let first = !done
        done = true
        lock.unlock()
        if first { body() }
    }
}
