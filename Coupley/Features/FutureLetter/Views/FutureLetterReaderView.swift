//
//  FutureLetterReaderView.swift
//  Coupley
//
//  One letter, looked up live by id, so the screen keeps up with the flip at
//  `opensAt`, the `openedAt` stamp and an unsend while it is open. What it
//  shows follows the letter's phase:
//
//    sealed for me     a live countdown. Nothing is requested: the words sit
//                      behind `request.time` in firestore.rules, so asking
//                      early could only be refused.
//    ready for me      opens it (the server-confirmed first read), then the
//                      reveal.
//    opened by me      rereads it, from the cache if need be.
//    mine              my own copy, and Unsend while it is still sealed.
//
//  The root of the sheet's `.read` route, or pushed from the hub. Both give
//  it the sheet's Done; it declares none of its own.
//

import Foundation
import SwiftUI
import UIKit

struct FutureLetterReaderView: View {

    let letterId: String
    /// The envelope as the caller saw it. It stands in only until the
    /// listener has loaded; after that, a letter missing from it is gone.
    let fallback: FutureLetter
    @ObservedObject var viewModel: FutureLetterViewModel
    let partnerName: String
    let onReplyInChat: () -> Void

    @EnvironmentObject private var notificationViewModel: NotificationViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Stage: Equatable {
        case idle
        case loading
        case revealed
        case failed(FutureLetterOpenError)
    }

    @State private var stage: Stage = .idle
    /// The words. Never `body`: that name is the View's own.
    @State private var letterBody: FutureLetterBody?
    @State private var confirmUnsend = false
    @State private var unsendFailed = false
    @State private var isUnsending = false
    /// Bumped by Try again. Part of the task key, so a retry runs inside the
    /// view's own task and is cancelled with it.
    @State private var attempt = 0

    private struct TaskKey: Equatable {
        let phase: FutureLetterPhase?
        let attempt: Int
    }

    private static let titleFont = Font.system(size: 22, weight: .bold, design: .rounded)
    private static let unsendRed = Color(red: 1.0, green: 0.45, blue: 0.45)
    private static let goneTitle = "This letter is no longer available."
    private static let goneMessage = "It may have been unsent."

    // MARK: - The letter

    /// The envelope as the listener has it now.
    private var live: FutureLetter? {
        viewModel.letter(id: letterId) ?? (viewModel.hasLoaded ? nil : fallback)
    }

    /// The envelope on screen. An unsend takes the letter out of the listener
    /// locally before the server answers, so it stays on screen through the
    /// dismissal (or the failure alert) instead of flashing "no longer
    /// available".
    private var shown: FutureLetter? {
        live ?? ((isUnsending || unsendFailed) ? fallback : nil)
    }

    /// What the crossfade below follows: the phase on screen, except that
    /// ready and opened count as one, so the openedAt stamp echoing back
    /// mid-reveal can never swap the reveal's own animation for the fade.
    private var crossfadeKey: FutureLetterPhase? {
        guard let letter = shown else { return nil }
        let phase = viewModel.phase(of: letter)
        return phase == .openedByMe ? .readyForMe : phase
    }

    // MARK: - Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Brand.Space.gutter)
            .padding(.top, 16)
            .padding(.bottom, 40)
            // A phase change (the flip at opensAt, the letter opening or
            // being unsent on the other side) arrives with no animation of
            // its own; this crossfades it.
            .animation(.easeInOut(duration: 0.3), value: crossfadeKey)
        }
        .background(Brand.bgGradient.ignoresSafeArea())
        .navigationTitle("Letter")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: TaskKey(phase: live.map { viewModel.phase(of: $0) }, attempt: attempt)) {
            await respondToPhase()
        }
        .alert("Couldn't unsend", isPresented: $unsendFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("It may have just opened, or you're offline. Try again.")
        }
    }

    @ViewBuilder
    private var content: some View {
        if let letter = shown {
            switch viewModel.phase(of: letter) {
            case .sealedForMe:
                sealedForMe(letter)
            // One branch for both, so the openedAt stamp landing just after
            // the reveal does not rebuild the screen.
            case .readyForMe, .openedByMe:
                forMe(letter)
            case .sealedByMe, .waitingForPartner, .openedByPartner:
                mine(letter)
            }
        } else {
            gonePanel
        }
    }

    // MARK: - A. Sealed, for me

    @ViewBuilder
    private func sealedForMe(_ letter: FutureLetter) -> some View {
        BrandCard(tier: .card) {
            VStack(spacing: 14) {
                sealBadge

                VStack(spacing: 4) {
                    Text("Sealed letter")
                        .font(BrandType.label)
                        .foregroundStyle(Brand.textSecondary)
                    Text("From \(partnerName)")
                        .font(Self.titleFont)
                        .foregroundStyle(Brand.textPrimary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)

                // Ticks every second so each step of the countdown lands on
                // time. The flip to ready is the view model's clock, not this.
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(spacing: 8) {
                        countdown(to: letter.opensAt, now: context.date)
                        Text("Opens \(FutureLetterClock.moment(letter.opensAt, now: context.date))")
                            .font(BrandType.body)
                            .foregroundStyle(Brand.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                }

                WaxSealStrip()
            }
            .frame(maxWidth: .infinity)
        }

        Text("It stays locked until then — on Coupley's servers, not just on this screen. When the moment comes, it'll be waiting for you on Home.")
            .font(BrandType.body)
            .foregroundStyle(Brand.textSecondary)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)

        notificationLine
    }

    /// The Memory Capsule's sealed motif: a gold-washed circle and its lock.
    private var sealBadge: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [FutureLetterStyle.gold.opacity(0.30),
                                 FutureLetterStyle.goldDeep.opacity(0.18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 76, height: 76)
            Image(systemName: "lock.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(FutureLetterStyle.gold)
        }
        .accessibilityHidden(true)
    }

    /// "12" over "days until it opens". Stacked, because the unit is too long
    /// to sit beside a 56pt number once it reaches four digits.
    private func countdown(to opensAt: Date, now: Date) -> some View {
        let remaining = FutureLetterClock.bigCountdown(to: opensAt, now: now)
        return VStack(spacing: 0) {
            Text("\(remaining.value)")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundStyle(Brand.textPrimary)
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                // A content transition only plays inside an animation; the
                // TimelineView's tick brings none of its own.
                .animation(reduceMotion ? nil : .snappy, value: remaining.value)
            Text(remaining.unit)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Brand.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    /// The "ready" reminder is a local notification on this device, so it
    /// only reaches the reader if notifications are allowed here.
    @ViewBuilder
    private var notificationLine: some View {
        switch notificationViewModel.permissionState {
        case .authorized, .provisional:
            notice("We'll let you know when it opens.", icon: "bell.fill")
        case .unknown:
            VStack(alignment: .leading, spacing: 10) {
                notice("Turn on notifications to know the moment it opens.", icon: "bell")
                BrandCTA(title: "Turn on notifications", icon: "bell.fill",
                         tier: .card, accent: FutureLetterStyle.accent) {
                    notificationViewModel.requestPermissionIfNeeded()
                }
            }
        case .denied:
            VStack(alignment: .leading, spacing: 10) {
                notice("Notifications are off. Turn them on in Settings to know the moment it opens.",
                       icon: "bell.slash")
                BrandCTA(title: "Open Settings", icon: "gearshape.fill",
                         tier: .card, accent: FutureLetterStyle.accent) {
                    openSettings()
                }
            }
        }
    }

    private func notice(_ text: String, icon: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(FutureLetterStyle.gold)
                .accessibilityHidden(true)
            Text(text)
                .font(BrandType.label)
                .foregroundStyle(Brand.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - B, C, D. Opening, failed, revealed

    @ViewBuilder
    private func forMe(_ letter: FutureLetter) -> some View {
        if stage == .revealed, let letterBody {
            VStack(alignment: .leading, spacing: 6) {
                Text("From \(partnerName)")
                    .font(Self.titleFont)
                    .foregroundStyle(Brand.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(openedLine(letter))
                    .font(BrandType.meta)
                    .foregroundStyle(Brand.textSecondary)
            }
            .transition(.opacity)

            paper(letterBody.text, signOff: "— \(partnerName)")
                .transition(paperRise)

            BrandCTA(title: "Reply in Chat", icon: "bubble.left.and.bubble.right.fill",
                     tier: .card, action: onReplyInChat)
                .transition(.opacity)
        } else {
            Image(systemName: "envelope.open.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(FutureLetterStyle.gold)
                .frame(maxWidth: .infinity)
                .padding(.top, 36)
                .accessibilityHidden(true)
                .transition(.opacity)

            if case .failed(let error) = stage {
                failurePanel(error)
                    .transition(.opacity)
            } else {
                VStack(spacing: 10) {
                    ProgressView()
                        .tint(FutureLetterStyle.accent)
                    Text("Opening…")
                        .font(BrandType.label)
                        .foregroundStyle(Brand.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .transition(.opacity)
            }
        }
    }

    /// "Sealed Nov 13 · Opened today at 9:14 AM".
    private func openedLine(_ letter: FutureLetter) -> String {
        let now = viewModel.now
        let sealed = FutureLetterClock.shortDate(letter.sealedMoment, now: now)
        // Nil only between the reveal and the listener echoing back the stamp
        // that very read wrote, so the moment is now.
        let opened = FutureLetterClock.moment(letter.openedAt ?? Date(), now: now)
        return "Sealed \(sealed) · Opened \(opened)"
    }

    /// On the first reveal the paper rises into place. With Reduce Motion it
    /// only fades in.
    private var paperRise: AnyTransition {
        reduceMotion ? .opacity : .offset(y: 40).combined(with: .opacity)
    }

    private var revealAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.25)
                     : .spring(response: 0.85, dampingFraction: 0.72)
    }

    private func failurePanel(_ error: FutureLetterOpenError) -> some View {
        let copy = Self.failureCopy(error)
        if error == .unavailable {
            return panel(title: copy.title, message: copy.message,
                         buttonTitle: "Done", buttonIcon: nil) {
                dismiss()
            }
        }
        return panel(title: copy.title, message: copy.message,
                     buttonTitle: "Try again", buttonIcon: "arrow.clockwise") {
            retry()
        }
    }

    private static func failureCopy(_ error: FutureLetterOpenError) -> (title: String, message: String) {
        switch error {
        case .notYet:
            return ("Not quite yet",
                    "Coupley's clock says this letter hasn't opened yet. If your phone's clock is ahead, it will open at the real time.")
        case .offline:
            return ("You're offline",
                    "Connect to the internet to open your letter. It's waiting for you.")
        case .unavailable:
            return (goneTitle, goneMessage)
        case .other:
            return ("Couldn't open your letter",
                    "Please try again in a moment.")
        }
    }

    // MARK: - E, F, G. Mine

    @ViewBuilder
    private func mine(_ letter: FutureLetter) -> some View {
        let phase = viewModel.phase(of: letter)

        VStack(alignment: .leading, spacing: 6) {
            Text("Your letter to \(partnerName)")
                .font(Self.titleFont)
                .foregroundStyle(Brand.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            mineStatus(letter, phase: phase)

            if phase == .sealedByMe {
                HStack(spacing: 5) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .accessibilityHidden(true)
                    Text("Only you can read it until then.")
                        .font(BrandType.meta)
                }
                .foregroundStyle(Brand.textTertiary)
                .padding(.top, 2)
            }
        }

        BrandCard(tier: .card) {
            if let letterBody {
                letterText(letterBody.text)
            } else if case .failed = stage {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Couldn't load your letter.")
                        .font(BrandType.body)
                        .foregroundStyle(Brand.textSecondary)
                    BrandCTA(title: "Try again", icon: "arrow.clockwise",
                             tier: .card, accent: FutureLetterStyle.accent) {
                        retry()
                    }
                }
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(FutureLetterStyle.accent)
                    Text("Loading your letter…")
                        .font(BrandType.body)
                        .foregroundStyle(Brand.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
        }

        if phase == .sealedByMe {
            unsendButton(letter)
        }
    }

    @ViewBuilder
    private func mineStatus(_ letter: FutureLetter, phase: FutureLetterPhase) -> some View {
        if phase == .sealedByMe {
            // Every minute, so "42 min" counts down while the screen is open.
            TimelineView(.everyMinute) { context in
                statusText(sealedStatus(letter, now: context.date))
            }
        } else {
            statusText(sentStatus(letter, phase: phase))
        }
    }

    private func statusText(_ text: String) -> some View {
        Text(text)
            .font(BrandType.body)
            .foregroundStyle(Brand.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// "Opens Thu, Dec 25 at 9:00 AM · 12 days", or "Sending…" while the seal
    /// is still a local, unacknowledged write.
    private func sealedStatus(_ letter: FutureLetter, now: Date) -> String {
        if viewModel.isPending(letter) { return "Sending…" }
        let when = FutureLetterClock.moment(letter.opensAt, now: now)
        let left = FutureLetterClock.shortCountdown(to: letter.opensAt, now: now)
        return "Opens \(when) · \(left)"
    }

    /// "Sam opened it today at 9:14 AM." once opened, otherwise
    /// "Ready since today at 9:00 AM · Sam hasn't opened it yet."
    private func sentStatus(_ letter: FutureLetter, phase: FutureLetterPhase) -> String {
        let now = viewModel.now
        if phase == .openedByPartner, let openedAt = letter.openedAt {
            return "\(partnerName) opened it \(FutureLetterClock.moment(openedAt, now: now))."
        }
        // Due by this phone's clock, but the seal itself has not reached the
        // server yet (queued offline): it is not ready for anyone.
        if viewModel.isPending(letter) { return "Sending…" }
        let ready = FutureLetterClock.moment(letter.opensAt, now: now)
        return "Ready since \(ready) · \(partnerName) hasn't opened it yet."
    }

    private func unsendButton(_ letter: FutureLetter) -> some View {
        Button(role: .destructive) {
            confirmUnsend = true
        } label: {
            HStack(spacing: 8) {
                if isUnsending {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Self.unsendRed)
                }
                Text("Unsend letter")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(Self.unsendRed)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .disabled(isUnsending)
        // On the button, so an iPad anchors the dialog here, and it goes away
        // with the button if the letter opens while it is up.
        .confirmationDialog("Unsend this letter?",
                            isPresented: $confirmUnsend,
                            titleVisibility: .visible) {
            Button("Unsend", role: .destructive) { unsend(letter) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It will be deleted for both of you. This can't be undone.")
        }
    }

    // MARK: - Shared pieces

    /// The revealed letter, signed "— Sam". My own copy (E to G) is the same
    /// card without the sign-off: I wrote it.
    private func paper(_ text: String, signOff: String) -> some View {
        BrandCard(tier: .card) {
            VStack(alignment: .leading, spacing: 16) {
                letterText(text)
                Text(signOff)
                    .font(BrandType.label)
                    .foregroundStyle(Brand.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private func letterText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 17, design: .rounded))
            .foregroundStyle(Brand.textPrimary)
            .lineSpacing(5)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// C's inline panel, and H.
    private func panel(title: String, message: String, buttonTitle: String,
                       buttonIcon: String?, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(BrandType.title)
                    .foregroundStyle(Brand.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(message)
                    .font(BrandType.body)
                    .foregroundStyle(Brand.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            BrandCTA(title: buttonTitle, icon: buttonIcon, tier: .card,
                     accent: FutureLetterStyle.accent, action: action)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: Brand.cornerStyle)
                .fill(FutureLetterStyle.accent.opacity(0.10))
        )
    }

    // MARK: - H. Removed

    private var gonePanel: some View {
        panel(title: Self.goneTitle, message: Self.goneMessage,
              buttonTitle: "Done", buttonIcon: nil) {
            dismiss()
        }
    }

    // MARK: - Loading

    /// Runs on appear and whenever the live letter's phase changes.
    private func respondToPhase() async {
        guard let letter = live else { return }
        switch viewModel.phase(of: letter) {
        case .sealedForMe:
            // No request at all: the time lock is the server's clock. A
            // refusal from an early try (a phone clock running ahead) is
            // cleared, so the real moment opens the letter by itself.
            if case .failed = stage { stage = .idle }
        case .readyForMe:
            guard stage == .idle else { return }
            // The flip runs on this phone's clock, the lock on the server's,
            // and a phone a little fast is refused at the flip. Keep asking
            // while this screen is up and the letter is ready: quietly
            // ("Opening…") through a few seconds of skew, then with "Not quite
            // yet" on screen. Closing the reader cancels this task.
            var wait: Double = 1
            var tries = 0
            while await open(letter, quietWhenNotYet: tries < 3) == .notYet {
                tries += 1
                try? await Task.sleep(for: .seconds(wait))
                if Task.isCancelled { return }
                wait = min(wait * 2, 30)
            }
        case .openedByMe, .sealedByMe, .waitingForPartner, .openedByPartner:
            if letterBody == nil, stage != .loading { await load(letter) }
        }
    }

    /// The first open. `fetchBody(for:)` asks the server only, never the
    /// cache, so the answer is the server clock's. Returns the refusal, if any.
    @discardableResult
    private func open(_ letter: FutureLetter, quietWhenNotYet: Bool = false) async -> FutureLetterOpenError? {
        stage = .loading
        switch await viewModel.fetchBody(for: letter) {
        case .success(let fetched):
            letterBody = fetched
            withAnimation(revealAnimation) { stage = .revealed }
            // The receipt only once the words are on screen. A reader closed
            // while the letter was opening has not opened it: no "Sam opened
            // your letter" for the sender, and it stays this user's hero.
            if !Task.isCancelled {
                viewModel.markOpened(letter)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
            return nil
        case .failure(let error):
            if !(quietWhenNotYet && error == .notYet) { stage = .failed(error) }
            return error
        }
    }

    /// Every later read: my own copy, or a letter I already opened. The
    /// default source, so a copy read once can be reread offline.
    private func load(_ letter: FutureLetter) async {
        stage = .loading
        let result = await viewModel.fetchBody(for: letter)
        switch result {
        case .success(let fetched):
            letterBody = fetched
            stage = .revealed
        case .failure(let error):
            stage = .failed(error)
        }
    }

    /// Re-runs `respondToPhase` through the view's task: `.idle` lets the
    /// ready branch open again, and the other branches load again.
    private func retry() {
        stage = .idle
        attempt += 1
    }

    // MARK: - Actions

    private func unsend(_ letter: FutureLetter) {
        guard !isUnsending else { return }
        isUnsending = true
        Task {
            if await viewModel.unsend(letter) {
                // isUnsending stays set: `shown` holds the letter on screen
                // through the dismissal.
                dismiss()
            } else {
                unsendFailed = true
                isUnsending = false
            }
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
