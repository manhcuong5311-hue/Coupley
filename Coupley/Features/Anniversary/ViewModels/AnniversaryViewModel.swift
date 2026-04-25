//
//  AnniversaryViewModel.swift
//  Coupley
//

import Foundation
import FirebaseFirestore
import Combine
import UIKit

// MARK: - View Model

@MainActor
final class AnniversaryViewModel: ObservableObject {

    @Published private(set) var anniversaries: [Anniversary] = []
    @Published private(set) var isListening: Bool = false
    @Published private(set) var errorMessage: String?
    @Published var isSaving: Bool = false
    @Published var isUploadingImage: Bool = false

    /// Tick published every minute while the view is visible so the UI can
    /// re-render countdowns that cross midnight while the app is in the
    /// foreground.
    @Published private(set) var now: Date = Date()

    private let session: UserSession
    private let service: AnniversaryService
    private let scheduler: AnniversaryNotificationScheduling
    private let storageService: AnniversaryStorageService

    nonisolated(unsafe) private var listener: ListenerRegistration?
    private var tickTimer: Timer?

    // MARK: - Init

    init(
        session: UserSession,
        service: AnniversaryService? = nil,
        scheduler: AnniversaryNotificationScheduling? = nil,
        storageService: AnniversaryStorageService? = nil
    ) {
        self.session = session
        self.service = service ?? FirestoreAnniversaryService()
        self.scheduler = scheduler ?? AnniversaryNotificationScheduler()
        self.storageService = storageService ?? AnniversaryStorageService()
    }

    deinit {
        listener?.remove()
        tickTimer?.invalidate()
    }

    // MARK: - Lifecycle

    func startListening() {
        guard listener == nil, session.isPaired else { return }
        isListening = true

        loadCache()

        listener = service.observe(
            coupleId: session.coupleId,
            onUpdate: { [weak self] items in
                Task { @MainActor in
                    self?.handleRemoteUpdate(items)
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
        listener?.remove(); listener = nil
        isListening = false
        tickTimer?.invalidate(); tickTimer = nil
    }

    /// Called when the app returns to the foreground — rebump `now` and
    /// reschedule notifications in case the system dropped them or the
    /// device's timezone changed while we were away.
    func refresh() {
        now = Date()
        Task {
            for item in anniversaries {
                await scheduler.reschedule(item)
            }
        }
    }

    // MARK: - CRUD

    func create(title: String, date: Date, note: String?, image: UIImage? = nil) async {
        guard session.isPaired else { return }
        isSaving = true
        defer { isSaving = false }

        let anniversaryId = UUID().uuidString
        var imageURL: String?

        if let image {
            isUploadingImage = true
            imageURL = try? await storageService.uploadCover(
                image,
                coupleId: session.coupleId,
                anniversaryId: anniversaryId
            )
            isUploadingImage = false
        }

        let anniversary = Anniversary(
            id: anniversaryId,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            date: date,
            note: note?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            imageURL: imageURL,
            creatorTimezone: TimeZone.current.identifier,
            createdBy: session.userId
        )

        do {
            try await service.create(coupleId: session.coupleId, anniversary: anniversary)
            await scheduler.reschedule(anniversary)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func update(_ anniversary: Anniversary, title: String, date: Date, note: String?, image: UIImage? = nil) async {
        guard session.isPaired else { return }
        isSaving = true
        defer { isSaving = false }

        var updated = anniversary
        updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.date = date
        updated.note = note?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        updated.updatedAt = Date()

        if let image {
            isUploadingImage = true
            updated.imageURL = try? await storageService.uploadCover(
                image,
                coupleId: session.coupleId,
                anniversaryId: anniversary.id
            )
            isUploadingImage = false
        }

        do {
            try await service.update(coupleId: session.coupleId, anniversary: updated)
            await scheduler.reschedule(updated)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ anniversary: Anniversary) async {
        guard session.isPaired else { return }
        do {
            try await service.delete(coupleId: session.coupleId, id: anniversary.id)
            await scheduler.cancel(anniversary.id)
            if anniversary.imageURL != nil {
                await storageService.deleteCover(coupleId: session.coupleId, anniversaryId: anniversary.id)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Private

    private func handleRemoteUpdate(_ items: [Anniversary]) {
        let previous = Dictionary(uniqueKeysWithValues: anniversaries.map { ($0.id, $0) })
        anniversaries = items
        saveCache(items)

        // Reconcile local notifications with remote truth. This covers all
        // the partner-side edits/deletes plus the case where the OS dropped
        // pending requests while the app was uninstalled/reinstalled.
        Task {
            // Cancel notifications for items that no longer exist.
            let currentIds = Set(items.map(\.id))
            for (id, _) in previous where !currentIds.contains(id) {
                await scheduler.cancel(id)
            }
            // Schedule/refresh notifications for every current item.
            for item in items {
                await scheduler.reschedule(item)
            }
        }
    }

    private func startTicking() {
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.now = Date() }
        }
    }

    // MARK: - Anniversary Cache

    private var cacheKey: String { "coupley.anniversaries.\(session.coupleId)" }

    private func loadCache() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let items = try? JSONDecoder().decode([AnniversaryDTO].self, from: data),
              !items.isEmpty else { return }
        anniversaries = items.map(\.anniversary)
    }

    private func saveCache(_ items: [Anniversary]) {
        guard let data = try? JSONEncoder().encode(items.map(AnniversaryDTO.init)) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }
}

// MARK: - String helper

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Cache DTO

/// Plain Codable mirror of Anniversary that avoids @DocumentID encoding ambiguity.
private struct AnniversaryDTO: Codable {
    let id: String
    let title: String
    let date: Date
    let note: String?
    let imageURL: String?
    let creatorTimezone: String
    let createdBy: String
    let createdAt: Date
    let updatedAt: Date

    init(_ a: Anniversary) {
        id             = a.id
        title          = a.title
        date           = a.date
        note           = a.note
        imageURL       = a.imageURL
        creatorTimezone = a.creatorTimezone
        createdBy      = a.createdBy
        createdAt      = a.createdAt
        updatedAt      = a.updatedAt
    }

    var anniversary: Anniversary {
        Anniversary(
            id: id, title: title, date: date, note: note, imageURL: imageURL,
            creatorTimezone: creatorTimezone, createdBy: createdBy,
            createdAt: createdAt, updatedAt: updatedAt
        )
    }
}
