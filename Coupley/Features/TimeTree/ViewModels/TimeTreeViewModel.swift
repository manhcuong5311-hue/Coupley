//
//  TimeTreeViewModel.swift
//  Coupley
//
//  Owns the state for the Journey tab:
//   - the relationship anchor (start date)
//   - the list of memories (past + capsule)
//   - a minute tick so countdowns and "days together" stay live
//   - detection of a recently reached crown for the celebration overlay
//
//  Lifecycle: `startListening()` attaches the Firestore listeners once and
//  they stay attached while the tab is hidden; only the minute tick pauses
//  (`pauseTicking()` / `resumeTicking()`). `stopListening()` is for a retry
//  and for teardown.
//
//  Reminders are NOT scheduled here. WidgetSyncService stays bound for the
//  whole paired session and owns capsule and crown reminders, so they stay
//  right even when Journey is never opened.
//
//  Local caches in UserDefaults give an offline-first first paint, like the
//  Anniversary feature. A sealed capsule is cached without its note,
//  emotions, attribution or photo.
//

import Foundation
import FirebaseFirestore
import Combine
import UIKit

// MARK: - View Model

@MainActor
final class TimeTreeViewModel: ObservableObject {

    // MARK: - Published state

    @Published private(set) var anchor: RelationshipAnchor?
    @Published private(set) var memories: [TimeMemory] = []
    @Published private(set) var isListening: Bool = false
    /// `false` until the first Firestore snapshot (or a non-empty cache) arrives.
    /// Used by the view to show a loading indicator instead of the empty state
    /// during the initial fetch window. Pausing never resets it.
    @Published private(set) var hasReceivedFirstUpdate: Bool = false
    /// True once Journey's own memories listener has answered, not just the
    /// device cache, which can predate a capsule the partner sealed since
    /// (a capsule reminder tapped on a cold launch waits for this).
    @Published private(set) var hasReceivedListenerUpdate: Bool = false
    @Published private(set) var errorMessage: String?
    @Published var isSavingMemory: Bool = false
    @Published var isUploadingPhoto: Bool = false
    @Published var isSavingAnchor: Bool = false

    /// Ticked every minute (on the minute) so day-level countdowns advance at
    /// midnight while Journey is on screen.
    @Published private(set) var now: Date = Date()

    /// The crown milestone to celebrate now. The view observes this and runs
    /// the celebration overlay when set; the overlay calls `acknowledgeCrown`
    /// to clear it.
    @Published var pendingCrownCelebration: CrownMilestone?

    /// True once the start date is known: there is one (from the server, its
    /// offline cache or this device's cache), or the SERVER said there is
    /// none. While false, `anchor == nil` means "not loaded yet", not "no
    /// start date" (a new phone opened offline), so a view can hold back
    /// "Set the day it started"; `setAnchor` refuses a first start date then.
    @Published private(set) var hasResolvedAnchor: Bool = false

    // MARK: - Error state

    /// True while `errorMessage` holds a failure from something the user did
    /// (a save, a photo upload, the start date) rather than from a listener.
    /// Such a message stays until the user dismisses it or acts again.
    private var errorIsFromUserAction = false
    /// A listener has failed and stays dead until `retryAfterError()`. Its
    /// message comes back once a user-action message over it is dismissed.
    private var listenerFailed = false

    /// The error is a listener failure that `retryAfterError()` can fix (show
    /// "Try again"); a user-action failure is only dismissed.
    var errorIsRetryable: Bool { errorMessage != nil && !errorIsFromUserAction }

    /// Shown as-is in Journey's error strip, so already localized.
    private enum Copy {
        static var listenerFailed: String {
            String(localized: "Couldn't load your Journey. Check your connection and try again.",
                   comment: "Journey error: the memories or start date failed to load")
        }
        static var saveFailed: String {
            String(localized: "Couldn't save that. Check your connection and try again.",
                   comment: "Journey error: saving or deleting a memory failed")
        }
        static var photoFailed: String {
            String(localized: "Couldn't upload the photo, so the memory was saved without it.",
                   comment: "Journey error: the memory was saved but its photo upload failed")
        }
        static var startDateFailed: String {
            String(localized: "Couldn't save the start date. Try again.",
                   comment: "Journey error: saving the relationship start date failed")
        }
        static var memoryDeleted: String {
            String(localized: "That memory was deleted, so your changes weren't saved.",
                   comment: "Journey error: the memory being edited was deleted meanwhile")
        }
    }

    // MARK: - Dependencies

    private let session: UserSession
    private let memoryService: TimeTreeMemoryService
    private let anchorService: TimeTreeAnchorService
    private let storageService: TimeTreeStorageService

    nonisolated(unsafe) private var memoryListener: ListenerRegistration?
    nonisolated(unsafe) private var anchorListener: ListenerRegistration?
    /// Bumped on every attach and stop, so an event a removed listener had
    /// already queued is dropped instead of landing after a retry.
    private var listenerGeneration = 0
    private var tickTimer: Timer?
    /// A crown asked for (reminder tap) before the start date had loaded.
    private var requestedCrownId: String?
    /// Memories shown from the device cache with their sealed contents
    /// blanked, until the listener delivers the real ones. Saving one of
    /// those copies would write the blanks back, so it is refused, and
    /// `canEdit` offers no editor for them. Published so Edit and
    /// "Add photo" appear the moment the real copies arrive.
    @Published private var redactedCacheIds: Set<String> = []

    // MARK: - Init

    init(
        session: UserSession,
        memoryService: TimeTreeMemoryService? = nil,
        anchorService: TimeTreeAnchorService? = nil,
        storageService: TimeTreeStorageService? = nil
    ) {
        self.session = session
        self.memoryService  = memoryService  ?? FirestoreTimeTreeMemoryService()
        self.anchorService  = anchorService  ?? FirestoreTimeTreeAnchorService()
        self.storageService = storageService ?? TimeTreeStorageService()
    }

    deinit {
        memoryListener?.remove()
        anchorListener?.remove()
        tickTimer?.invalidate()
    }

    /// This device's user, for "only the author can edit a sealed capsule"
    /// and "set by you".
    var currentUserId: String { session.userId }

    // MARK: - Lifecycle

    /// Attaches the listeners (once: calling it again is a no-op while they
    /// are attached) and makes sure the minute tick runs.
    func startListening() {
        guard session.isPaired else { return }
        if memoryListener == nil || anchorListener == nil {
            attachListeners()
        }
        if tickTimer == nil {
            resumeTicking()
        }
    }

    /// Journey left the screen: stop the minute tick only. The listeners stay
    /// attached, so the data is current when the tab comes back.
    func pauseTicking() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    /// Journey is back on screen: catch the clock up, restart the minute
    /// tick and look for a crown to celebrate.
    func resumeTicking() {
        now = Date()
        startTicking()
        evaluateCrownCelebration()
    }

    /// Removes the listeners and the tick. For a retry and for teardown.
    func stopListening() {
        listenerGeneration += 1
        memoryListener?.remove(); memoryListener = nil
        anchorListener?.remove(); anchorListener = nil
        isListening = false
        pauseTicking()
    }

    /// Called when the app becomes active: catch the clock up and look for a
    /// crown reached while the app was away.
    func refresh() {
        now = Date()
        evaluateCrownCelebration()
    }

    // MARK: - Errors

    func dismissError() {
        if errorIsFromUserAction && listenerFailed {
            // The listener is still dead: put its message (and "Try again") back.
            errorIsFromUserAction = false
            errorMessage = Copy.listenerFailed
        } else {
            errorIsFromUserAction = false
            listenerFailed = false
            errorMessage = nil
        }
    }

    func retryAfterError() {
        dismissError()
        stopListening()
        startListening()
    }

    // MARK: - Anchor

    /// Saves the day the relationship started. `startDay` is the day the
    /// user picked (any time on it); it is stored as that calendar day, so
    /// both partners count from the same day. Editing keeps who first set it
    /// and when; only the start date and `updatedAt` change.
    func setAnchor(startDay: Date, myName: String?) async {
        guard session.isPaired else { return }
        isSavingAnchor = true
        defer { isSavingAnchor = false }
        beginUserAction()

        let startDate = JourneyCalendarDay.storedMoment(forLocalDay: startDay)
        let next: RelationshipAnchor
        if var existing = anchor {
            existing.startDate = startDate
            existing.updatedAt = Date()
            next = existing
        } else if !hasResolvedAnchor {
            // Nobody has said yet whether the partner already set a start
            // date (offline on a new phone). A first one written now would
            // replace theirs on reconnect.
            failUserAction(Copy.startDateFailed)
            return
        } else {
            let moment = Date()
            next = RelationshipAnchor(
                startDate: startDate,
                setBy: session.userId,
                setByName: myName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                setAt: moment,
                updatedAt: moment
            )
        }

        do {
            try await anchorService.setAnchor(coupleId: session.coupleId, anchor: next)
        } catch {
            failUserAction(Copy.startDateFailed)
        }
    }

    // MARK: - Memory CRUD

    func createMemory(
        kind: MemoryKind,
        title: String,
        date: Date,
        note: String?,
        emotions: [MemoryEmotion],
        attribution: String?,
        anniversaryId: String? = nil,
        unlockDate: Date? = nil,
        photo: UIImage? = nil
    ) async {
        guard session.isPaired else { return }
        isSavingMemory = true
        defer { isSavingMemory = false }
        beginUserAction()

        let memoryId = UUID().uuidString
        var uploaded: UploadedMemoryPhoto?
        if let photo {
            uploaded = await uploadPhoto(photo, memoryId: memoryId)
        }

        let memory = TimeMemory(
            id: memoryId,
            kind: kind,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            date: date,
            note: note?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            photoURL: uploaded?.url,
            emotions: emotions,
            attribution: attribution?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            anniversaryId: anniversaryId,
            unlockDate: unlockDate,
            createdBy: session.userId
        )

        do {
            try await memoryService.create(coupleId: session.coupleId, memory: memory)
        } catch {
            // Nothing points at the new file: don't leave it behind.
            if let uploaded { discardPhoto(url: uploaded.url, memoryId: memoryId) }
            failUserAction(Copy.saveFailed)
            return
        }

        // Was `try?` once: a failed upload saved the memory silently without
        // its picture. Reported only now that the memory itself is saved.
        if photo != nil && uploaded == nil {
            failUserAction(Copy.photoFailed)
        }
        AdsManager.shared.recordAction()
    }

    func updateMemory(
        _ memory: TimeMemory,
        kind: MemoryKind,
        title: String,
        date: Date,
        note: String?,
        emotions: [MemoryEmotion],
        attribution: String?,
        anniversaryId: String?,
        unlockDate: Date?,
        photo: UIImage? = nil,
        clearPhoto: Bool = false
    ) async {
        guard session.isPaired else { return }
        isSavingMemory = true
        defer { isSavingMemory = false }
        beginUserAction()

        // The listener's copy says what the document holds right now. Gone
        // from the list means it was deleted (on the other phone, while an
        // editor was open): writing it back would re-create it. Checked
        // before any upload, so no orphaned photo is left behind.
        guard let live = self.memory(id: memory.id) else {
            failUserAction(Copy.memoryDeleted)
            return
        }

        // A sealed capsule belongs to its author until it opens. The editor
        // isn't offered to anyone else; this is the backstop. And a cached
        // copy with its contents blanked must never be written back.
        guard !live.isLocked(at: Date()) || live.createdBy == session.userId,
              !redactedCacheIds.contains(memory.id) else {
            failUserAction(Copy.saveFailed)
            return
        }

        // `id` and `createdBy` travel unchanged: the rules require both.
        var updated = memory
        updated.kind = kind
        updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.date = date
        updated.note = note?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        updated.emotions = emotions
        updated.attribution = attribution?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        updated.anniversaryId = anniversaryId
        updated.unlockDate = unlockDate
        updated.updatedAt = Date()
        // An edit that doesn't touch the photo keeps the current one, even
        // if the partner replaced it while this editor was open.
        updated.photoURL = live.photoURL

        // A new photo is uploaded first, to its own file; the old file is
        // removed only once the document no longer points at it.
        var uploaded: UploadedMemoryPhoto?
        if let photo {
            uploaded = await uploadPhoto(photo, memoryId: memory.id)
            if let uploaded { updated.photoURL = uploaded.url }
        } else if clearPhoto {
            updated.photoURL = nil
        }

        do {
            try await memoryService.update(coupleId: session.coupleId, memory: updated)
        } catch {
            if let uploaded { discardPhoto(url: uploaded.url, memoryId: memory.id) }
            // Deleted on the other phone while this save was in flight: the
            // update answers NOT_FOUND (PERMISSION_DENIED under the hardened
            // rules, which see no document). Nothing to retry, so don't
            // blame the connection.
            let ns = error as NSError
            let gone = ns.domain == FirestoreErrorDomain
                && (ns.code == FirestoreErrorCode.notFound.rawValue
                    || (ns.code == FirestoreErrorCode.permissionDenied.rawValue
                        && self.memory(id: memory.id) == nil))
            failUserAction(gone ? Copy.memoryDeleted : Copy.saveFailed)
            return
        }

        if let previous = live.photoURL, previous != updated.photoURL {
            discardPhoto(url: previous, memoryId: memory.id)
        }
        if photo != nil && uploaded == nil {
            failUserAction(Copy.photoFailed)
        }
    }

    func deleteMemory(_ memory: TimeMemory) async {
        guard session.isPaired else { return }
        beginUserAction()
        let photoURLs = Set([memory.photoURL, self.memory(id: memory.id)?.photoURL].compactMap { $0 })
        do {
            try await memoryService.delete(coupleId: session.coupleId, id: memory.id)
        } catch {
            failUserAction(Copy.saveFailed)
            return
        }
        // The document is gone; now its files (by URL, plus the legacy path).
        for url in photoURLs {
            discardPhoto(url: url, memoryId: memory.id)
        }
        discardLegacyPhoto(memoryId: memory.id)
    }

    // MARK: - Crown celebration

    /// Shows this crown's celebration (a crown reminder was tapped) if the
    /// couple has reached it, even if it was celebrated on this device before.
    func presentCrown(milestoneId: String) {
        guard let milestone = CrownMilestone.milestone(id: milestoneId) else { return }
        guard let anchor else {
            // The start date hasn't loaded yet; finish when it arrives.
            requestedCrownId = milestoneId
            return
        }
        requestedCrownId = nil
        guard milestone.isReached(anchor: anchor.startDate, now: Date()) else { return }
        pendingCrownCelebration = milestone
    }

    func acknowledgeCrown() {
        guard let milestone = pendingCrownCelebration else { return }
        markCrownAsCelebrated(milestone)
        pendingCrownCelebration = nil
    }

    // MARK: - Local caches

    private static let memoryCachePrefix = "coupley.memories."
    private static let anchorCachePrefix = "coupley.anchor."

    /// Removes every couple's cached memories and start date from this
    /// device (sign-out, disconnect, account deletion). The per-device
    /// "crown celebrated" flags stay.
    static func purgeLocalCaches() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix(memoryCachePrefix) || key.hasPrefix(anchorCachePrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - Private — errors

    /// A new user action replaces the previous user-action message; a dead
    /// listener's message stays, because the listener is still dead.
    private func beginUserAction() {
        guard errorIsFromUserAction else { return }
        errorIsFromUserAction = false
        errorMessage = listenerFailed ? Copy.listenerFailed : nil
    }

    private func failUserAction(_ message: String) {
        errorIsFromUserAction = true
        errorMessage = message
    }

    private func handleListenerFailure() {
        listenerFailed = true
        // A message about what the user just did is not overwritten; this
        // one comes back when that one is dismissed.
        guard !errorIsFromUserAction else { return }
        errorMessage = Copy.listenerFailed
    }

    // MARK: - Private — photos

    /// Uploads `photo` to its own file and keeps the uploaded JPEG bytes in
    /// the image cache, so this phone never downloads what it just sent and
    /// nothing is re-encoded on the main thread. nil when the upload failed.
    private func uploadPhoto(_ photo: UIImage, memoryId: String) async -> UploadedMemoryPhoto? {
        isUploadingPhoto = true
        defer { isUploadingPhoto = false }
        do {
            let uploaded = try await storageService.uploadPhoto(
                photo,
                coupleId: session.coupleId,
                memoryId: memoryId
            )
            if let url = URL(string: uploaded.url) {
                ImageCache.shared.store(data: uploaded.jpegData, for: url)
            }
            return uploaded
        } catch {
            return nil
        }
    }

    /// Deletes a photo file in the background: nothing waits on Storage,
    /// which can retry for minutes offline.
    private func discardPhoto(url: String, memoryId: String) {
        let storage = storageService
        let coupleId = session.coupleId
        Task { await storage.deletePhoto(url: url, coupleId: coupleId, memoryId: memoryId) }
    }

    /// The .../photo.jpg that earlier versions wrote for every memory.
    private func discardLegacyPhoto(memoryId: String) {
        let storage = storageService
        let coupleId = session.coupleId
        Task { await storage.deletePhoto(coupleId: coupleId, memoryId: memoryId) }
    }

    // MARK: - Private — remote sync

    private func attachListeners() {
        memoryListener?.remove(); memoryListener = nil
        anchorListener?.remove(); anchorListener = nil
        listenerGeneration += 1
        let generation = listenerGeneration

        // A fresh attach: a previous listener failure is over.
        listenerFailed = false
        if !errorIsFromUserAction && errorMessage != nil { errorMessage = nil }

        loadCacheIfNeeded()
        isListening = true

        memoryListener = memoryService.observe(
            coupleId: session.coupleId,
            onUpdate: { [weak self] items in
                Task { @MainActor [weak self] in
                    guard let self, self.listenerGeneration == generation else { return }
                    self.handleRemoteMemoriesUpdate(items)
                }
            },
            onError: { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.listenerGeneration == generation else { return }
                    self.handleListenerFailure()
                }
            }
        )

        anchorListener = anchorService.observe(
            coupleId: session.coupleId,
            onUpdate: { [weak self] anchor in
                Task { @MainActor [weak self] in
                    guard let self, self.listenerGeneration == generation else { return }
                    self.handleRemoteAnchorUpdate(anchor)
                }
            },
            onError: { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.listenerGeneration == generation else { return }
                    self.handleListenerFailure()
                }
            }
        )
    }

    private func handleRemoteMemoriesUpdate(_ items: [TimeMemory]) {
        let shown = Self.shownMemories(items)
        if memories != shown { memories = shown }
        redactedCacheIds = []
        if !hasReceivedFirstUpdate { hasReceivedFirstUpdate = true }
        if !hasReceivedListenerUpdate { hasReceivedListenerUpdate = true }
        saveMemoriesCache(items)
    }

    /// The memories as drawn. Only screenshot builds (`-coupleyDemoData`,
    /// Debug) retitle them; the cache always keeps the real ones.
    private static func shownMemories(_ items: [TimeMemory]) -> [TimeMemory] {
        #if DEBUG
        if let demo = DemoContent.current { return demo.memories(items) }
        #endif
        return items
    }

    /// `nil` here means the server has no start date (the service never
    /// reports a cache miss as nil).
    private func handleRemoteAnchorUpdate(_ anchor: RelationshipAnchor?) {
        if self.anchor != anchor { self.anchor = anchor }
        if !hasResolvedAnchor { hasResolvedAnchor = true }
        saveAnchorCache(anchor)
        if anchor == nil {
            requestedCrownId = nil
        } else {
            fulfilCrownRequest()
        }
        evaluateCrownCelebration()
    }

    private func fulfilCrownRequest() {
        guard let requested = requestedCrownId, anchor != nil else { return }
        presentCrown(milestoneId: requested)
    }

    /// Takes the most recently reached crown (by date). If it was reached in
    /// the last 3 days and hasn't been celebrated on this device yet,
    /// surfaces it for the overlay. Older crowns never pop up again.
    private func evaluateCrownCelebration() {
        guard pendingCrownCelebration == nil, let anchor else { return }
        guard let latest = CrownMilestone.reached(after: anchor.startDate, now: now).last,
              latest.isRecentlyReached(anchor: anchor.startDate, now: now, withinDays: 3),
              !hasCelebrated(latest)
        else { return }
        pendingCrownCelebration = latest
    }

    // MARK: - Tick timer

    /// Fires on each minute boundary, also while a scroll view is tracking.
    private func startTicking() {
        tickTimer?.invalidate()
        let firstFire = Calendar.current.nextDate(
            after: Date(),
            matching: DateComponents(second: 0),
            matchingPolicy: .nextTime
        ) ?? Date().addingTimeInterval(60)
        let timer = Timer(fire: firstFire, interval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.now = Date()
                self?.evaluateCrownCelebration()
            }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    // MARK: - Cache (UserDefaults)

    private var memoryCacheKey: String { Self.memoryCachePrefix + session.coupleId }
    private var anchorCacheKey: String { Self.anchorCachePrefix + session.coupleId }

    /// Fills in only what isn't already in memory: after a retry, the live
    /// copies are fresher than the cache (and not redacted).
    private func loadCacheIfNeeded() {
        let defaults = UserDefaults.standard
        if memories.isEmpty,
           let data = defaults.data(forKey: memoryCacheKey),
           let items = try? JSONDecoder().decode([MemoryDTO].self, from: data),
           !items.isEmpty {
            memories = Self.shownMemories(items.map(\.memory))
            redactedCacheIds = Set(items.filter { $0.redacted == true }.map(\.id))
            hasReceivedFirstUpdate = true
        }
        if anchor == nil,
           let data = defaults.data(forKey: anchorCacheKey),
           let dto = try? JSONDecoder().decode(AnchorDTO.self, from: data) {
            anchor = dto.anchor
            hasResolvedAnchor = true
            fulfilCrownRequest()
        }
    }

    /// Sealed capsules are written without their note, emotions,
    /// attribution and photo: what the app keeps out of sight shouldn't sit
    /// in plain text on the device either.
    private func saveMemoriesCache(_ items: [TimeMemory]) {
        let moment = Date()
        let entries = items.map { memory in
            memory.isLocked(at: moment)
                ? MemoryDTO(Self.redactedForCache(memory), redacted: true)
                : MemoryDTO(memory, redacted: false)
        }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: memoryCacheKey)
    }

    private static func redactedForCache(_ memory: TimeMemory) -> TimeMemory {
        var copy = memory
        copy.note = nil
        copy.emotions = []
        copy.attribution = nil
        copy.photoURL = nil
        return copy
    }

    private func saveAnchorCache(_ anchor: RelationshipAnchor?) {
        if let anchor, let data = try? JSONEncoder().encode(AnchorDTO(anchor)) {
            UserDefaults.standard.set(data, forKey: anchorCacheKey)
        } else {
            UserDefaults.standard.removeObject(forKey: anchorCacheKey)
        }
    }

    // MARK: - Crown "celebrated" flag (per device, per couple)

    private func crownCelebratedKey(for milestone: CrownMilestone) -> String {
        "coupley.crown.\(session.coupleId).\(milestone.id)"
    }

    private func hasCelebrated(_ milestone: CrownMilestone) -> Bool {
        UserDefaults.standard.bool(forKey: crownCelebratedKey(for: milestone))
    }

    private func markCrownAsCelebrated(_ milestone: CrownMilestone) {
        UserDefaults.standard.set(true, forKey: crownCelebratedKey(for: milestone))
    }
}

// MARK: - Derived selectors

extension TimeTreeViewModel {

    /// All non-capsule memories or capsules whose unlock has passed.
    /// Sorted newest-first for the timeline.
    var visibleMemories: [TimeMemory] {
        memories
            .filter { !$0.isLocked(at: now) }
            .sorted { $0.date > $1.date }
    }

    /// Capsule memories that are still locked. Sorted by unlock date
    /// ascending (closest unlock first).
    var lockedCapsules: [TimeMemory] {
        memories
            .filter { $0.isLocked(at: now) }
            .sorted { ($0.unlockDate ?? .distantFuture) < ($1.unlockDate ?? .distantFuture) }
    }

    var daysTogether: Int? {
        anchor?.daysTogether(now: now)
    }

    var nextCrown: CrownMilestone? {
        anchor.flatMap { CrownMilestone.next(after: $0.startDate, now: now) }
    }

    var growthStage: TreeGrowthStage {
        TreeGrowthStage.from(daysTogether: daysTogether ?? 0)
    }

    var currentSeason: TreeSeason {
        TreeSeason.current(now: now)
    }

    /// The earliest date of each preset kind among the visible memories
    /// (custom moments excluded), e.g. to mark which "firsts" are recorded.
    var firstDateByKind: [MemoryKind: Date] {
        var result: [MemoryKind: Date] = [:]
        for memory in visibleMemories where memory.kind != .custom {
            if let earliest = result[memory.kind], earliest <= memory.date { continue }
            result[memory.kind] = memory.date
        }
        return result
    }

    func memory(id: String) -> TimeMemory? {
        memories.first { $0.id == id }
    }

    /// Anyone can edit an open memory; a sealed capsule only by its author,
    /// so its contents stay out of sight for the partner until it opens.
    /// Nobody edits a copy the device cache blanked (a capsule cached while
    /// sealed): an editor seeded from it would save the blanks over the
    /// real note, feelings and photo.
    func canEdit(_ memory: TimeMemory) -> Bool {
        guard !redactedCacheIds.contains(memory.id) else { return false }
        return !memory.isLocked(at: now) || memory.createdBy == session.userId
    }
}

// MARK: - String helper

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Cache DTOs

private struct MemoryDTO: Codable {
    let id: String
    let kind: String
    let title: String
    let date: Date
    let note: String?
    let photoURL: String?
    let emotions: [String]
    let attribution: String?
    let anniversaryId: String?
    let unlockDate: Date?
    let createdBy: String
    let createdAt: Date
    let updatedAt: Date
    /// A sealed capsule cached without its contents (nil in caches written
    /// before redaction existed, which hold everything).
    let redacted: Bool?

    init(_ m: TimeMemory, redacted: Bool) {
        self.redacted = redacted
        id = m.id
        kind = m.kind.rawValue
        title = m.title
        date = m.date
        note = m.note
        photoURL = m.photoURL
        emotions = m.emotions.map(\.rawValue)
        attribution = m.attribution
        anniversaryId = m.anniversaryId
        unlockDate = m.unlockDate
        createdBy = m.createdBy
        createdAt = m.createdAt
        updatedAt = m.updatedAt
    }

    var memory: TimeMemory {
        TimeMemory(
            id: id,
            kind: MemoryKind(rawValue: kind) ?? .custom,
            title: title,
            date: date,
            note: note,
            photoURL: photoURL,
            emotions: emotions.compactMap(MemoryEmotion.init(rawValue:)),
            attribution: attribution,
            anniversaryId: anniversaryId,
            unlockDate: unlockDate,
            createdBy: createdBy,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

private struct AnchorDTO: Codable {
    let startDate: Date
    let setBy: String
    let setByName: String?
    let setAt: Date
    let updatedAt: Date

    init(_ a: RelationshipAnchor) {
        startDate = a.startDate
        setBy = a.setBy
        setByName = a.setByName
        setAt = a.setAt
        updatedAt = a.updatedAt
    }

    var anchor: RelationshipAnchor {
        RelationshipAnchor(
            startDate: startDate,
            setBy: setBy,
            setByName: setByName,
            setAt: setAt,
            updatedAt: updatedAt
        )
    }
}
