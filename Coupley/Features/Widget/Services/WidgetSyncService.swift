//
//  WidgetSyncService.swift
//  Coupley
//
//  Single coordinator that owns the widget snapshot. Reads live data from
//  Firestore (TimeTree anchor + memories, partner mood, latest nudge),
//  downloads the couple photo, builds a `WidgetSnapshot`, persists it to
//  the App Group container, and triggers a widget timeline reload. The
//  widget then reads from disk — it never touches Firebase.
//
//  Lifecycle: created and bound to a session by `WidgetSyncCoordinator`.
//  Bind/unbind cycles match `SessionStore.appState` transitions so the
//  service is idle when the user is signed-out or unpaired.
//

import Foundation
import FirebaseFirestore
import FirebaseStorage
import UIKit
import WidgetKit

// MARK: - Service

@MainActor
final class WidgetSyncService {

    static let shared = WidgetSyncService()

    private let db = Firestore.firestore()
    private let storage = Storage.storage()

    // The TimeTree feature replaces the old Anniversary list — both
    // "days together" and the upcoming-event countdown now come from
    // the relationship anchor + memory collection.
    private let anchorService: TimeTreeAnchorService = FirestoreTimeTreeAnchorService()
    private let memoryService: TimeTreeMemoryService = FirestoreTimeTreeMemoryService()

    private var session: UserSession?
    private var partnerDisplayName: String?
    private var couplePhotoURLString: String?

    nonisolated(unsafe) private var anchorListener: ListenerRegistration?
    nonisolated(unsafe) private var memoryListener: ListenerRegistration?
    nonisolated(unsafe) private var partnerMoodListener: ListenerRegistration?
    nonisolated(unsafe) private var nudgeListener: ListenerRegistration?
    nonisolated(unsafe) private var partnerProfileListener: ListenerRegistration?
    nonisolated(unsafe) private var coupleDocListener: ListenerRegistration?

    // In-memory bits of the snapshot we'll merge on every write. Holding
    // them here lets a single listener fire without losing the data the
    // others contributed.
    private var pendingMood: MoodSnapshot?
    private var pendingNudge: NudgeSnapshot?
    private var pendingAnniversary: AnniversarySnapshot?

    // Raw inputs that feed `pendingAnniversary` — kept separately so a
    // memory update doesn't lose the anchor and vice versa.
    private var pendingAnchor: RelationshipAnchor?
    private var pendingMemories: [TimeMemory] = []

    private init() {}

    // MARK: - Bind / Unbind

    /// Attaches the service to a paired session. Idempotent — re-binding
    /// to the same session is a no-op. Re-binding to a different session
    /// detaches the previous listeners first.
    func bind(session: UserSession, partnerDisplayName: String?) {
        guard session.isPaired else {
            unbind()
            return
        }

        // Already bound to this session?
        if let current = self.session,
           current.coupleId == session.coupleId,
           current.userId == session.userId {
            self.partnerDisplayName = partnerDisplayName
            scheduleWrite()
            return
        }

        // Switching sessions — drop the old listeners and pending data
        // but DON'T wipe the snapshot to placeholder. Wiping here would
        // make the widget flash the "Connect with your partner" empty
        // state until the first Firestore listener fires.
        tearDownListeners()
        self.session = session
        self.partnerDisplayName = partnerDisplayName

        startListening(session: session)

        // Write an initial paired snapshot now so `isPaired: true` lands
        // immediately — Firestore listeners will fill in mood/nudge/
        // anniversary as they fire. Without this, the widget keeps
        // rendering the previous (possibly placeholder) snapshot until
        // the first listener completes.
        scheduleWrite()
    }

    /// Detaches all listeners and writes a final unpaired snapshot so the
    /// widget shows the empty state immediately. Call on sign-out and on
    /// disconnect.
    func unbind() {
        tearDownListeners()

        let empty = WidgetSnapshot.placeholder
        WidgetSnapshotStore.write(empty)
        WidgetSnapshotStore.clearCouplePhoto()
        reloadTimelines()
    }

    /// Removes Firestore listeners and clears in-memory pending state
    /// without touching the on-disk snapshot. Use this when transitioning
    /// between paired sessions; use `unbind()` when actually leaving the
    /// paired state.
    private func tearDownListeners() {
        anchorListener?.remove();         anchorListener = nil
        memoryListener?.remove();         memoryListener = nil
        partnerMoodListener?.remove();    partnerMoodListener = nil
        nudgeListener?.remove();          nudgeListener = nil
        partnerProfileListener?.remove(); partnerProfileListener = nil
        coupleDocListener?.remove();      coupleDocListener = nil

        session = nil
        partnerDisplayName = nil
        couplePhotoURLString = nil
        pendingMood = nil
        pendingNudge = nil
        pendingAnniversary = nil
        pendingAnchor = nil
        pendingMemories = []
    }

    // MARK: - Listeners

    private func startListening(session: UserSession) {
        observeRelationshipAnchor(coupleId: session.coupleId)
        observeMemories(coupleId: session.coupleId)
        observePartnerMood(coupleId: session.coupleId, partnerId: session.partnerId)
        observeNudges(coupleId: session.coupleId, userId: session.userId)
        observePartnerProfile(partnerId: session.partnerId)
        observeCoupleDocument(coupleId: session.coupleId)
    }

    // MARK: - TimeTree (Anchor + Memories)

    private func observeRelationshipAnchor(coupleId: String) {
        anchorListener = anchorService.observe(
            coupleId: coupleId,
            onUpdate: { [weak self] anchor in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.pendingAnchor = anchor
                    self.rebuildAnniversarySnapshot()
                    self.scheduleWrite()
                }
            },
            onError: { _ in }
        )
    }

    private func observeMemories(coupleId: String) {
        memoryListener = memoryService.observe(
            coupleId: coupleId,
            onUpdate: { [weak self] memories in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.pendingMemories = memories
                    self.rebuildAnniversarySnapshot()
                    self.scheduleWrite()
                }
            },
            onError: { _ in }
        )
    }

    /// Combines the latest anchor + memories into the AnniversarySnapshot
    /// the widget consumes. The yearly anniversary is synthesized so the
    /// widget always has a countdown to surface, even when the user hasn't
    /// added any future-dated memories.
    private func rebuildAnniversarySnapshot() {
        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)

        let relationshipStart = pendingAnchor?.startDate

        var upcoming: [UpcomingAnniversary] = []

        // Future-dated memories or capsules whose unlock date is still ahead.
        for memory in pendingMemories {
            let surfaceDate = memory.unlockDate ?? memory.date
            guard calendar.startOfDay(for: surfaceDate) >= today else { continue }
            let title: String = {
                if memory.kind == .custom {
                    let trimmed = memory.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? "Memory" : trimmed
                }
                return memory.kind.displayName
            }()
            upcoming.append(UpcomingAnniversary(
                id: memory.id,
                title: title,
                date: surfaceDate
            ))
        }

        // Synthesize the next yearly anniversary so the widget shows a
        // countdown beyond the engine's 7-day milestone window. The
        // engine still picks up "1 Year Anniversary" / "2 Year Anniversary"
        // as a celebratory milestone when it's imminent.
        if let anchor = pendingAnchor {
            let nextAnniversary = anchor.nextYearlyAnniversary(now: now, calendar: calendar)
            let yearsAhead = anchor.yearsCompleted(now: now, calendar: calendar) + 1
            upcoming.append(UpcomingAnniversary(
                id: "anniversary-year-\(yearsAhead)",
                title: "Anniversary",
                date: nextAnniversary
            ))
        }

        upcoming.sort { $0.date < $1.date }
        pendingAnniversary = AnniversarySnapshot(
            relationshipStart: relationshipStart,
            upcoming: Array(upcoming.prefix(8))
        )
    }

    // MARK: - Partner Mood

    private func observePartnerMood(coupleId: String, partnerId: String) {
        partnerMoodListener = db
            .collection(FirestorePath.moods(coupleId: coupleId))
            .whereField("userId", isEqualTo: partnerId)
            .order(by: "timestamp", descending: true)
            .limit(to: 1)
            .addSnapshotListener { [weak self] snapshot, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.pendingMood = Self.makeMoodSnapshot(snapshot)
                    self.scheduleWrite()
                }
            }
    }

    private static func makeMoodSnapshot(_ snapshot: QuerySnapshot?) -> MoodSnapshot? {
        guard let doc = snapshot?.documents.first else { return nil }
        let data = doc.data()
        let raw = (data["mood"] as? String) ?? ""
        let kind = WidgetMoodKind(rawValue: raw) ?? .unspecified
        let note = (data["note"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let custom = (data["customLabel"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() ?? Date()
        return MoodSnapshot(
            kind: kind,
            note: note,
            updatedAt: timestamp,
            customLabel: custom
        )
    }

    // MARK: - Nudges

    private func observeNudges(coupleId: String, userId: String) {
        // Latest 1 nudge addressed to the current user. Window keeps it
        // fresh — we don't want a stale 3-day-old "Thinking of you" on
        // the home screen.
        let since = Date().addingTimeInterval(-24 * 3600)

        nudgeListener = db.collection("couples/\(coupleId)/nudges")
            .whereField("toUserId", isEqualTo: userId)
            .whereField("createdAt", isGreaterThan: Timestamp(date: since))
            .order(by: "createdAt", descending: true)
            .limit(to: 1)
            .addSnapshotListener { [weak self] snapshot, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.pendingNudge = Self.makeNudgeSnapshot(snapshot)
                    self.scheduleWrite()
                }
            }
    }

    private static func makeNudgeSnapshot(_ snapshot: QuerySnapshot?) -> NudgeSnapshot? {
        guard let doc = snapshot?.documents.first else { return nil }
        let data = doc.data()
        let kind = (data["kind"] as? String) ?? "ping"
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        let reactionRaw = data["reactionKind"] as? String

        let (emoji, message) = Self.presentation(forKind: kind, reaction: reactionRaw)
        return NudgeSnapshot(emoji: emoji, message: message, receivedAt: createdAt)
    }

    /// Maps a nudge document to widget-friendly emoji + message. The main
    /// app's own `NudgeKind` / `ReactionKind` enums live in the domain
    /// layer; we duplicate the mapping here to keep this file free of
    /// cross-feature imports.
    private static func presentation(
        forKind kind: String,
        reaction: String?
    ) -> (emoji: String, message: String) {
        switch (kind, reaction) {
        case ("ping", _):              return ("💌", "Thinking of you")
        case ("reaction", "heart"):    return ("❤️", "Sent you love")
        case ("reaction", "hug"):      return ("🤗", "Sent you a hug")
        case ("reaction", "callMe"):   return ("📞", "Wants to call")
        case ("reaction", "coffee"):   return ("☕", "Coffee together?")
        case ("reaction", _):          return ("✨", "Sent a reaction")
        default:                       return ("💭", "From your partner")
        }
    }

    // MARK: - Partner Profile

    private func observePartnerProfile(partnerId: String) {
        partnerProfileListener = db
            .collection(FirestorePath.users)
            .document(partnerId)
            .addSnapshotListener { [weak self] snapshot, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let name = (snapshot?.data()?["displayName"] as? String)
                        .flatMap { $0.isEmpty ? nil : $0 }
                    self.partnerDisplayName = name ?? self.partnerDisplayName
                    self.scheduleWrite()
                }
            }
    }

    // MARK: - Couple Document (photo)

    private func observeCoupleDocument(coupleId: String) {
        coupleDocListener = db
            .collection(FirestorePath.couples)
            .document(coupleId)
            .addSnapshotListener { [weak self] snapshot, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let urlString = snapshot?.data()?["photoURL"] as? String
                    if urlString != self.couplePhotoURLString {
                        self.couplePhotoURLString = urlString
                        await self.refreshCouplePhoto(from: urlString)
                    }
                    self.scheduleWrite()
                }
            }
    }

    // MARK: - Photo Download

    private func refreshCouplePhoto(from urlString: String?) async {
        guard let urlString, !urlString.isEmpty else {
            WidgetSnapshotStore.clearCouplePhoto()
            return
        }

        // The image source is the Firebase Storage URL stored on the couple
        // doc. URLSession works for both signed-token URLs and public URLs.
        guard let url = URL(string: urlString) else {
            WidgetSnapshotStore.clearCouplePhoto()
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let image = UIImage(data: data) else {
                return
            }

            // Downsample to roughly the medium widget's pixel density. The
            // App Group container is shared with the user's device backups,
            // so we keep the file small.
            let resized = Self.downscaled(image, maxDimension: 1024)
            guard let jpeg = resized.jpegData(compressionQuality: 0.82) else { return }
            _ = WidgetSnapshotStore.writeCouplePhoto(jpegData: jpeg)
        } catch {
            // Leave the previous photo in place on transient failure —
            // better than blanking the widget on a flaky connection.
        }
    }

    private static func downscaled(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    // MARK: - Write

    private var writeTask: Task<Void, Never>?

    /// Coalesces back-to-back listener fires — when three listeners hit at
    /// the same time, we still only persist + reload widgets once.
    private func scheduleWrite() {
        writeTask?.cancel()
        writeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000) // 120ms
            guard !Task.isCancelled, let self else { return }
            self.writeNow()
        }
    }

    private func writeNow() {
        guard let session, session.isPaired else {
            WidgetSnapshotStore.write(.placeholder)
            reloadTimelines()
            return
        }

        let snapshot = WidgetSnapshot(
            version: WidgetSnapshot.currentVersion,
            generatedAt: Date(),
            isPaired: true,
            partner: PartnerSnapshot(
                displayName: partnerDisplayName ?? "Partner",
                avatarFilename: nil
            ),
            mood: pendingMood,
            nudge: pendingNudge,
            anniversary: pendingAnniversary,
            couplePhotoFilename: (WidgetShared.couplePhotoURL?.lastPathComponent)
                .flatMap { name in
                    // Only include the filename if the file actually exists.
                    let url = WidgetShared.containerURL?.appendingPathComponent(name)
                    if let url, FileManager.default.fileExists(atPath: url.path) {
                        return name
                    }
                    return nil
                }
        )

        WidgetSnapshotStore.write(snapshot)
        reloadTimelines()
    }

    // MARK: - Timeline Reload

    private func reloadTimelines() {
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetShared.widgetKind)
    }
}
