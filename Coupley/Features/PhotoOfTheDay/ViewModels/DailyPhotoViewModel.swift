//
//  DailyPhotoViewModel.swift
//  Coupley
//

import Foundation
import SwiftUI
import Combine
import FirebaseFirestore

@MainActor
final class DailyPhotoViewModel: ObservableObject {

    enum CardState: Equatable {
        case hidden
        case loading
        /// Prompt is open and this user hasn't sent a photo.
        case awaitingMe(DailyPhoto)
        /// Sent; waiting for the partner before anything is revealed.
        case awaitingPartner(DailyPhoto)
        /// Both in — show them.
        case revealed(DailyPhoto)
    }

    @Published private(set) var photo: DailyPhoto?
    @Published private(set) var isLoading = true
    @Published private(set) var isUploading = false
    @Published private(set) var errorMessage: String?

    private var session: UserSession
    private let service: DailyPhotoServicing
    private var listener: ListenerRegistration?
    private var lastEnsureAttempt: Date?
    private static let ensureRetryInterval: TimeInterval = 3600

    init(session: UserSession, service: DailyPhotoServicing? = nil) {
        self.session = session
        self.service = service ?? FirestoreDailyPhotoService()
    }

    deinit { listener?.remove() }

    /// `UserSession.demo` passes `isPaired` with a placeholder couple id, so
    /// it has to be excluded explicitly — see QuestionOfTheDayViewModel.
    private var hasRealSession: Bool {
        session.isPaired && session.coupleId != UserSession.demo.coupleId
    }

    var state: CardState {
        guard hasRealSession else { return .hidden }
        guard let photo else { return isLoading ? .loading : .hidden }
        if !photo.hasSubmitted(session.userId) { return .awaitingMe(photo) }
        if !photo.hasSubmitted(session.partnerId) { return .awaitingPartner(photo) }
        return .revealed(photo)
    }

    var myUserId: String { session.userId }
    var partnerUserId: String { session.partnerId }

    func rebind(session: UserSession) {
        guard session.coupleId != self.session.coupleId
                || session.userId != self.session.userId else { return }
        self.session = session
        lastEnsureAttempt = nil
        stop()
        start()
    }

    func start() {
        guard hasRealSession else { isLoading = false; return }

        if listener == nil {
            listener = service.observeCurrent(
                coupleId: session.coupleId,
                onUpdate: { [weak self] photo in
                    Task { @MainActor in
                        self?.photo = photo
                        self?.isLoading = false
                    }
                },
                onError: { [weak self] error in
                    Task { @MainActor in
                        self?.errorMessage = error.localizedDescription
                        self?.isLoading = false
                    }
                }
            )
        }
        ensurePromptExists()
    }

    func stop() {
        listener?.remove(); listener = nil
    }

    private func ensurePromptExists() {
        guard hasRealSession else { return }
        if let last = lastEnsureAttempt,
           Date().timeIntervalSince(last) < Self.ensureRetryInterval { return }
        lastEnsureAttempt = Date()

        Task { [weak self, service, session] in
            do {
                try await service.ensureCurrentPrompt(coupleId: session.coupleId)
            } catch {
                print("[DailyPhoto] ensureCurrentPrompt failed: \(error.localizedDescription)")
                // Not an attempt worth throttling: allow the next trigger to retry.
                self?.lastEnsureAttempt = nil
            }
        }
    }

    // MARK: - Submitting

    func submit(_ image: UIImage) {
        guard let photo, !isUploading else { return }
        // One photo per prompt per person. The card already hides the button
        // once you've sent, but a stale view or a double tap must not cost a
        // second upload — every one is storage billed and the partner's data
        // spent on a picture that replaces the one they already loaded.
        guard !photo.hasSubmitted(session.userId) else { return }
        isUploading = true
        errorMessage = nil

        Task { [service, session] in
            defer { Task { @MainActor in self.isUploading = false } }
            do {
                try await service.submit(image,
                                         coupleId: session.coupleId,
                                         photoId: photo.id,
                                         userId: session.userId)
                await MainActor.run { AdsManager.shared.recordAction() }
            } catch {
                await MainActor.run { self.errorMessage = error.localizedDescription }
            }
        }
    }
}
