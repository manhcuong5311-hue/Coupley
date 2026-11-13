//
//  MemoryDetailSheet.swift
//  Coupley
//
//  One memory, read in full: the photo, the story, the feelings and who
//  wrote it. Tapping a memory on Journey opens this.
//
//  A sealed capsule shows only its envelope: a card-tier countdown (a locked
//  state is never a hero), and nothing of the note, photo, feelings or
//  attribution. Edit is offered only where `canEdit` allows it, so the
//  partner of a capsule's author cannot read it early through the editor.
//
//  The sheet closes itself when its memory leaves the list (deleted from the
//  nested editor, or on the partner's phone), so a stale copy can never be
//  saved back and re-create it.
//

import Foundation
import SwiftUI
import UIKit

// MARK: - Detail Sheet

struct MemoryDetailSheet: View {

    @ObservedObject var viewModel: TimeTreeViewModel
    let memory: TimeMemory
    /// Its editor is up. Owned by the presenter, so a capsule reminder that
    /// arrives meanwhile waits instead of closing the editor mid-edit.
    @Binding var showEditor: Bool
    /// Runs once the editor has fully closed (its sheet's onDismiss), where
    /// the presenter can safely present or dismiss sheets again.
    var onEditorDismissed: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The lock glyph's well and the kind emoji's well grow with the text.
    @ScaledMetric(relativeTo: .title2) private var sealSize: CGFloat = 64
    @ScaledMetric(relativeTo: .title2) private var emojiSize: CGFloat = 46

    private var current: TimeMemory {
        viewModel.memories.first(where: { $0.id == memory.id }) ?? memory
    }

    private var isLocked: Bool { current.isLocked(at: viewModel.now) }

    /// False once the memory is gone from the shared list.
    private var isStillListed: Bool {
        viewModel.memories.contains { $0.id == memory.id }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Brand.Space.sibling) {
                    if isLocked {
                        lockedCard
                    } else {
                        openContent
                    }
                }
                .padding(.horizontal, Brand.Space.gutter)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
            .background(Brand.bgGradient.ignoresSafeArea())
            .navigationTitle(isLocked
                             ? Text("Capsule", comment: "Title of the detail sheet for a sealed memory capsule")
                             : Text("Memory", comment: "Title of the detail sheet for one memory"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Close", comment: "Toolbar button: close this sheet")
                    }
                    .foregroundStyle(Brand.textSecondary)
                }
                // A sealed capsule is editable by its author only: the
                // editor pre-fills everything the seal is hiding.
                if viewModel.canEdit(current) {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showEditor = true
                        } label: {
                            Text("Edit", comment: "Toolbar button: edit this memory")
                        }
                        .foregroundStyle(Brand.accentStart)
                    }
                }
            }
            .sheet(isPresented: $showEditor, onDismiss: onEditorDismissed) {
                MemoryEditorSheet(viewModel: viewModel, mode: .edit(current))
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            // Deleted from the editor above, or by the partner: close, taking
            // the editor with it, before a Save could write it back.
            .onChange(of: isStillListed) { _, stillListed in
                if !stillListed { dismiss() }
            }
        }
    }

    // MARK: - Sealed

    private var lockedCard: some View {
        VStack(alignment: .leading, spacing: Brand.Space.sibling) {
            BrandCard(tier: .card) {
                VStack(spacing: 14) {
                    Image(systemName: "lock.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(FutureLetterStyle.gold)
                        .frame(width: sealSize, height: sealSize)
                        .wellBackground(in: .card, radius: sealSize / 2)
                        .accessibilityHidden(true)

                    VStack(spacing: 4) {
                        Text("Sealed capsule")
                            .font(JourneyFont.label)
                            .foregroundStyle(JourneyStyle.goldText)
                        Text(current.title.isEmpty
                             ? String(localized: "A moment for you both", comment: "Title of a memory capsule that has no title")
                             : current.title)
                            .font(JourneyFont.title)
                            .foregroundStyle(Brand.textPrimary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)

                    if let unlockDate = current.unlockDate {
                        countdown(to: unlockDate)

                        Text("Opens \(unlockDate.formatted(date: .long, time: .omitted))",
                             comment: "When a sealed memory capsule opens. %@ is a date such as 'January 26, 2027'.")
                            .font(JourneyFont.body)
                            .foregroundStyle(Brand.textSecondary)
                            .multilineTextAlignment(.center)
                    }

                    WaxSealStrip()
                }
                .frame(maxWidth: .infinity)
            }

            Text("Kept out of sight in the app until the unlock day, for both of you.")
                .font(JourneyFont.body)
                .foregroundStyle(Brand.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }

    /// "12" over "days until it opens", on the Journey clock, which ticks
    /// every minute while the tab is up.
    private func countdown(to unlockDate: Date) -> some View {
        let remaining = FutureLetterClock.bigCountdown(to: unlockDate, now: viewModel.now)
        return VStack(spacing: 2) {
            Text(remaining.value, format: .number)
                .font(JourneyFont.number)
                .foregroundStyle(Brand.textPrimary)
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                // A content transition only plays inside an animation.
                .animation(reduceMotion ? nil : .snappy, value: remaining.value)
            Text(remaining.unit)
                .font(JourneyFont.caption)
                .foregroundStyle(Brand.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: - Open

    @ViewBuilder
    private var openContent: some View {
        if let urlString = current.photoURL, let url = URL(string: urlString) {
            photo(url)
        }

        header

        if let note = current.note, !note.isEmpty {
            noteCard(note)
        }

        if !current.emotions.isEmpty {
            emotionsCard
        }

        if let attribution = current.attribution, !attribution.isEmpty {
            attributionLine(attribution)
        }
    }

    private func photo(_ url: URL) -> some View {
        let radius = SurfaceTier.card.radius
        return CachedAsyncImage(url: url, maxPixelSize: 1200) { phase in
            ZStack {
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(Brand.textTertiary)
                default:
                    ProgressView()
                        .tint(Brand.textTertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 240)
            .clipped()
        }
        .wellBackground(in: .quiet, radius: radius)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: Brand.cornerStyle))
        .shadow(color: .black.opacity(0.10), radius: 12, y: 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Photo", comment: "VoiceOver: the memory's photo"))
        .accessibilityAddTraits(.isImage)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(current.kind.emoji)
                .font(.title2)
                .frame(width: emojiSize, height: emojiSize)
                .wellBackground(in: .quiet, radius: emojiSize / 2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(current.title.isEmpty ? current.kind.displayName : current.title)
                    .font(JourneyFont.display)
                    .foregroundStyle(Brand.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Text(current.formattedDate())
                    .font(JourneyFont.body)
                    .foregroundStyle(Brand.textSecondary)

                if current.isUnlockedCapsule(at: viewModel.now) {
                    openedBadge
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Gold glyph, gold-for-text label, on the page's own surface: the text
    /// gold is only measured against the palette's surfaces, never a tint.
    private var openedBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: "envelope.open.fill")
                .font(JourneyFont.meta)
                .foregroundStyle(FutureLetterStyle.gold)
                .accessibilityHidden(true)
            Text("Capsule opened")
                .font(JourneyFont.meta)
                .foregroundStyle(JourneyStyle.goldText)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .wellBackground(in: .quiet, radius: 10)
    }

    private func noteCard(_ note: String) -> some View {
        BrandCard(tier: .card) {
            VStack(alignment: .leading, spacing: 8) {
                Text("The story", comment: "Header above a memory's written note")
                    .font(JourneyFont.label)
                    .foregroundStyle(Brand.textSecondary)
                    .accessibilityAddTraits(.isHeader)

                Text(note)
                    .font(JourneyFont.body)
                    .foregroundStyle(Brand.textPrimary)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }

    private var emotionsCard: some View {
        BrandCard(tier: .card) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Felt like", comment: "Header above a memory's feeling tags, e.g. 'Felt like: Happy, Loved'")
                    .font(JourneyFont.label)
                    .foregroundStyle(Brand.textSecondary)

                FlowLayout(spacing: 8) {
                    ForEach(current.emotions, id: \.self) { emotion in
                        HStack(spacing: 5) {
                            Text(emotion.emoji)
                                .accessibilityHidden(true)
                            Text(emotion.displayName)
                        }
                        .font(JourneyFont.caption)
                        .foregroundStyle(Brand.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .wellBackground(in: .card, radius: 12)
                    }
                }
            }
        }
        // "Felt like, Nervous, Joyful, Tender": the names, never the emoji.
        .accessibilityElement(children: .combine)
    }

    private func attributionLine(_ attribution: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "person.2.fill")
                .font(JourneyFont.meta)
                .foregroundStyle(Brand.textTertiary)
                .accessibilityHidden(true)
            Text(attribution)
                .font(JourneyFont.caption)
                .foregroundStyle(Brand.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }
}
