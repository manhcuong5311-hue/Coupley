//
//  TimeTreeViewModel.swift
//  Coupley
//
//  Owns the state for the entire Time Tree feature:
//   - the relationship anchor (start date)
//   - the list of memories (past + capsule)
//   - a 60-second tick timer so countdowns and "days together" stay live
//   - one-shot detection of newly-reached crown milestones for the
//     celebration overlay
//
//  Real-time Firestore listeners stay attached while the tab is visible
//  and are torn down on disappear. Local caches in UserDefaults provide
//  an offline-first experience consistent with the existing Anniversary
//  feature pattern.
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
    @Published private(set) var errorMessage: String?
    @Published var isSavingMemory: Bool = false
    @Published var isUploadingPhoto: Bool = false
    @Published var isSavingAnchor: Bool = false

    /// Ticked every minute so day-level countdowns advance at midnight
    /// while the app is foregrounded.
    @Published private(set) var now: Date = Date()

    /// The crown milestone that just became reached and hasn't been
    /// celebrated yet. The view observes this and runs the celebration
    /// overlay when set; the overlay calls `acknowledgeCrown` to clear it.
    @Published var pendingCrownCelebration: CrownMilestone?

    // MARK: - Dependencies

    private let session: UserSession
    private let memoryService: TimeTreeMemoryService
    private let anchorService: TimeTreeAnchorService
    private let storageService: TimeTreeStorageService
    private let scheduler: TimeTreeNotificationScheduling

    nonisolated(unsafe) private var memoryListener: ListenerRegistration?
    nonisolated(unsafe) private var anchorListener: ListenerRegistration?
    private var tickTimer: Timer?

    // MARK: - Init

    init(
        session: UserSession,
        memoryService: TimeTreeMemoryService? = nil,
        anchorService: TimeTreeAnchorService? = nil,
        storageService: TimeTreeStorageService? = nil,
        scheduler: TimeTreeNotificationScheduling? = nil
    ) {
        self.session = session
        self.memoryService  = memoryService  ?? FirestoreTimeTreeMemoryService()
        self.anchorService  = anchorService  ?? FirestoreTimeTreeAnchorService()
        self.storageService = storageService ?? TimeTreeStorageService()
        self.scheduler      = scheduler      ?? TimeTreeNotificationScheduler()
    }

    deinit {
        memoryListener?.remove()
        anchorListener?.remove()
        tickTimer?.invalidate()
    }

    // MARK: - Lifecycle

    func startListening() {
        guard memoryListener == nil, session.isPaired else { return }
        isListening = true

        loadCache()

        memoryListener = memoryService.observe(
            coupleId: session.coupleId,
            onUpdate: { [weak self] items in
                Task { @MainActor in
                    self?.handleRemoteMemoriesUpdate(items)
                }
            },
            onError: { [weak self] error in
                Task { @MainActor in
                    self?.errorMessage = error.localizedDescription
                }
            }
        )

        anchorListener = anchorService.observe(
            coupleId: session.coupleId,
            onUpdate: { [weak self] anchor in
                Task { @MainActor in
                    self?.handleRemoteAnchorUpdate(anchor)
                }
            },
            onError: { [weak self] error in
                Task { @MainActor in
                    self?.errorMessage = error.localizedDescription
                }
            }
        )

        startTicking()
    }

    func stopListening() {
        memoryListener?.remove(); memoryListener = nil
        anchorListener?.remove(); anchorListener = nil
        isListening = false
        tickTimer?.invalidate(); tickTimer = nil
    }

    /// Called on scenePhase becoming active. Re-bumps `now`, reschedules
    /// notifications, and re-evaluates the crown celebration so users
    /// who came back to the app on the milestone day get the moment.
    func refresh() {
        now = Date()
        Task {
            for memory in memories {
                await scheduler.rescheduleCapsule(memory)
            }
            if let anchor {
                await scheduler.rescheduleCrowns(anchor: anchor)
            }
        }
        evaluateCrownCelebration()
    }

    // MARK: - Anchor

    func setAnchor(startDate: Date, displayName: String?) async {
        guard session.isPaired else { return }
        isSavingAnchor = true
        defer { isSavingAnchor = false }

        let anchor = RelationshipAnchor(
            startDate: startDate,
            setBy: session.userId,
            setByName: displayName
        )
        do {
            try await anchorService.setAnchor(coupleId: session.coupleId, anchor: anchor)
            await scheduler.rescheduleCrowns(anchor: anchor)
        } catch {
            errorMessage = error.localizedDescription
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

        let memoryId = UUID().uuidString
        var photoURL: String?

        if let photo {
            isUploadingPhoto = true
            photoURL = try? await storageService.uploadPhoto(
                photo,
                coupleId: session.coupleId,
                memoryId: memoryId
            )
            isUploadingPhoto = false
        }

        let memory = TimeMemory(
            id: memoryId,
            kind: kind,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            date: date,
            note: note?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            photoURL: photoURL,
            emotions: emotions,
            attribution: attribution?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            anniversaryId: anniversaryId,
            unlockDate: unlockDate,
            createdBy: session.userId
        )

        do {
            try await memoryService.create(coupleId: session.coupleId, memory: memory)
            await scheduler.rescheduleCapsule(memory)
        } catch {
            errorMessage = error.localizedDescription
        }
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

        if let photo {
            isUploadingPhoto = true
            updated.photoURL = try? await storageService.uploadPhoto(
                photo,
                coupleId: session.coupleId,
                memoryId: memory.id
            )
            isUploadingPhoto = false
        } else if clearPhoto {
            updated.photoURL = nil
            await storageService.deletePhoto(coupleId: session.coupleId, memoryId: memory.id)
        }

        do {
            try await memoryService.update(coupleId: session.coupleId, memory: updated)
            await scheduler.rescheduleCapsule(updated)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteMemory(_ memory: TimeMemory) async {
        guard session.isPaired else { return }
        do {
            try await memoryService.delete(coupleId: session.coupleId, id: memory.id)
            await scheduler.cancelCapsule(memory.id)
            if memory.photoURL != nil {
                await storageService.deletePhoto(coupleId: session.coupleId, memoryId: memory.id)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Crown celebration

    func acknowledgeCrown() {
        guard let milestone = pendingCrownCelebration else { return }
        markCrownAsCelebrated(milestone)
        pendingCrownCelebration = nil
    }

    // MARK: - Private — remote sync

    private func handleRemoteMemoriesUpdate(_ items: [TimeMemory]) {
        let previous = Dictionary(uniqueKeysWithValues: memories.map { ($0.id, $0) })
        memories = items
        saveMemoriesCache(items)

        Task {
            let currentIds = Set(items.map(\.id))
            for (id, _) in previous where !currentIds.contains(id) {
                await scheduler.cancelCapsule(id)
            }
            for memory in items {
                await scheduler.rescheduleCapsule(memory)
            }
        }
    }

    private func handleRemoteAnchorUpdate(_ anchor: RelationshipAnchor?) {
        self.anchor = anchor
        saveAnchorCache(anchor)
        if let anchor {
            Task { await scheduler.rescheduleCrowns(anchor: anchor) }
            evaluateCrownCelebration()
        } else {
            Task { await scheduler.cancelAllCrowns() }
        }
    }

    /// Looks at the current anchor and the most-recently-reached crown
    /// milestone. If that milestone became reached today AND we haven't
    /// celebrated it on this device yet, surfaces it for the overlay.
    private func evaluateCrownCelebration() {
        guard let anchor else { return }

        let reached = CrownMilestone.reached(after: anchor.startDate, now: now)
        guard let mostRecent = reached.last else { return }

        // Only celebrate "fresh" crowns — within their reach day, not
        // every crown the couple has ever passed (we'd spam the user
        // every time they open the app from now until forever).
        guard mostRecent.isFreshlyReached(anchor: anchor.startDate, now: now) else { return }

        guard !hasCelebrated(mostRecent) else { return }
        pendingCrownCelebration = mostRecent
    }

    // MARK: - Tick timer

    private func startTicking() {
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.now = Date()
                self?.evaluateCrownCelebration()
            }
        }
    }

    // MARK: - Cache (UserDefaults)

    private var memoryCacheKey: String { "coupley.memories.\(session.coupleId)" }
    private var anchorCacheKey: String { "coupley.anchor.\(session.coupleId)" }

    private func loadCache() {
        if let data = UserDefaults.standard.data(forKey: memoryCacheKey),
           let items = try? JSONDecoder().decode([MemoryDTO].self, from: data),
           !items.isEmpty {
            memories = items.map(\.memory)
        }
        if let data = UserDefaults.standard.data(forKey: anchorCacheKey),
           let dto = try? JSONDecoder().decode(AnchorDTO.self, from: data) {
            anchor = dto.anchor
        }
    }

    private func saveMemoriesCache(_ items: [TimeMemory]) {
        guard let data = try? JSONEncoder().encode(items.map(MemoryDTO.init)) else { return }
        UserDefaults.standard.set(data, forKey: memoryCacheKey)
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

    init(_ m: TimeMemory) {
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
