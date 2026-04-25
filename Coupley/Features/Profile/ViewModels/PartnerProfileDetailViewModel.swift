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
        /// Viewing your own profile — you own all entries and can freely
        /// edit/remove anything, including hints your partner added.
        case mine
        /// Viewing your partner's profile — you may still add hints *for*
        /// them (stored on their doc, attributed back to you) and remove
        /// only the hints you yourself contributed.
        case partner
    }

    // MARK: - Published state

    @Published var profile: PartnerProfileDetail
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isSaving: Bool = false
    @Published private(set) var errorMessage: String?

    let mode: Mode
    let targetUserId: String
    let currentUserId: String
    let hasPartner: Bool

    // MARK: - Deps

    private let service: PartnerProfileDetailService
    nonisolated(unsafe) private var listener: ListenerRegistration?
    private var saveTask: Task<Void, Never>?

    // MARK: - Init

    init(
        targetUserId: String,
        currentUserId: String,
        mode: Mode,
        hasPartner: Bool,
        service: PartnerProfileDetailService = FirestorePartnerProfileDetailService()
    ) {
        self.targetUserId = targetUserId
        self.currentUserId = currentUserId
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

    // MARK: - Edit permissions

    /// Anyone in the couple may add hints to either profile. Partner-mode
    /// adds are attributed back to the contributor via `*AddedBy`.
    var canAdd: Bool {
        mode == .mine || (mode == .partner && hasPartner)
    }

    /// The profile owner may remove any entry. A non-owner may only remove
    /// hints they themselves contributed — they can't silently delete the
    /// owner's own likes/dislikes.
    func canRemove(addedBy: String?) -> Bool {
        if mode == .mine { return true }
        return addedBy == currentUserId
    }

    // MARK: - Free-text fields (communication style, notes)

    /// Text fields remain owner-only — partner hints are shaped like chips,
    /// not paragraphs. Non-owners see read-only text.
    var canEditFreeText: Bool { mode == .mine }

    // MARK: - Mutations

    func addLike(_ value: String) {
        guard canAdd else { return }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !profile.likes.contains(trimmed) else { return }
        profile.likes.append(trimmed)
        profile.likesAddedBy[trimmed] = currentUserId
        persist()
    }

    func removeLike(_ value: String) {
        guard canRemove(addedBy: profile.likesAddedBy[value]) else { return }
        profile.likes.removeAll { $0 == value }
        profile.likesAddedBy.removeValue(forKey: value)
        persist()
    }

    func addDislike(_ value: String) {
        guard canAdd else { return }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !profile.dislikes.contains(trimmed) else { return }
        profile.dislikes.append(trimmed)
        profile.dislikesAddedBy[trimmed] = currentUserId
        persist()
    }

    func removeDislike(_ value: String) {
        guard canRemove(addedBy: profile.dislikesAddedBy[value]) else { return }
        profile.dislikes.removeAll { $0 == value }
        profile.dislikesAddedBy.removeValue(forKey: value)
        persist()
    }

    func addActivity(_ value: String) {
        guard canAdd else { return }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !profile.activities.contains(trimmed) else { return }
        profile.activities.append(trimmed)
        profile.activitiesAddedBy[trimmed] = currentUserId
        persist()
    }

    func removeActivity(_ value: String) {
        guard canRemove(addedBy: profile.activitiesAddedBy[value]) else { return }
        profile.activities.removeAll { $0 == value }
        profile.activitiesAddedBy.removeValue(forKey: value)
        persist()
    }

    func updateCommunicationStyle(_ value: String) {
        guard canEditFreeText else { return }
        profile.communicationStyle = value
        persist(debounced: true)
    }

    func updateNotes(_ value: String) {
        guard canEditFreeText else { return }
        profile.notes = value
        persist(debounced: true)
    }

    // MARK: - Custom Q&A (owner-only)

    /// Custom quizzes are personal reflections — only the profile owner can
    /// create or remove them. Premium gate is enforced at the call site
    /// (create button presents the paywall).
    var canEditCustomAnswers: Bool { mode == .mine }

    func addCustomAnswer(question: String, options: [String], selected: [String]) {
        guard canEditCustomAnswers else { return }
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedOptions = options
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !trimmedQuestion.isEmpty, !cleanedOptions.isEmpty else { return }

        let selectedInOptions = selected.filter { cleanedOptions.contains($0) }
        let entry = CustomQuizAnswer(
            question: trimmedQuestion,
            options: cleanedOptions,
            selectedOptions: selectedInOptions,
            createdBy: currentUserId
        )
        profile.customAnswers.append(entry)
        persist()
    }

    func removeCustomAnswer(id: String) {
        guard canEditCustomAnswers else { return }
        profile.customAnswers.removeAll { $0.id == id }
        persist()
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
