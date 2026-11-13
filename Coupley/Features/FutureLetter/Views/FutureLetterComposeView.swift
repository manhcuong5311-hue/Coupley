//
//  FutureLetterComposeView.swift
//  Coupley
//
//  Writing a Future Letter: the words, the moment it opens, and the seal.
//  Pushed from the letters hub, which also gives it the sheet's Done.
//
//  The draft lives in `FutureLetterDraftStore`, not in @State here and not on
//  the view model: Home observes the view model, so a @Published draft there
//  would re-render Home on every keystroke. Backing out keeps the draft in
//  memory for this session.
//
//  Everything this screen checks is advice. `FutureLetterViewModel.seal()`
//  checks the words and the moment again, and once the letter is sealed the
//  server's clock decides when it can be read.
//

import Foundation
import SwiftUI
import UIKit

struct FutureLetterComposeView: View {

    @ObservedObject var viewModel: FutureLetterViewModel
    @ObservedObject var draft: FutureLetterDraftStore
    let partnerName: String

    @FocusState private var editorFocused: Bool

    /// The instant the picker's range is computed from. Captured on appear
    /// rather than read live, so the range does not move on every render.
    @State private var rangeAnchor = Date()

    private static let placeholder = "Write what you want them to read that day…"
    /// The counter turns amber from here, a thousand characters before the cap.
    private static let counterWarning = 9_000

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                header

                Group {
                    editorCard
                    momentCard
                    chatCard
                }
                // seal() reads the draft as it starts and clears it on
                // success, so an edit made mid-flight would vanish unsent.
                .disabled(viewModel.isSending)

                sealSection
                    .padding(.top, 8)
            }
            .padding(.horizontal, Brand.Space.gutter)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Brand.bgGradient.ignoresSafeArea())
        .navigationTitle("New Letter")
        .navigationBarTitleDisplayMode(.inline)
        // No way out while a seal is in flight, so a failure always has this
        // screen, and the draft, to come back to.
        .navigationBarBackButtonHidden(viewModel.isSending)
        .interactiveDismissDisabled(viewModel.isSending)
        .onAppear {
            // One instant for both, so a refreshed draft always sits inside
            // the range the picker draws.
            let now = Date()
            rangeAnchor = now
            draft.refreshIfStale(now: now)
        }
        .alert("Couldn't seal your letter", isPresented: Binding(
            get: { viewModel.sendError != nil },
            set: { if !$0 { viewModel.dismissSendError() } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Check your connection and try again. Your words are still here.")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("A letter for \(partnerName)")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Brand.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text("\(partnerName) will see it's on its way, but can't read a word until the moment you choose.")
                .font(.system(size: 15, design: .rounded))
                .foregroundStyle(Brand.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - The words

    private var editorCard: some View {
        BrandCard(tier: .card) {
            VStack(alignment: .trailing, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    if draft.text.isEmpty {
                        Text(Self.placeholder)
                            .font(.system(size: 17, design: .rounded))
                            .foregroundStyle(Brand.textTertiary)
                            // TextEditor's own text inset, so the placeholder
                            // sits exactly where the first word will.
                            .padding(.top, 8)
                            .padding(.horizontal, 5)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }

                    TextEditor(text: $draft.text)
                        .font(.system(size: 17, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 220)
                        .focused($editorFocused)
                        .accessibilityLabel("Letter")
                        .accessibilityHint(draft.text.isEmpty ? Self.placeholder : "")
                }

                counter
            }
        }
    }

    private var counter: some View {
        let count = draft.text.count
        let limit = FutureLetterSchedule.maxCharacters
        return Text("\(count.formatted()) / \(limit.formatted())")
            .font(BrandType.meta)
            .monospacedDigit()
            .foregroundStyle(counterColor(count))
            .accessibilityLabel("\(count.formatted()) of \(limit.formatted()) characters")
    }

    // MARK: - The moment

    private var momentCard: some View {
        BrandCard(tier: .card) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Opens on")
                    .font(BrandType.label)
                    .foregroundStyle(Brand.textSecondary)
                    .accessibilityAddTraits(.isHeader)

                DatePicker("Opens on",
                           selection: $draft.opensAt,
                           in: pickerRange,
                           displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .tint(FutureLetterStyle.accent)

                // Re-evaluated every minute as well as on every change, so a
                // pick that goes stale while the screen sits open turns into
                // the warning on its own. It reads the live clock, as seal()
                // does, rather than the tick's own date.
                TimelineView(.everyMinute) { _ in
                    momentCaption(now: Date())
                }
            }
        }
    }

    private var pickerRange: ClosedRange<Date> {
        FutureLetterSchedule.earliest(now: rangeAnchor)...FutureLetterSchedule.latest(now: rangeAnchor)
    }

    private func momentCaption(now: Date) -> some View {
        let caption: String
        if isMomentValid(now: now) {
            let when = FutureLetterClock.moment(chosenMoment, now: now)
            caption = "Opens \(when) your time. \(partnerName) sees it in their own time zone."
        } else {
            caption = tooSoonCopy
        }
        return Text(caption)
            .font(BrandType.body)
            .foregroundStyle(Brand.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - The chat note

    private var chatCard: some View {
        BrandCard(tier: .card) {
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Tell \(partnerName) in chat", isOn: $draft.tellInChat)
                    .font(BrandType.title)
                    .foregroundStyle(Brand.textPrimary)
                    .tint(FutureLetterStyle.accent)

                Text("Posts \u{201C}\(FutureLetterViewModel.chatNote)\u{201D} in your chat.")
                    .font(BrandType.body)
                    .foregroundStyle(Brand.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - The seal

    private var sealSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .accessibilityHidden(true)
                Text("Once it's sealed you can't edit it. You can unsend it until it opens.")
                    .font(BrandType.meta)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Brand.textTertiary)

            // Re-evaluated every minute too, for the same reason as the
            // caption under the picker.
            TimelineView(.everyMinute) { _ in
                sealButton(now: Date())
            }
        }
    }

    private func sealButton(now: Date) -> some View {
        let hint = disabledHint(now: now)
        return VStack(spacing: 10) {
            // The sheet's one filled accent.
            BrandCTA(title: "Seal letter",
                     icon: "lock.fill",
                     tier: .hero,
                     accent: FutureLetterStyle.accent,
                     isEnabled: canSeal(now: now),
                     isBusy: viewModel.isSending) {
                sealLetter()
            }

            if let hint {
                Text(hint)
                    .font(BrandType.body)
                    .foregroundStyle(Brand.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: hint)
    }

    private func sealLetter() {
        editorFocused = false
        Task {
            // On success the view model closes the sheet, and Home's pinned
            // row takes over from here.
            if await viewModel.seal() {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }

    // MARK: - Checks (the ones seal() makes)

    /// The words as seal() will send them.
    private var trimmedText: String {
        draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The moment as seal() will store it: the picked minute, seconds dropped.
    private var chosenMoment: Date {
        FutureLetterSchedule.normalized(draft.opensAt)
    }

    private func isMomentValid(now: Date) -> Bool {
        FutureLetterSchedule.isValid(chosenMoment, now: now)
    }

    private func canSeal(now: Date) -> Bool {
        let text = trimmedText
        return !text.isEmpty
            && text.count <= FutureLetterSchedule.maxCharacters
            && isMomentValid(now: now)
    }

    /// Why Seal is disabled, shown under it. Nil while it can be pressed.
    private func disabledHint(now: Date) -> String? {
        if trimmedText.isEmpty { return "Write something first." }
        if trimmedText.count > FutureLetterSchedule.maxCharacters {
            return "Make it \(FutureLetterSchedule.maxCharacters.formatted()) characters or fewer to seal it."
        }
        if !isMomentValid(now: now) { return tooSoonCopy }
        return nil
    }

    /// Amber from 9,000; red past the limit. The text itself is never cut:
    /// rewriting it mid-word breaks Vietnamese input and moves the caret.
    private func counterColor(_ count: Int) -> Color {
        if count > FutureLetterSchedule.maxCharacters { return Color(red: 1.0, green: 0.45, blue: 0.45) }
        return count >= Self.counterWarning ? FutureLetterStyle.accent : Brand.textTertiary
    }

    private var tooSoonCopy: String {
        "Pick a time at least \(FutureLetterSchedule.minimumLeadDescription) from now."
    }
}

// MARK: - Preview

#if DEBUG
/// Owns its view model the way ContentView does, so the draft survives canvas
/// updates. On `.demo` the view model is unavailable: no listener starts, and
/// Seal letter returns without writing anything.
private struct FutureLetterComposePreview: View {
    @StateObject private var viewModel = FutureLetterViewModel(session: .demo)

    var body: some View {
        NavigationStack {
            FutureLetterComposeView(viewModel: viewModel, draft: viewModel.draft, partnerName: "Sam")
        }
    }
}

#Preview {
    FutureLetterComposePreview()
}
#endif
