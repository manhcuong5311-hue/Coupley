//
//  PartnerProfileDetailViewModel.swift
//  Coupley
//
//  MVVM view model backing both the "My Profile" and "Partner Profile"
//  detail screens. Same shape, different edit permission.
//

import Foundation
import FirebaseFirestore
import Combine

// MARK: - View Model

@MainActor
final class PartnerProfileDetailViewModel: ObservableObject {

    enum Mode {
        case mine
        case partner

        var isEditable: Bool { self == .mine }
    }

    // MARK: - Published state

    @Published var profile: PartnerProfileDetail
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isSaving: Bool = false
    @Published private(set) var errorMessage: String?

    let mode: Mode
    let targetUserId: String
    let hasPartner: Bool

    // MARK: - Deps

    private let service: PartnerProfileDetailService
    nonisolated(unsafe) private var listener: ListenerRegistration?
    private var saveTask: Task<Void, Never>?

    // MARK: - Init

    init(
        targetUserId: String,
        mode: Mode,
        hasPartner: Bool,
        service: PartnerProfileDetailService = FirestorePartnerProfileDetailService()
    ) {
        self.targetUserId = targetUserId
        self.mode = mode
        self.hasPartner = hasPartner
        self.service = service

        // Prime from cache so the screen doesn't flash empty state.
        self.profile = FirestorePartnerProfileDetailService.cached(userId: targetUserId)
            ?? .empty(userId: targetUserId)
    }

    deinit {
        listener?.remove()
        saveTask?.cancel()
    }

    // MARK: - Lifecycle

    func start() {
        guard listener == nil else { return }

        // Edge case: partner profile requested but no partner connected.
        if mode == .partner && !hasPartner {
            errorMessage = "No partner connected yet."
            return
        }

        isLoading = profile.isEmpty
        listener = service.observeProfile(userId: targetUserId) { [weak self] profile in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Conflict resolution: only accept if newer than current.
                if profile.updatedAt >= self.profile.updatedAt || self.profile.isEmpty {
                    self.profile = profile
                }
                self.isLoading = false
                self.errorMessage = nil
            }
        }
    }

    func stop() {
        listener?.remove()
        listener = nil
    }

    // MARK: - Mutations (only valid in .mine mode)

    func addLike(_ value: String) {
        guard mode.isEditable else { return }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !profile.likes.contains(trimmed) else { return }
        profile.likes.append(trimmed)
        persist()
    }

    func removeLike(_ value: String) {
        guard mode.isEditable else { return }
        profile.likes.removeAll { $0 == value }
        persist()
    }

    func addDislike(_ value: String) {
        guard mode.isEditable else { return }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !profile.dislikes.contains(trimmed) else { return }
        profile.dislikes.append(trimmed)
        persist()
    }

    func removeDislike(_ value: String) {
        guard mode.isEditable else { return }
        profile.dislikes.removeAll { $0 == value }
        persist()
    }

    func addActivity(_ value: String) {
        guard mode.isEditable else { return }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !profile.activities.contains(trimmed) else { return }
        profile.activities.append(trimmed)
        persist()
    }

    func removeActivity(_ value: String) {
        guard mode.isEditable else { return }
        profile.activities.removeAll { $0 == value }
        persist()
    }

    func updateCommunicationStyle(_ value: String) {
        guard mode.isEditable else { return }
        profile.communicationStyle = value
        persist(debounced: true)
    }

    func updateNotes(_ value: String) {
        guard mode.isEditable else { return }
        profile.notes = value
        persist(debounced: true)
    }

    // MARK: - Persist

    /// Writes the current profile to the backend. If `debounced`, waits a
    /// short moment so typing doesn't fire a write on every keystroke.
    private func persist(debounced: Bool = false) {
        saveTask?.cancel()
        saveTask = Task { [profile, service] in
            if debounced {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if Task.isCancelled { return }
            }
            await MainActor.run { self.isSaving = true }
            defer { Task { @MainActor in self.isSaving = false } }

            var snapshot = profile
            snapshot.updatedAt = Date()

            do {
                try await service.updateProfile(snapshot)
            } catch {
                await MainActor.run {
                    self.errorMessage = "Couldn't sync changes. We'll retry when you're back online."
                }
            }
        }
    }
}
