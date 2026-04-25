//
//  NudgeViewModel.swift
//  Coupley
//
//  Persistent nudge listener that survives tab switches.
//  Lives in ContentView so it receives nudges regardless of which tab is active.
//

import Foundation
import SwiftUI
import Combine
import FirebaseFirestore

@MainActor
final class NudgeViewModel: ObservableObject {

    @Published var incomingNudge: Nudge? = nil

    private let session: UserSession
    private let nudgeService: NudgeServicing
    private var listener: ListenerRegistration?
    private var dismissTask: Task<Void, Never>?
    private var lastShownNudgeId: String?

    init(session: UserSession,
         nudgeService: NudgeServicing? = nil) {
        self.session = session
        self.nudgeService = nudgeService ?? FirestoreNudgeService()
    }

    deinit {
        listener?.remove()
        dismissTask?.cancel()
    }

    // MARK: - Lifecycle

    func startListening() {
        guard session.isPaired, listener == nil else { return }
        listener = nudgeService.listenForIncoming(
            coupleId: session.coupleId,
            toUserId: session.userId
        ) { [weak self] nudges in
            Task { @MainActor [weak self] in
                guard let self, let latest = nudges.first else { return }
                // Skip nudges we already showed this session
                if self.lastShownNudgeId == latest.firestoreId { return }
                self.lastShownNudgeId = latest.firestoreId
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                    self.incomingNudge = latest
                }
                self.scheduleDismiss()
            }
        }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
        dismissTask?.cancel()
    }

    func dismiss() {
        dismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.25)) {
            incomingNudge = nil
        }
    }

    private func scheduleDismiss() {
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 s
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                self.incomingNudge = nil
            }
        }
    }
}
