//
//  FutureLetterSheet.swift
//  Coupley
//
//  The letters sheet. ContentView presents it with `.sheet(item:)` on
//  `FutureLetterViewModel.route`, so any tab can open it and it outlives
//  whatever opened it: the hero card leaves the hero slot the moment
//  `openedAt` is stamped, mid-reading.
//
//    .hub       FutureLettersView — every letter, both ways, and the way to
//               write a new one. A row pushes the reader; the CTA pushes
//               Compose.
//    .compose   FutureLetterComposeView as the root, one tap from Home's
//               masthead, Chat's + menu or an anniversary on Journey.
//    .read(l)   FutureLetterReaderView as the root, straight from Home's
//               pinned row or hero card.
//
//  Every screen in the stack shows exactly one Done, which clears `route`:
//  the same thing a swipe-down does. See `FutureLetterDoneToolbar`.
//

import SwiftUI
import UIKit

// MARK: - Sheet

struct FutureLetterSheet: View {

    let route: FutureLetterViewModel.Route
    @ObservedObject var viewModel: FutureLetterViewModel
    let partnerName: String
    let onReplyInChat: () -> Void

    var body: some View {
        NavigationStack {
            switch route {
            case .hub:
                // The hub puts Done on itself and on both screens it pushes,
                // so nothing is added here: a second one would show twice.
                FutureLettersView(viewModel: viewModel,
                                  partnerName: partnerName,
                                  onReplyInChat: onReplyInChat)
            case .compose:
                FutureLetterComposeView(viewModel: viewModel,
                                        draft: viewModel.draft,
                                        partnerName: partnerName)
                    .modifier(FutureLetterDoneToolbar(viewModel: viewModel))
            case .read(let letter):
                FutureLetterReaderView(letterId: letter.id,
                                       fallback: letter,
                                       viewModel: viewModel,
                                       partnerName: partnerName,
                                       onReplyInChat: onReplyInChat)
                    .modifier(FutureLetterDoneToolbar(viewModel: viewModel))
            }
        }
    }
}

// MARK: - Hub

/// Every letter, for you and from you, plus the way to write a new one.
/// The root of the sheet's stack for `.hub`.
struct FutureLettersView: View {

    @ObservedObject var viewModel: FutureLetterViewModel
    let partnerName: String
    let onReplyInChat: () -> Void

    @State private var isComposing = false
    @State private var reading: FutureLetter?

    var body: some View {
        ZStack {
            Brand.bgGradient.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Brand.Space.zone) {
                    // Outlined: on this screen nothing is a hero, so there is
                    // no filled accent. Compose owns the sheet's one fill.
                    BrandCTA(title: "Write a letter",
                             icon: "square.and.pencil",
                             tier: .card,
                             accent: FutureLetterStyle.accent) {
                        // Same rule as `compose()` with no moment of its own.
                        viewModel.draft.dropUnusedPreset()
                        isComposing = true
                    }

                    content
                        // A letter sealed, unsent or opened while the hub is
                        // up slides into place instead of jumping.
                        .animation(.spring(response: 0.45, dampingFraction: 0.85),
                                   value: viewModel.letters)
                }
                .padding(.horizontal, Brand.Space.gutter)
                .padding(.top, Brand.Space.sibling)
                .padding(.bottom, Brand.Space.zone)
            }
        }
        .navigationTitle("Future Letters")
        .navigationBarTitleDisplayMode(.inline)
        .modifier(FutureLetterDoneToolbar(viewModel: viewModel))
        // Toolbar items do not follow a push, so each pushed screen gets its
        // own Done here. Neither Compose nor the reader declares one.
        .navigationDestination(isPresented: $isComposing) {
            FutureLetterComposeView(viewModel: viewModel,
                                    draft: viewModel.draft,
                                    partnerName: partnerName)
                .modifier(FutureLetterDoneToolbar(viewModel: viewModel))
        }
        .navigationDestination(item: $reading) { letter in
            // The reader follows the live letter by id; `letter` is only the
            // snapshot from the moment of the tap.
            FutureLetterReaderView(letterId: letter.id,
                                   fallback: letter,
                                   viewModel: viewModel,
                                   partnerName: partnerName,
                                   onReplyInChat: onReplyInChat)
                .modifier(FutureLetterDoneToolbar(viewModel: viewModel))
        }
    }

    // MARK: State

    @ViewBuilder
    private var content: some View {
        if !viewModel.hasLoaded {
            loadingState
        } else {
            VStack(alignment: .leading, spacing: Brand.Space.zone) {
                // A failed listener keeps the letters it already delivered,
                // so they stay readable under the error.
                if viewModel.listenError != nil {
                    errorState
                }

                if viewModel.letters.isEmpty {
                    // An invitation to write would be a guess while the list
                    // could not be loaded.
                    if viewModel.listenError == nil {
                        emptyState
                    }
                } else {
                    // `viewModel.now` decides each phase and only moves at
                    // boundaries; the countdown text needs a minute clock.
                    TimelineView(.everyMinute) { context in
                        sections(now: context.date)
                    }
                }
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(FutureLetterStyle.accent)
            Text("Finding your letters…")
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(Brand.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var errorState: some View {
        BrandCard(tier: .card) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(FutureLetterStyle.accent)
                        .accessibilityHidden(true)

                    Text("Couldn't load your letters. Check your connection and try again.")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // A listener that has failed stays registered, so the
                // idempotent `start()` alone would not listen again.
                BrandCTA(title: "Try again",
                         tier: .card,
                         accent: FutureLetterStyle.accent) {
                    viewModel.stop()
                    viewModel.start()
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [FutureLetterStyle.gold.opacity(0.30),
                                     FutureLetterStyle.goldDeep.opacity(0.18)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                Image(systemName: "envelope.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(FutureLetterStyle.gold)
            }
            .frame(width: 76, height: 76)
            .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Write to them, for later")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Text("Pick a day — an anniversary, a birthday, the end of a hard week. It's pinned on Home for both of you, and \(partnerName) can open it only when that moment comes.")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
    }

    // MARK: Sections

    private func sections(now: Date) -> some View {
        let forMe = viewModel.lettersForMe
        let fromMe = viewModel.lettersFromMe
        return VStack(alignment: .leading, spacing: Brand.Space.zone) {
            if !forMe.isEmpty {
                section("For you", letters: forMe, now: now)
            }
            if !fromMe.isEmpty {
                section("From you", letters: fromMe, now: now)
            }
        }
    }

    private func section(_ title: LocalizedStringResource, letters: [FutureLetter], now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Not an Eyebrow, and not uppercase: the screen's labels stay
            // plain so tracked small caps keep meaning one thing.
            Text(title)
                .font(BrandType.label)
                .foregroundStyle(Brand.textTertiary)
                .padding(.leading, 4)
                .padding(.bottom, 2)
                .accessibilityAddTraits(.isHeader)

            ForEach(letters) { letter in
                row(letter, now: now)
            }
        }
    }

    /// Same chip, same press and haptic as Home's pinned row. The row content
    /// is already one VoiceOver element, with "Shows the letter." as its hint.
    private func row(_ letter: FutureLetter, now: Date) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            reading = letter
        } label: {
            BrandCard(tier: .chip) {
                FutureLetterRowContent(letter: letter,
                                       phase: viewModel.phase(of: letter),
                                       partnerName: partnerName,
                                       now: now,
                                       isPending: viewModel.isPending(letter))
            }
        }
        .buttonStyle(BouncyButtonStyle(scale: 0.96))
    }
}

// MARK: - Done

/// The sheet's way out: clears `route`, the same as a swipe-down.
///
/// A toolbar item belongs to the screen that declares it and does not follow
/// a push, so every screen in this stack needs its own, and must get exactly
/// one. The hub adds it to itself and to the two screens it pushes; the sheet
/// adds it to a reader it shows as its root. Compose and the reader add none.
private struct FutureLetterDoneToolbar: ViewModifier {

    @ObservedObject var viewModel: FutureLetterViewModel

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.route = nil
                } label: {
                    Text("Done", comment: "Toolbar button that closes the letters sheet.")
                }
                .foregroundStyle(viewModel.isSending ? Brand.textTertiary : Brand.accentStart)
                // Compose hides Back and blocks the swipe-down while a
                // seal is in flight; Done must not be a third way out,
                // or a failure would have no screen left to show it.
                .disabled(viewModel.isSending)
            }
        }
    }
}
