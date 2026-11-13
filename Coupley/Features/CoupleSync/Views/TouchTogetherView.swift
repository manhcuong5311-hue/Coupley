//
//  TouchTogetherView.swift
//  Coupley
//
//  Both partners press and hold a circle. While only one is holding, the
//  circle waits. The moment both are holding, the two rings meet and both
//  phones buzz — for as long as neither lets go.
//
//  The signal rides on the shared `liveState/room` document: a timestamp per
//  user, refreshed a couple of times a second while held, read through a
//  short freshness window. Nothing has to be cleaned up if an app is killed
//  mid-hold; the timestamp simply goes stale and the ring lets go.
//
//  Round-trip latency over Firestore is a few hundred milliseconds, so this
//  will never feel like a wire. It feels like presence, which is the point.
//

import SwiftUI
import UIKit
import Combine
import FirebaseFirestore

// MARK: - View Model

@MainActor
final class TouchTogetherViewModel: ObservableObject {

    @Published private(set) var iAmTouching = false
    @Published private(set) var partnerIsTouching = false

    var bothTouching: Bool { iAmTouching && partnerIsTouching }

    private var session: UserSession
    private let liveRoom: LiveRoomServicing
    private var listener: ListenerRegistration?
    /// Keeps refreshing the timestamp while the finger stays down.
    private var holdTask: Task<Void, Never>?
    /// Drops `partnerIsTouching` when their refreshes stop arriving.
    private var partnerExpiry: Task<Void, Never>?
    private var buzzTask: Task<Void, Never>?

    init(session: UserSession, liveRoom: LiveRoomServicing = FirestoreLiveRoomService()) {
        self.session = session
        self.liveRoom = liveRoom
    }

    /// `UserSession.demo` reports `isPaired == true` behind a placeholder
    /// couple id, and the dashboard holds it until a real session arrives.
    private var hasRealSession: Bool {
        session.isPaired && session.coupleId != UserSession.demo.coupleId
    }

    /// Point this at the live session. The owner holds the view model for the
    /// whole screen's lifetime, so this replaces re-creating it — which is
    /// what made the listener disappear roughly every 60 seconds.
    func rebind(session: UserSession) {
        guard session.coupleId != self.session.coupleId
                || session.userId != self.session.userId else { return }
        stop()
        self.session = session
    }

    deinit {
        listener?.remove()
        holdTask?.cancel()
        partnerExpiry?.cancel()
        buzzTask?.cancel()
    }

    // MARK: Lifecycle

    func start() {
        guard hasRealSession, listener == nil else { return }
        listener = liveRoom.observe(coupleId: session.coupleId) { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                self.applyPartner(state.isTouching(self.session.partnerId))
            }
        }
    }

    func stop() {
        listener?.remove(); listener = nil
        endTouch()
        partnerExpiry?.cancel(); partnerExpiry = nil
    }

    private func applyPartner(_ touching: Bool) {
        partnerIsTouching = touching
        partnerExpiry?.cancel()
        guard touching else { updateBuzzing(); return }
        partnerExpiry = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(LiveRoomState.touchWindow * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.partnerIsTouching = false
                self?.updateBuzzing()
            }
        }
        updateBuzzing()
    }

    // MARK: Touch

    func beginTouch() {
        guard hasRealSession, !iAmTouching else { return }
        iAmTouching = true
        updateBuzzing()

        holdTask = Task { [liveRoom, session] in
            while !Task.isCancelled {
                await liveRoom.markTouching(coupleId: session.coupleId, userId: session.userId)
                try? await Task.sleep(nanoseconds: 700_000_000)
            }
        }
    }

    func endTouch() {
        holdTask?.cancel(); holdTask = nil
        guard iAmTouching else { return }
        iAmTouching = false
        updateBuzzing()
        Task { [liveRoom, session] in
            await liveRoom.clearTouching(coupleId: session.coupleId, userId: session.userId)
        }
    }

    // MARK: Haptics

    /// A repeating pulse while the contact lasts — a single tap would be over
    /// before the other person noticed it.
    private func updateBuzzing() {
        let shouldBuzz = bothTouching
        if shouldBuzz, buzzTask == nil {
            buzzTask = Task { @MainActor in
                let generator = UIImpactFeedbackGenerator(style: .soft)
                generator.prepare()
                while !Task.isCancelled {
                    generator.impactOccurred(intensity: 0.9)
                    try? await Task.sleep(nanoseconds: 520_000_000)
                }
            }
        } else if !shouldBuzz {
            buzzTask?.cancel()
            buzzTask = nil
        }
    }
}

// MARK: - View

struct TouchTogetherView: View {

    let partnerName: String
    @ObservedObject var viewModel: TouchTogetherViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var ripple = false

    var body: some View {
        ZStack {
            Brand.bgGradient.ignoresSafeArea()

            VStack(spacing: 28) {
                header
                Spacer()
                circle
                Spacer()
                caption
            }
            .padding(.vertical, 28)
        }
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
    }

    private var accent: Color {
        viewModel.bothTouching
            ? Color(red: 1.0, green: 0.42, blue: 0.56)
            : Brand.accentStart
    }

    private var header: some View {
        HStack {
            Button("Close") {
                viewModel.endTouch()
                dismiss()
            }
            .font(.system(size: 15, weight: .medium, design: .rounded))
            .foregroundStyle(Brand.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 22)
    }

    private var circle: some View {
        ZStack {
            // Partner's ring — only there while they are holding.
            Circle()
                .strokeBorder(accent.opacity(0.9), lineWidth: 3)
                .frame(width: viewModel.partnerIsTouching ? 210 : 255,
                       height: viewModel.partnerIsTouching ? 210 : 255)
                .opacity(viewModel.partnerIsTouching ? 1 : 0)

            // Contact glow.
            Circle()
                .fill(accent.opacity(0.22))
                .frame(width: 230, height: 230)
                .scaleEffect(ripple ? 1.18 : 0.92)
                .opacity(viewModel.bothTouching ? 1 : 0)
                .animation(
                    .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                    value: ripple
                )

            // Your own circle.
            Circle()
                .fill(
                    LinearGradient(colors: [accent, accent.opacity(0.65)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: viewModel.iAmTouching ? 180 : 150,
                       height: viewModel.iAmTouching ? 180 : 150)
                .shadow(color: accent.opacity(0.45), radius: 24, y: 6)
                .overlay(
                    Image(systemName: viewModel.bothTouching ? "heart.fill" : "hand.tap.fill")
                        .font(.system(size: viewModel.bothTouching ? 46 : 34, weight: .semibold))
                        .foregroundStyle(.white)
                )
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7),
                   value: viewModel.iAmTouching)
        .animation(.spring(response: 0.4, dampingFraction: 0.7),
                   value: viewModel.partnerIsTouching)
        .contentShape(Circle())
        // A 0-distance drag is the standard way to get press-and-release:
        // `onLongPressGesture` fires once and tells you nothing about the lift.
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !viewModel.iAmTouching {
                        viewModel.beginTouch()
                        ripple = true
                    }
                }
                .onEnded { _ in
                    viewModel.endTouch()
                    ripple = false
                }
        )
    }

    private var caption: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Brand.textPrimary)
                .animation(nil, value: title)
            Text(subtitle)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Brand.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
        }
        .padding(.bottom, 10)
    }

    private var title: String {
        if viewModel.bothTouching { return "Together" }
        if viewModel.partnerIsTouching { return "\(partnerName) is holding" }
        if viewModel.iAmTouching { return "Waiting for \(partnerName)…" }
        return "Touch together"
    }

    private var subtitle: String {
        if viewModel.bothTouching { return "Both of you are holding on." }
        if viewModel.partnerIsTouching { return "Press and hold to meet them." }
        if viewModel.iAmTouching { return "Keep holding — they'll feel it when they join." }
        return "Press and hold. When \(partnerName) holds too, you'll both feel it."
    }
}
