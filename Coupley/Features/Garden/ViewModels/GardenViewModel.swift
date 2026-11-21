//
//  GardenViewModel.swift
//  Coupley
//
//  The garden's state, lifecycle and actions (spec I3). Owned by
//  ContentView as a @StateObject (Home's row and push routing need it too)
//  and handed to TimeTreeView as an @ObservedObject. Lifecycle like the
//  letters: built with ContentView's session, `rebind(session:)` on a couple
//  change, `start()` on appear and foreground (idempotent), `stop()` (every
//  live model's from the sign-out teardown, `stopAll()`); a released model
//  leaves no listener behind.
//
//  Derived values (hero, requests, Home line, journal, notices, ceremony
//  and replay candidates) live in GardenViewModel+Models.swift. Every string
//  comes from GardenCopy, GardenError.message or the contract's localized
//  properties.
//
//  The server decides everything that matters (watering times, the 12-hour
//  turn, plantings). This device's clock only decides how the garden LOOKS,
//  corrected by an offset estimated from its own acknowledged waterings.
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class GardenViewModel: ObservableObject {

    // MARK: State

    @Published private(set) var availability: GardenAvailability
    @Published private(set) var anchor: GardenAnchorState = .unresolved
    @Published private(set) var docs: GardenDocsSnapshot = .empty
    @Published private(set) var waterings: GardenWateringsSnapshot = .empty
    @Published private(set) var partner: GardenPartnerInfo = .unknown
    @Published private(set) var selectedSlot: GardenSlot = .our
    /// What the selected page plays now.
    @Published private(set) var playback: GardenEffectPlayback?
    @Published private(set) var ceremony: GardenCeremony?
    @Published private(set) var notices: [GardenNotice] = []
    @Published private(set) var errorMessage: String?
    /// The proposals a consent call is running for (each card is busy alone).
    @Published private(set) var busyProposalIds: Set<String> = []
    @Published private(set) var isWatering = false
    /// The 4-second line after watering (B3 row 3).
    @Published private(set) var afterWateringLine: String?
    @Published private(set) var now = Date()

    // MARK: Dependencies

    private(set) var session: UserSession
    private let service: GardenServicing
    private let connectivity: GardenConnectivityMonitoring
    private let chat: CoupleChatServicing
    let defaults = UserDefaults.standard

    // MARK: Listeners

    private var anchorSubscription: GardenSubscription?
    private var gardenSubscription: GardenSubscription?
    private var wateringsSubscription: GardenSubscription?
    private var partnerSubscription: GardenSubscription?
    private var probeTask: Task<Void, Never>?
    /// Quick re-listens after a failed listener (3, 6 and 9 s), reset by a
    /// healthy snapshot. Foreground retries too.
    private var listenRetries = 0
    private var listenRetryTask: Task<Void, Never>?
    private var hasLoadedCache = false
    /// The capability is announced once per launch per user, and only after
    /// a probe found the garden rules deployed.
    private static var announcedUsers: Set<String> = []
    /// Every live model (weakly: a model still goes with its view), so the
    /// sign-out teardown can stop them while Firebase still holds the
    /// credentials (`stopAll`).
    private static let liveModels = NSHashTable<GardenViewModel>.weakObjects()
    /// Recording Our tree is tried once per `start()`.
    private var recordAttempted = false
    private var deletingProposals: Set<String> = []

    // MARK: The backend's answers

    /// The real backend's answers (its rules answered, it switched the
    /// garden off, the clock offset) persist on this install, in
    /// GardenBackendState. An injected service's (the DEBUG lab, previews)
    /// last only as long as this model, so they never vouch for the real
    /// garden nor touch its reminders.
    private let remembersBackend: Bool
    private var injectedRulesVerified = false
    private var injectedSwitchedOff = false

    // MARK: Clock

    private var boundaryTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    /// The hero is on screen: the sky ticks each minute, replays and the
    /// proposer's ceremony may play.
    private(set) var isHeroVisible = false
    /// Server time minus device time, from this device's acknowledged
    /// waterings, clamped to ±GardenCadence.maxServerOffset.
    private var serverOffset: TimeInterval

    // MARK: Watering bookkeeping

    /// My waterings not yet confirmed by the server: id → when I tapped.
    private(set) var wateringTaps: [String: Date] = [:]
    /// Taps a snapshot has shown pending: if one vanishes, the server refused it.
    private var seenPending: Set<String> = []
    /// Waterings whose commit has not returned yet (≤ 2.5 s): a refusal
    /// then reaches its own catch (the error strip), never the later
    /// "didn't go through" notice, whichever of the two arrives first.
    private var inFlightWaterings: Set<String> = []
    /// Queued waterings the server refused later ("didn't go through").
    private(set) var refusedWaterings: [RefusedWatering] = []
    private var afterWateringTask: Task<Void, Never>?
    private var playbackTask: Task<Void, Never>?
    private var replayedIds: Set<String> = []
    /// A watering a push or Home's row asked to show.
    private var replayRequestId: String?
    /// The partner's watering whose status line is accent-tinted for 2 s.
    private(set) var newsWateringId: String?
    private var newsTask: Task<Void, Never>?

    // MARK: Consent bookkeeping

    /// Seeds I took back this session (never "set aside").
    private var takenBackKeys: Set<String> = []
    /// Since when the start date on the server is one this device has not
    /// seen agreed (a legacy edit, recorded or not); the notice waits 2 s so
    /// our own agreement, whose two documents reach the two listeners a
    /// moment apart, never flashes it.
    private(set) var startDateMismatchSince: Date?
    private var lastPageOrder: [GardenSlot] = []

    struct RefusedWatering: Equatable {
        let id: String
        let at: Date
    }

    init(session: UserSession,
         service: GardenServicing? = nil,
         connectivity: GardenConnectivityMonitoring? = nil,
         chat: CoupleChatServicing? = nil) {
        // A build without the garden reads no connectivity: no path monitor.
        let monitor: GardenConnectivityMonitoring
        if let connectivity {
            monitor = connectivity
        } else if GardenFeature.isEnabled {
            monitor = GardenConnectivity()
        } else {
            monitor = GardenNoConnectivityMonitor()
        }
        self.session = session
        self.connectivity = monitor
        self.remembersBackend = service == nil
        self.service = service ?? FirestoreGardenService(connectivity: monitor)
        self.chat = chat ?? FirestoreCoupleChatService()
        self.serverOffset = 0
        self.availability = .unpaired
        loadServerOffset()
        availability = startingAvailability
        restoreSelectedSlot()
        if GardenFeature.isEnabled { Self.liveModels.add(self) }
    }

    /// SessionStore's sign-out teardown (RootView): every garden stops
    /// listening before Firebase signs out, so no listener is refused (and
    /// retried) on the way out. A model released without it (unpairing, a
    /// theme change rebuilding ContentView) removes its listeners as it goes.
    static func stopAll() {
        for model in liveModels.allObjects { model.stop() }
    }

    deinit {
        // The listeners go with their subscriptions (FirestoreGardenSubscription);
        // the probe and the timers end here.
        probeTask?.cancel()
        listenRetryTask?.cancel()
        boundaryTask?.cancel()
        tickTask?.cancel()
        afterWateringTask?.cancel()
        playbackTask?.cancel()
        newsTask?.cancel()
    }

    // MARK: Lifecycle

    /// False unpaired and on `UserSession.demo` (its placeholder couple id
    /// would be denied by the rules), and in a build without the garden: such
    /// a build must never listen, nor announce the garden capability.
    var isAvailable: Bool { Self.isAvailable(session) }

    private static func isAvailable(_ session: UserSession) -> Bool {
        GardenFeature.isEnabled && session.isPaired && session.coupleId != UserSession.demo.coupleId
    }

    /// Before the probe answers: switched off if that was the backend's last
    /// answer (the pre-garden Journey shows at once, even offline), else
    /// loading.
    private var startingAvailability: GardenAvailability {
        guard isAvailable else { return .unpaired }
        return isSwitchedOff ? .disabledRemotely : .loading
    }

    /// A new couple (or user) starts from nothing; the same one only takes
    /// the new value.
    func rebind(session: UserSession) {
        let changed = session.userId != self.session.userId
            || session.coupleId != self.session.coupleId
            || session.partnerId != self.session.partnerId
        self.session = session
        guard changed else { return }
        stop()
        reset()
        loadServerOffset()
        availability = startingAvailability
        restoreSelectedSlot()
        start()
    }

    /// Probe, listeners, capability write, record Our tree, clock. Idempotent:
    /// on appear and foreground it re-probes (an unavailable or remotely
    /// disabled garden comes back this way) and keeps healthy listeners.
    func start() {
        guard isAvailable else {
            availability = .unpaired
            return
        }
        loadCacheIfNeeded()
        recordAttempted = false
        if anchorSubscription == nil { attachAnchor() }
        if probeTask == nil {
            let coupleId = session.coupleId
            let service = self.service
            // The probe can take 6 s: it must not keep a model ContentView
            // has let go of alive, nor attach listeners to it afterwards.
            probeTask = Task { [weak self] in
                let result = await service.probe()
                guard !Task.isCancelled, let self else { return }
                self.probeTask = nil
                guard self.session.coupleId == coupleId, self.isAvailable else { return }
                self.handleProbe(result)
            }
        }
        refreshClock()
    }

    func stop() {
        probeTask?.cancel()
        probeTask = nil
        anchorSubscription?.cancel()
        anchorSubscription = nil
        detachGardenListeners()
        listenRetryTask?.cancel()
        listenRetryTask = nil
        boundaryTask?.cancel()
        boundaryTask = nil
        tickTask?.cancel()
        tickTask = nil
    }

    /// Foreground, significantTimeChange, and every boundary the garden's
    /// copy or controls change at.
    func refreshClock() {
        reconcile()
    }

    /// The hero appeared: minute tick for the sky.
    func resumeTicking() {
        isHeroVisible = true
        startMinuteTick()
        reconcile()
    }

    func pauseTicking() {
        isHeroVisible = false
        tickTask?.cancel()
        tickTask = nil
    }

    /// Removes every `coupley.garden.*` key except those
    /// GardenDefaultsKey.isKeptOnPurge names (called when the app leaves .ready).
    static func purgeLocalCaches() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix(GardenDefaultsKey.prefix) && !GardenDefaultsKey.isKeptOnPurge(key) {
            defaults.removeObject(forKey: key)
        }
    }

    private func reset() {
        anchor = .unresolved
        docs = .empty
        waterings = .empty
        partner = .unknown
        playback = nil
        ceremony = nil
        notices = []
        errorMessage = nil
        busyProposalIds = []
        isWatering = false
        afterWateringLine = nil
        hasLoadedCache = false
        listenRetries = 0
        deletingProposals = []
        wateringTaps = [:]
        seenPending = []
        inFlightWaterings = []
        refusedWaterings = []
        replayedIds = []
        replayRequestId = nil
        newsWateringId = nil
        takenBackKeys = []
        startDateMismatchSince = nil
        lastPageOrder = []
        [afterWateringTask, playbackTask, newsTask].forEach { $0?.cancel() }
    }

    // MARK: Probe and listeners

    /// The backend's last definitive answer holds until the next one: an
    /// offline or slow probe (6 s) changes nothing, so a garden switched off
    /// remotely stays off and one whose rules never answered stays closed.
    private func handleProbe(_ result: GardenProbeResult) {
        switch result {
        case .enabled:
            rememberProbe(rulesVerified: true, switchedOff: false)
            attachGardenListeners()
            announceCapabilityOnce()
        case .offline:
            if isSwitchedOff {
                detachGardenListeners()
                availability = .disabledRemotely
            } else if rulesVerified {
                attachGardenListeners()
            } else if gardenSubscription == nil {
                availability = .unavailable(.neverOnline)
            }
        case .rulesMissing:
            rememberProbe(rulesVerified: false, switchedOff: isSwitchedOff)
            detachGardenListeners()
            availability = .unavailable(.rulesMissing)
        case .disabledRemotely:
            rememberProbe(rulesVerified: true, switchedOff: true)
            detachGardenListeners()
            availability = .disabledRemotely
        }
        reconcile()
    }

    // MARK: Remembering the backend's answers

    /// Its rules answered once: an offline start may show the cached garden.
    private var rulesVerified: Bool {
        get { remembersBackend ? GardenBackendState.rulesVerified : injectedRulesVerified }
        set {
            if remembersBackend { GardenBackendState.rulesVerified = newValue } else { injectedRulesVerified = newValue }
        }
    }

    /// Its last definitive answer was `appConfig/garden {enabled: false}`.
    private var isSwitchedOff: Bool {
        get { remembersBackend ? GardenBackendState.isSwitchedOff : injectedSwitchedOff }
        set {
            if remembersBackend { GardenBackendState.isSwitchedOff = newValue } else { injectedSwitchedOff = newValue }
        }
    }

    /// Keeps a definitive probe answer. When the remote switch flips, the
    /// garden's reminders are re-planned at once: cancelled while it is off
    /// (GardenReminderScheduler.remindersAllowed), back when it is on.
    private func rememberProbe(rulesVerified verified: Bool, switchedOff: Bool) {
        let switchFlipped = switchedOff != isSwitchedOff
        rulesVerified = verified
        isSwitchedOff = switchedOff
        if switchFlipped, remembersBackend {
            WidgetSyncService.shared.gardenRemindersPreferenceChanged()
        }
    }

    /// The real backend's clock offset; an injected service's starts at 0.
    /// Nothing is read for a build or session without a garden.
    private func loadServerOffset() {
        serverOffset = remembersBackend && isAvailable ? GardenBackendState.serverOffset : 0
    }

    /// The start date is listened to in every available state: even an
    /// unavailable garden must know whether to show the planting hero.
    private func attachAnchor() {
        anchorSubscription = service.observeAnchor(
            coupleId: session.coupleId,
            onUpdate: { [weak self] state in
                self?.anchor = state
                self?.reconcile()
            },
            onError: { [weak self] _ in self?.handleListenerFailure() })
    }

    private func attachGardenListeners() {
        if availability == .unavailable(.listenerFailed) { detachGardenListeners() }
        guard gardenSubscription == nil else {
            if availability != .ready { availability = .ready }
            return
        }
        if availability != .ready { availability = .loading }
        let coupleId = session.coupleId
        gardenSubscription = service.observeGarden(
            coupleId: coupleId,
            onUpdate: { [weak self] snapshot in self?.handleDocs(snapshot) },
            onError: { [weak self] _ in self?.handleListenerFailure() })
        wateringsSubscription = service.observeWaterings(
            coupleId: coupleId,
            onUpdate: { [weak self] snapshot in self?.handleWaterings(snapshot) },
            onError: { [weak self] _ in self?.handleListenerFailure() })
        partnerSubscription = service.observePartner(
            partnerId: session.partnerId,
            onUpdate: { [weak self] info in
                self?.partner = info
                self?.reconcile()
            },
            onError: { _ in })
    }

    private func detachGardenListeners() {
        gardenSubscription?.cancel()
        gardenSubscription = nil
        wateringsSubscription?.cancel()
        wateringsSubscription = nil
        partnerSubscription?.cancel()
        partnerSubscription = nil
    }

    /// Firestore ends a listener for good once it reports an error, so every
    /// garden listener is replaced: on foreground, and after 3, 6 and 9 s.
    /// A garden switched off remotely stays off (the pre-garden Journey);
    /// the next start listens again.
    private func handleListenerFailure() {
        detachGardenListeners()
        anchorSubscription?.cancel()
        anchorSubscription = nil
        guard availability != .disabledRemotely else {
            reconcile()
            return
        }
        availability = .unavailable(.listenerFailed)
        reconcile()
        guard listenRetries < 3, listenRetryTask == nil else { return }
        listenRetries += 1
        let delay = Double(listenRetries * 3)
        listenRetryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.listenRetryTask = nil
            if self.availability == .unavailable(.listenerFailed) { self.start() }
        }
    }

    private func handleDocs(_ snapshot: GardenDocsSnapshot) {
        docs = snapshot
        listenRetries = 0
        if availability == .loading { availability = .ready }
        if !snapshot.isFromCache { writeCache() }
        reconcile()
    }

    private func handleWaterings(_ snapshot: GardenWateringsSnapshot) {
        trackMyWaterings(in: snapshot)
        waterings = snapshot
        if !docs.isFromCache, !snapshot.isFromCache { writeCache() }
        reconcile()
    }

    private func announceCapabilityOnce() {
        let userId = session.userId
        guard !Self.announcedUsers.contains(userId) else { return }
        Self.announcedUsers.insert(userId)
        Task { await service.announceCapability(userId: userId) }
    }

    // MARK: Reconcile

    /// Runs after every snapshot and clock move: tidies the server (void
    /// proposals, Our tree's record), rebuilds notices, starts a ceremony or
    /// a replay when one is due, and aims the clock at the next boundary.
    private func reconcile() {
        now = serverNow()
        let serverDocs = !docs.isFromCache && availability == .ready
        if serverDocs {
            keepSelectionValid()
            trackMyOpenSeeds()
            deleteVoidProposals()
            recordOurTreeIfNeeded()
            forgetHomeDraftOnceHome()
        }
        trackStartDateChange(serverDocs: serverDocs)
        notices = noticeList()
        // Only from the server: the offline cache can still hold a tree that
        // has since gone, and its ceremony would play for a tree that the
        // next snapshot removes. The planter's own ceremony comes from the
        // planting itself (plantingCeremony), not from here.
        if ceremony == nil, isHeroVisible, serverDocs, let next = dueCeremony() {
            ceremony = next
        }
        if playback == nil, isHeroVisible, let watering = replayCandidate(requested: replayRequestId) {
            replay(watering)
        }
        scheduleBoundary()
    }

    func serverNow() -> Date {
        Date().addingTimeInterval(serverOffset)
    }

    /// A selected tree that went (it rested), or a remembered page whose
    /// tree is gone, gives way to its neighbour. A tree just planted here is
    /// selected before its snapshot arrives, so a slot never seen in the
    /// garden is left alone.
    private func keepSelectionValid() {
        guard anchor.isResolved else { return }
        let order = plantedTrees.map(\.slot)
        defer { lastPageOrder = order }
        guard !order.isEmpty, !order.contains(selectedSlot),
              lastPageOrder.isEmpty || lastPageOrder.contains(selectedSlot) else { return }
        let previous = lastPageOrder.firstIndex(of: selectedSlot).map { Array(lastPageOrder[..<$0]) } ?? []
        selectedSlot = previous.last(where: order.contains) ?? order[0]
        storeSelectedSlot()
    }

    private func restoreSelectedSlot() {
        guard isAvailable else { return }
        let raw = defaults.string(forKey: GardenDefaultsKey.selectedSlot(session.coupleId)) ?? ""
        selectedSlot = GardenSlot(rawValue: raw) ?? .our
    }

    private func storeSelectedSlot() {
        defaults.set(selectedSlot.rawValue, forKey: GardenDefaultsKey.selectedSlot(session.coupleId))
    }

    // MARK: Device cache

    private func loadCacheIfNeeded() {
        guard !hasLoadedCache else { return }
        hasLoadedCache = true
        guard docs == .empty,
              let data = defaults.data(forKey: GardenDefaultsKey.cache(session.coupleId)),
              let cached = GardenCodec.decodeCache(data) else { return }
        docs = GardenDocsSnapshot(trees: cached.trees, proposals: [], waterers: [], isFromCache: true)
        if waterings == .empty {
            waterings = GardenWateringsSnapshot(waterings: cached.waterings, isFromCache: true)
        }
    }

    /// Server snapshots only, so the offline first paint never shows a write
    /// the server has not accepted.
    private func writeCache() {
        guard let data = GardenCodec.cacheData(trees: docs.trees, waterings: waterings.waterings) else { return }
        defaults.set(data, forKey: GardenDefaultsKey.cache(session.coupleId))
    }

    // MARK: Server bookkeeping

    /// Our tree from an existing start date (A9): recorded by the first
    /// garden client online. The transaction does nothing if it exists.
    private func recordOurTreeIfNeeded() {
        guard !recordAttempted, anchor.isResolved, anchor.exists, connectivity.isOnline,
              !docs.trees.contains(where: { $0.isOurTree }) else { return }
        recordAttempted = true
        let coupleId = session.coupleId, me = session.userId
        Task { try? await service.recordOurTree(coupleId: coupleId, by: me) }
    }

    /// Void proposals are hidden at once and deleted by their proposer's
    /// client; the other client deletes one only after a day, so the
    /// proposer can keep a voided first seed's place and look (A10).
    private func deleteVoidProposals() {
        guard anchor.isResolved, connectivity.isOnline else { return }
        let me = session.userId, coupleId = session.coupleId
        for proposal in docs.proposals where isVoid(proposal) && !deletingProposals.contains(proposal.id) {
            let isMine = proposal.by == me
            let isStale = proposal.at.map { now.timeIntervalSince($0) > GardenCadence.homeRowFor } ?? true
            guard isMine || isStale else { continue }
            if isMine, proposal.id == GardenDocID.seedOurTree { keepHomeDraft(from: proposal) }
            deletingProposals.insert(proposal.id)
            // A refused delete is not retried until the next couple or launch.
            Task { [weak self] in
                guard (try? await self?.service.deleteVoidProposal(coupleId: coupleId, id: proposal.id)) != nil else { return }
                self?.deletingProposals.remove(proposal.id)
            }
        }
    }

    /// A first seed voided by a legacy planting: its place and look come
    /// back as the "Give your tree a home" invitation, prefilled.
    private func keepHomeDraft(from seed: GardenProposal) {
        let look = seed.look ?? .ourTreeDefault
        guard seed.place != nil || look != .ourTreeDefault else { return }
        let draft = HomeDraft(place: seed.place, look: look)
        if let data = try? JSONEncoder().encode(draft) {
            defaults.set(data, forKey: GardenDefaultsKey.homeDraft(session.coupleId))
        }
    }

    /// Our tree has a place: the home invitation's prefill (a place) is done.
    private func forgetHomeDraftOnceHome() {
        let key = GardenDefaultsKey.homeDraft(session.coupleId)
        guard docs.trees.first(where: { $0.isOurTree })?.place != nil, defaults.object(forKey: key) != nil else { return }
        defaults.removeObject(forKey: key)
    }

    /// My open plant proposals, keyed by seed key (ids are reused). One that
    /// leaves a server snapshot without becoming a tree, being countered or
    /// taken back by me, was let go by the partner: it stays recorded,
    /// flagged, until its notice is dismissed.
    private func trackMyOpenSeeds() {
        guard anchor.isResolved else { return }
        let me = session.userId
        let stored = openSeedRecords()
        var records = stored
        let mine = docs.proposals.filter { $0.kind == .plant && $0.by == me }
        for proposal in mine {
            records[proposal.key] = OpenSeedRecord(id: proposal.id, title: proposal.title ?? "",
                                                   preset: proposal.preset ?? .custom, setAside: false)
        }
        for (key, record) in records where !record.setAside && !mine.contains(where: { $0.key == key }) {
            let answered = docs.proposals.contains { $0.key == key }
            let planted = docs.trees.contains { $0.key == key }
            let voided = record.id == GardenDocID.seedOurTree && anchor.exists
            if answered || planted || voided || takenBackKeys.contains(key) {
                records[key] = nil
            } else {
                records[key]?.setAside = true
            }
        }
        if records != stored { storeOpenSeedRecords(records) }
    }

    /// A start date that changed outside an agreement with me (A10: in an
    /// older version of Coupley) is told once on each of my devices, even
    /// after another device has recorded it: the start date needs both of
    /// us, so the one who did not agree always hears of it. Each device
    /// keeps the start date it last saw agreed (`startDateSeen`): silently
    /// the first time the server answers (what the couple last agreed or
    /// recorded), and silently for an agreement I am part of or a recording
    /// I made. Anything else, or config and Our tree still disagreeing (not
    /// recorded yet), shows the notice after 2 s.
    private func trackStartDateChange(serverDocs: Bool) {
        guard serverDocs, anchor.isResolved, anchor.exists, let start = anchor.startDate else {
            startDateMismatchSince = nil
            return
        }
        let our = docs.trees.first(where: { $0.isOurTree })
        guard our?.hasPendingWrites != true else {
            startDateMismatchSince = nil
            return
        }
        let coupleId = session.coupleId
        if startDateSeen() == nil {
            markStartDateSeen(our?.agreedStartDay ?? start, coupleId: coupleId)
        }
        let unrecorded = our.map { !GardenCodec.sameInstant(start, $0.agreedStartDay) } ?? false
        if !unrecorded, let our, isAgreedWithMe(our), !GardenCodec.sameInstant(start, startDateSeen()) {
            markStartDateSeen(start, coupleId: coupleId)
        }
        guard unrecorded || !GardenCodec.sameInstant(start, startDateSeen()) else {
            startDateMismatchSince = nil
            return
        }
        if startDateMismatchSince == nil { startDateMismatchSince = Date() }
    }

    /// Our tree's latest record is one I took part in: an agreement (a
    /// start date, the planting, or a change that kept the agreed day), or
    /// a recording I made myself (an OK on another of my devices).
    private func isAgreedWithMe(_ our: GardenTree) -> Bool {
        let me = session.userId
        switch our.agreementKind {
        case .startDate, .plant, .change:
            return our.agreementBy.contains(me)
        case .recorded:
            return our.agreementBy == [me]
        }
    }

    /// The start date this device last saw agreed or acknowledged; nil
    /// before the server's first answer here.
    private func startDateSeen() -> Date? {
        let key = GardenDefaultsKey.startDateSeen(session.coupleId)
        guard defaults.object(forKey: key) != nil else { return nil }
        return Date(timeIntervalSince1970: defaults.double(forKey: key))
    }

    private func markStartDateSeen(_ day: Date?, coupleId: String) {
        guard let day else { return }
        defaults.set(day.timeIntervalSince1970, forKey: GardenDefaultsKey.startDateSeen(coupleId))
    }

    /// Confirms or rolls back my waterings. A confirmed one also tunes the
    /// server-offset estimate (only from a quick answer: a watering that sat
    /// queued offline says nothing about the clocks).
    private func trackMyWaterings(in snapshot: GardenWateringsSnapshot) {
        let byId = Dictionary(snapshot.waterings.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for (id, tap) in wateringTaps {
            if let watering = byId[id] {
                if watering.hasPendingWrites {
                    seenPending.insert(id)
                    continue
                }
                let answeredAfter = Date().timeIntervalSince(tap)
                if let at = watering.wateredAt, answeredAfter < 10 {
                    let midpoint = tap.addingTimeInterval(answeredAfter / 2)
                    let offset = min(GardenCadence.maxServerOffset,
                                     max(-GardenCadence.maxServerOffset, at.timeIntervalSince(midpoint)))
                    serverOffset = offset
                    if remembersBackend { GardenBackendState.serverOffset = offset }
                }
                wateringTaps[id] = nil
                seenPending.remove(id)
            } else if seenPending.contains(id), !inFlightWaterings.contains(id) {
                // Refused after its commit returned (it sat queued). One
                // refused while the commit is still out (the rollback can
                // arrive just before the commit's answer) is the catch's.
                wateringTaps[id] = nil
                seenPending.remove(id)
                refusedWaterings.append(RefusedWatering(id: id, at: tap))
            }
        }
    }

    // MARK: Clock

    private func startMinuteTick() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                let seconds = Date().timeIntervalSinceReferenceDate
                let untilMinute = 60 - seconds.truncatingRemainder(dividingBy: 60) + 0.05
                try? await Task.sleep(for: .seconds(untilMinute))
                // Ends with the model: a model released without stop() must
                // not leave this loop waking every minute for ever.
                guard !Task.isCancelled, let self else { return }
                self.refreshClock()
            }
        }
    }

    /// One one-shot timer aimed at the next moment any garden copy, control
    /// or overlay changes.
    private func scheduleBoundary() {
        boundaryTask?.cancel()
        let current = now
        guard let next = nextBoundaries().filter({ $0 > current.addingTimeInterval(0.25) }).min() else {
            boundaryTask = nil
            return
        }
        let delay = next.timeIntervalSince(current) + 0.25
        boundaryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.refreshClock()
        }
    }

    // MARK: Actions (each ends with errorMessage set on failure; consent actions return success)

    func select(_ slot: GardenSlot) {
        guard tree(slot) != nil, slot != selectedSlot else { return }
        selectedSlot = slot
        storeSelectedSlot()
    }

    /// Starts the effect at once, then writes. One tap waters every tree.
    func water(note: String?) {
        guard availability.allowsWrites, !isWatering else { return }
        switch waterAction {
        case .none:
            return
        case .locked(let until):
            errorMessage = GardenError.cooldown(until: until).message(partnerName: partnerName, now: now)
            return
        case .firstWater, .waterBack, .waterDue, .waterOptional:
            break
        }
        let me = session.userId, coupleId = session.coupleId
        let note = GardenLimits.wateringNote.clean(note).map(GardenLimits.wateringNote.truncate)
        let id = GardenDocID.newWatering()
        let confirmed = liveWaterings.filter { !$0.hasPendingWrites }
        let moment = GardenMoment.of(at: serverNow(), by: me, others: confirmed)
        let effect = GardenEffect.choose(wateringId: id, moment: moment, localHour: localHourAtSelectedTree(),
                                         previous: liveWaterings.first?.effect)
        let count = treeCount, name = partnerName, canGarden = partner.canGarden
        play(GardenEffectPlayback(wateringId: id, effect: effect, startTime: Date().timeIntervalSinceReferenceDate,
                                  isReplay: false, isFirstEver: moment == .first, byPartner: false, treeCount: count))
        wateringTaps[id] = Date()
        inFlightWaterings.insert(id)
        isWatering = true
        errorMessage = nil
        Task {
            do {
                try await service.water(coupleId: coupleId, by: me, wateringId: id, note: note, effect: effect)
                inFlightWaterings.remove(id)
                guard session.coupleId == coupleId else { return }
                isWatering = false
                showAfterWatering(GardenCopy.afterWatering(treeCount: count, partnerName: name, partnerCanGarden: canGarden))
            } catch {
                inFlightWaterings.remove(id)
                guard session.coupleId == coupleId else { return }
                isWatering = false
                // Refused within 2.5 s: the SDK rolls the local write back;
                // the strip says so, and no "didn't go through" notice follows.
                wateringTaps[id] = nil
                seenPending.remove(id)
                errorMessage = wateringErrorMessage(error)
            }
            reconcile()
        }
    }

    /// Routes by draft.mode.
    func propose(_ draft: GardenDraft) async -> Bool {
        let me = session.userId, coupleId = session.coupleId
        switch draft.mode {
        case .newPlaceTree:
            return await consent(busy: "new") {
                _ = try await self.service.proposePlaceSeed(coupleId: coupleId, by: me, draft: draft)
            }
        case .ourTreeFirstPlanting:
            return await consent(busy: GardenDocID.seedOurTree) {
                try await self.service.proposeOurTree(coupleId: coupleId, by: me, draft: draft)
            }
        case .editSeed(let id, let seen), .counter(let id, let seen), .editChange(let id, let seen):
            return await consent(busy: id) {
                try await self.service.editProposal(coupleId: coupleId, id: id, by: me, draft: draft, seen: seen)
            }
        case .changeTree(let slot):
            let sent = await consent(busy: GardenDocID.change(slot)) {
                try await self.service.proposeChange(coupleId: coupleId, slot: slot, by: me, draft: draft)
            }
            // The home invitation's prefill has done its job once Our tree's change is sent.
            if sent, slot.isOurTree { defaults.removeObject(forKey: GardenDefaultsKey.homeDraft(coupleId)) }
            return sent
        }
    }

    func takeBack(_ proposalId: String) async -> Bool {
        let me = session.userId, coupleId = session.coupleId
        let key = proposal(id: proposalId)?.key
        // Known before the commit lands, so the snapshot that drops the seed
        // never reads as the partner setting it aside.
        if let key { takenBackKeys.insert(key) }
        let done = await consent(busy: proposalId) {
            try await self.service.takeBack(coupleId: coupleId, id: proposalId, by: me, key: key)
        }
        if let key, !done { takenBackKeys.remove(key) }
        return done
    }

    /// Also "Keep it" for change, start date and rest.
    func letGo(_ proposalId: String) async -> Bool {
        let coupleId = session.coupleId
        return await consent(busy: proposalId) {
            try await self.service.letGo(coupleId: coupleId, id: proposalId)
        }
    }

    /// Plants exactly the version shown. The planter's ceremony starts as
    /// soon as the transaction commits; never before.
    func plant(_ proposalId: String, seen: GardenProposalVersion, alsoDelete: String?) async -> Bool {
        let me = session.userId, coupleId = session.coupleId
        let seed = proposal(id: proposalId)
        let proposerName = partner.displayName
        var planted: GardenSlot?
        let done = await consent(busy: proposalId) {
            planted = try await self.service.plant(coupleId: coupleId, proposalId: proposalId, by: me, seen: seen,
                                                   proposerName: proposerName, alsoDelete: alsoDelete, key: seed?.key)
        }
        guard done, let slot = planted else { return false }
        if let seed, !defaults.bool(forKey: GardenDefaultsKey.ceremonySeen(coupleId, key: seed.key)) {
            ceremony = plantingCeremony(for: seed, slot: slot)
        }
        selectedSlot = slot
        storeSelectedSlot()
        return true
    }

    /// Change, start date, rest.
    func agree(_ proposalId: String, seen: GardenProposalVersion) async -> Bool {
        let me = session.userId, coupleId = session.coupleId
        return await consent(busy: proposalId) {
            try await self.service.agree(coupleId: coupleId, proposalId: proposalId, by: me, seen: seen)
        }
    }

    func requestRest(_ slot: GardenSlot, note: String?) async -> Bool {
        guard !slot.isOurTree else { return false }
        let me = session.userId, coupleId = session.coupleId
        return await consent(busy: GardenDocID.rest(slot)) {
            try await self.service.proposeRest(coupleId: coupleId, slot: slot, by: me, note: note)
        }
    }

    /// `day` is the local day picked in the start-date sheet.
    func suggestStartDate(day: Date, note: String?) async -> Bool {
        let me = session.userId, coupleId = session.coupleId
        return await consent(busy: GardenDocID.startDate) {
            try await self.service.proposeStartDate(coupleId: coupleId, by: me, day: day, note: note)
        }
    }

    /// Either partner, any time, no consent. Queues offline. Returns whether
    /// the change was sent (or there was nothing to change); otherwise
    /// `errorMessage` says why.
    @discardableResult
    func changeLook(_ slot: GardenSlot, to look: GardenLook) async -> Bool {
        guard let current = tree(slot) else {
            errorMessage = GardenCopy.lookFailed
            return false
        }
        guard look != current.look else { return true }
        guard availability.allowsWrites else {
            errorMessage = GardenError.denied.message(partnerName: partnerName, now: now)
            return false
        }
        // Our tree drawn from the start date alone is recorded on the next
        // online start; until then it has no document to change.
        guard canChangeLook(slot) else {
            errorMessage = GardenCopy.lookFailed
            return false
        }
        let allowed = slot.isOurTree && !look.species.canBeOurTree ? GardenLook(scene: look.scene, species: .oak) : look
        do {
            try await service.changeLook(coupleId: session.coupleId, slot: slot, by: session.userId,
                                         look: allowed, previous: current.look)
            errorMessage = nil
            return true
        } catch {
            errorMessage = GardenCopy.lookFailed
            return false
        }
    }

    /// The tree's look can be changed now: the garden takes writes and the
    /// tree has its document (Our tree drawn from the start date alone has
    /// none until it is recorded).
    func canChangeLook(_ slot: GardenSlot) -> Bool {
        availability.allowsWrites && docs.trees.contains { $0.slot == slot }
    }

    /// "Change it back". An agreed change since the partner's restyle has
    /// replaced that look: reverting would undo what we both agreed.
    func undoLook(_ slot: GardenSlot) async {
        guard let tree = tree(slot), let previous = tree.previousLook, !lookChangeIsSuperseded(tree) else { return }
        await changeLook(slot, to: previous)
    }

    /// "Not now" on a seed: collapses its card for 3 days on this device.
    func snooze(_ proposalId: String) {
        guard let seed = proposal(id: proposalId), seed.kind == .plant else { return }
        let until = serverNow().addingTimeInterval(GardenCadence.snoozeFor)
        defaults.set(until.timeIntervalSince1970, forKey: GardenDefaultsKey.snoozed(session.coupleId, seedKey: seed.key))
        objectWillChange.send()
        reconcile()
    }

    /// "OK" records, "Change it back", "Water again", "Choose a place".
    func perform(_ notice: GardenNotice) async {
        switch notice.kind {
        case .seedSetAside:
            dismiss(notice)
        case .homeInvite:
            acceptHomeInvite()
        case .startDateChangedElsewhere(let storedDay):
            let coupleId = session.coupleId
            // Recorded only while Our tree still disagrees with it: another
            // device (or the partner) may have recorded it already.
            if let our = docs.trees.first(where: { $0.isOurTree }),
               !GardenCodec.sameInstant(our.agreedStartDay, storedDay) {
                do {
                    try await service.recordStartDate(coupleId: coupleId, by: session.userId)
                } catch {
                    let gardenError = FirestoreGardenService.gardenError(error)
                    errorMessage = gardenError == .offline
                        ? gardenError.message(partnerName: partnerName, now: now)
                        : GardenCopy.answerFailed
                    reconcile()
                    return
                }
            }
            markStartDateSeen(storedDay, coupleId: coupleId)
        case .lookChanged(let slot, _):
            markNoticeSeen(notice.id)
            await undoLook(slot)
        case .wateringRefused:
            dismiss(notice)
            water(note: nil)
        }
        reconcile()
    }

    func dismiss(_ notice: GardenNotice) {
        switch notice.kind {
        case .seedSetAside:
            var records = openSeedRecords()
            if let key = records.first(where: { "aside." + $0.key == notice.id })?.key { records[key] = nil }
            storeOpenSeedRecords(records)
        case .homeInvite:
            defaults.set(true, forKey: GardenDefaultsKey.inviteDismissed(session.coupleId))
            defaults.removeObject(forKey: GardenDefaultsKey.homeDraft(session.coupleId))
        case .wateringRefused:
            refusedWaterings.removeAll { "refused." + $0.id == notice.id }
        case .startDateChangedElsewhere(let storedDay):
            markStartDateSeen(storedDay, coupleId: session.coupleId)
        case .lookChanged:
            markNoticeSeen(notice.id)
        }
        reconcile()
    }

    /// "Choose a place" on "Give your tree a home": the invitation is
    /// answered (it does not come back, and Our tree's page offers "Add a
    /// place" from now on). Its prefilled place and look stay for the change
    /// flow it opens, until Our tree's change is sent or Our tree has a place.
    func acceptHomeInvite() {
        defaults.set(true, forKey: GardenDefaultsKey.inviteDismissed(session.coupleId))
        reconcile()
    }

    func dismissError() {
        errorMessage = nil
    }

    /// Selects the page and queues the replay (from a push, a reminder or
    /// Home's row).
    func reveal(_ focus: GardenFocus) {
        switch focus {
        case .overview:
            break
        case .tree(let slot):
            select(slot)
        case .proposal(let id):
            if let slot = proposal(id: id)?.targetSlot { select(slot) }
        case .watering(let id):
            replayRequestId = id
        }
        reconcile()
    }

    /// The partner's latest watering and its note have been seen (the note
    /// tag or the status well was tapped, or the journal opened): the tag
    /// comes down and Home's row goes. A replay marks the watering seen by
    /// itself; only this marks its note read.
    func markWateringSeen() {
        guard let latest = timeline.partnerLast else { return }
        defaults.set(latest.id, forKey: GardenDefaultsKey.seenWatering(session.coupleId))
        markNoticeSeen(Self.noteReadId(latest.id))
        objectWillChange.send()
        reconcile()
    }

    func acknowledgeCeremony() {
        guard let current = ceremony else { return }
        defaults.set(true, forKey: GardenDefaultsKey.ceremonySeen(session.coupleId, key: current.key))
        ceremony = nil
        reconcile()
    }

    /// Sends the chat line after the user's Send.
    func tellPartnerToUpdate() async -> Bool {
        do {
            try await chat.sendText(GardenCopy.tellPartnerMessage, coupleId: session.coupleId, senderId: session.userId)
            return true
        } catch {
            errorMessage = GardenError.other.message(partnerName: partnerName, now: now)
            return false
        }
    }

    // MARK: Action helpers

    /// Runs one consent call: its proposal is busy while it runs (another
    /// call for the same one is refused; calls for different ones overlap
    /// and each clears only its own), the typed error on failure.
    private func consent(busy id: String, _ body: () async throws -> Void) async -> Bool {
        guard availability.allowsWrites else {
            errorMessage = GardenError.denied.message(partnerName: partnerName, now: now)
            return false
        }
        guard !busyProposalIds.contains(id) else { return false }
        busyProposalIds.insert(id)
        errorMessage = nil
        defer { busyProposalIds.remove(id) }
        do {
            try await body()
            return true
        } catch {
            errorMessage = FirestoreGardenService.gardenError(error).message(partnerName: partnerName, now: now)
            return false
        }
    }

    /// A refusal within 2.5 s: my other device watered (the 12-hour turn),
    /// or anything else.
    private func wateringErrorMessage(_ error: Error) -> String {
        if FirestoreGardenService.gardenError(error) == .denied,
           let turn = docs.waterers.first(where: { $0.uid == session.userId })?.lastWateredAt,
           serverNow().timeIntervalSince(turn) < GardenCadence.cooldown {
            return GardenError.cooldown(until: turn.addingTimeInterval(GardenCadence.cooldown))
                .message(partnerName: partnerName, now: now)
        }
        return GardenCopy.wateringFailed
    }

    private func localHourAtSelectedTree() -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tree(selectedSlot)?.place?.timeZone ?? .current
        return calendar.component(.hour, from: Date())
    }

    private func showAfterWatering(_ line: String) {
        afterWateringLine = line
        afterWateringTask?.cancel()
        afterWateringTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.afterWateringLine = nil
        }
    }

    private func play(_ next: GardenEffectPlayback) {
        playback = next
        playbackTask?.cancel()
        playbackTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(next.totalDuration + 0.2))
            guard !Task.isCancelled, self?.playback?.id == next.id else { return }
            self?.playback = nil
            // A partner's watering that landed meanwhile replays now.
            self?.reconcile()
        }
    }

    /// The partner's watering, replayed with its stored effect. Seeing it on
    /// Journey marks it seen (Home's row goes); its status line is tinted
    /// for 2 s.
    private func replay(_ watering: GardenWatering) {
        replayRequestId = nil
        replayedIds.insert(watering.id)
        let others = liveWaterings.filter { $0.id != watering.id && !$0.hasPendingWrites }
        let isFirst = watering.wateredAt.map { GardenMoment.of(at: $0, by: watering.by, others: others) == .first } ?? false
        play(GardenEffectPlayback(wateringId: watering.id, effect: watering.effect,
                                  startTime: Date().timeIntervalSinceReferenceDate, isReplay: true,
                                  isFirstEver: isFirst, byPartner: true, treeCount: treeCount))
        if watering.id == timeline.partnerLast?.id {
            defaults.set(watering.id, forKey: GardenDefaultsKey.seenWatering(session.coupleId))
        }
        newsWateringId = watering.id
        newsTask?.cancel()
        newsTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.objectWillChange.send()
            self?.newsWateringId = nil
        }
    }

    func hasReplayed(_ wateringId: String) -> Bool {
        replayedIds.contains(wateringId)
    }

    func fetchJournalPage(before: Date?) async throws -> [GardenWatering] {
        try await service.journalPage(coupleId: session.coupleId, before: before, limit: GardenLimits.journalPage)
    }

    func markNoticeSeen(_ id: String) {
        defaults.set(true, forKey: GardenDefaultsKey.noticeSeen(session.coupleId, id: id))
    }

    static func noteReadId(_ wateringId: String) -> String { "note." + wateringId }

    // MARK: Device records

    /// One of my open seeds (or one let go, until its notice is dismissed).
    /// Stored under GardenDefaultsKey.myOpenSeeds as JSON, keyed by the
    /// seed's key because place-seed ids are reused.
    struct OpenSeedRecord: Codable, Equatable {
        var id: String
        var title: String
        var preset: GardenPreset
        var setAside: Bool
    }

    func openSeedRecords() -> [String: OpenSeedRecord] {
        guard let data = defaults.data(forKey: GardenDefaultsKey.myOpenSeeds(session.coupleId)),
              let records = try? JSONDecoder().decode([String: OpenSeedRecord].self, from: data) else { return [:] }
        return records
    }

    private func storeOpenSeedRecords(_ records: [String: OpenSeedRecord]) {
        let key = GardenDefaultsKey.myOpenSeeds(session.coupleId)
        guard !records.isEmpty, let data = try? JSONEncoder().encode(records) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }

    /// A voided first seed's place and look (GardenDefaultsKey.homeDraft).
    struct HomeDraft: Codable, Equatable {
        var place: GardenPlace?
        var look: GardenLook
    }

    func homeDraft() -> HomeDraft? {
        guard let data = defaults.data(forKey: GardenDefaultsKey.homeDraft(session.coupleId)) else { return nil }
        return try? JSONDecoder().decode(HomeDraft.self, from: data)
    }
}
