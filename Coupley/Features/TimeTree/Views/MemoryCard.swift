//
//  MemoryCard.swift
//  Coupley
//
//  One memory on Journey's Timeline: title, date, note, feelings and who it
//  is from, with its photo as a thumbnail on the right.
//
//  Only opened memories reach this card. A capsule that is still sealed is a
//  chip in the Timeline's "Sealed for later" group (JourneyTimelineCapsuleRow),
//  so there is no locked state here to redact.
//
//  Two buttons, never one inside the other: the card's content opens the
//  memory, and a memory without a photo offers "Add photo" underneath. A
//  memory without a photo draws no empty photo box; its text takes the width.
//

import Foundation
import SwiftUI

// MARK: - Memory Card

struct MemoryCard: View {

    let memory: TimeMemory
    let now: Date
    let onTap: () -> Void
    /// Nil hides "Add photo" even when the memory has none.
    let onAddPhoto: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.displayScale) private var displayScale

    /// The main button's press, so the whole card gives under it the way it
    /// did when the card was one button.
    @State private var isPressed = false

    init(memory: TimeMemory,
         now: Date,
         onTap: @escaping () -> Void,
         onAddPhoto: (() -> Void)? = nil) {
        self.memory = memory
        self.now = now
        self.onTap = onTap
        self.onAddPhoto = onAddPhoto
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onTap) {
                summary
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(MemoryCardPressStyle(isPressed: $isPressed))
            // One element, read as sentences, with no emoji names:
            // "First Kiss, May 1, 2026. Nervous, Joyful, Tender. Has a photo."
            .accessibilityLabel(spokenLabel)
            .accessibilityHint("Shows the memory.")

            if photoURL == nil, let onAddPhoto {
                addPhotoButton(action: onAddPhoto)
            }
        }
        .modifier(TierContainer(tier: .card))
        // BouncyButtonStyle's press, applied to the card rather than to the
        // content inside it.
        .scaleEffect(isPressed ? 0.98 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isPressed)
    }

    // MARK: - Summary

    private var isLarge: Bool { dynamicTypeSize.isAccessibilitySize }

    private var photoURL: URL? {
        guard let string = memory.photoURL, !string.isEmpty else { return nil }
        return URL(string: string)
    }

    /// Text on the left and the thumbnail on the right. At the accessibility
    /// text sizes the thumbnail moves under the text, which keeps the full
    /// width and its title stays on the card's first line.
    private var summary: some View {
        let layout = isLarge
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 14))
        return layout {
            textColumn
            if let photoURL {
                thumbnail(url: photoURL)
            }
        }
    }

    private var textColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let note = memory.note, !note.isEmpty {
                Text(note)
                    .font(JourneyFont.body)
                    .foregroundStyle(Brand.textPrimary.opacity(0.92))
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !memory.emotions.isEmpty {
                emotionChips
            }

            if let attribution = memory.attribution, !attribution.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "person.2.fill")
                        .imageScale(.small)
                    Text(attribution)
                }
                .font(JourneyFont.meta)
                .foregroundStyle(Brand.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Header (kind, title, date, capsule badge)

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(memory.kind.emoji)
                .font(.system(size: 18))
                .frame(width: 38, height: 38)
                .background(Circle().fill(Brand.accentStart.opacity(0.12)))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(displayTitle)
                    .font(JourneyFont.title)
                    .foregroundStyle(Brand.textPrimary)
                    .lineLimit(isLarge ? 4 : 2)
                    .multilineTextAlignment(.leading)

                Text(longDate)
                    .font(JourneyFont.meta)
                    .foregroundStyle(Brand.textSecondary)

                if memory.isUnlockedCapsule(at: now) {
                    capsuleOpenedBadge
                        .padding(.top, 3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Gold text through `JourneyStyle.goldText`, which stays readable on the
    /// Light palettes; the glyph keeps the capsule's icon gold.
    private var capsuleOpenedBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "lock.open.fill")
                .foregroundStyle(FutureLetterStyle.gold)
            Text("Capsule opened")
                .foregroundStyle(JourneyStyle.goldText)
        }
        .font(JourneyFont.meta)
    }

    // MARK: - Emotion chips

    private var emotionChips: some View {
        FlowLayout(spacing: 6) {
            ForEach(memory.emotions, id: \.self) { emotion in
                HStack(spacing: 4) {
                    Text(emotion.emoji)
                        .font(JourneyFont.meta)
                    Text(emotion.displayName)
                        .font(JourneyFont.caption)
                }
                .foregroundStyle(Brand.textSecondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Capsule().fill(Brand.surfaceMid))
            }
        }
    }

    // MARK: - Thumbnail

    private static let thumbnailSide: CGFloat = 84

    /// The longest side to decode, in pixels: never the photo's full size.
    /// `maxPixelSize` bounds the LONGEST side and the thumbnail is filled and
    /// cropped, so 84pt × scale alone (252 px at 3x) would leave a 4:3
    /// photo's short side at 189 px, stretched to 252. A third more covers
    /// 4:3 at full sharpness: 336 px at 3x, about 340 KB decoded.
    private var thumbnailPixelSize: CGFloat {
        (Self.thumbnailSide * displayScale * 4 / 3).rounded(.up)
    }

    /// Decoded small, never at the photo's full size. The well shows while
    /// it loads, so the card keeps its shape.
    private func thumbnail(url: URL) -> some View {
        CachedAsyncImage(url: url, maxPixelSize: thumbnailPixelSize) { phase in
            ZStack {
                if case .success(let image) = phase {
                    image
                        .resizable()
                        .scaledToFill()
                } else if case .failure = phase {
                    Image(systemName: "photo")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(Brand.textTertiary)
                }
            }
            .frame(width: Self.thumbnailSide, height: Self.thumbnailSide)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: Brand.cornerStyle))
        }
        .wellBackground(in: .card, radius: 14)
        .accessibilityHidden(true)
    }

    // MARK: - Add photo

    /// Its own button below the card's content, never inside it. The padding
    /// only widens the tap target.
    private func addPhotoButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "photo.badge.plus")
                Text("Add photo")
            }
            .font(JourneyFont.meta)
            .foregroundStyle(Brand.accentStart)
            .padding(.vertical, 6)
            .padding(.trailing, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add a photo to \(spokenTitle)")
    }

    // MARK: - Copy

    private var displayTitle: String {
        memory.title.isEmpty ? memory.kind.displayName : memory.title
    }

    private var spokenTitle: String {
        let trimmed = memory.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? memory.kind.displayName : trimmed
    }

    /// "May 1, 2026", in the viewer's locale.
    private var longDate: String {
        memory.date.formatted(date: .long, time: .omitted)
    }

    private var spokenLabel: String {
        var sentences = [String(localized: "\(spokenTitle), \(longDate).",
                                comment: "VoiceOver: a memory card. First %@ is the memory's title, second its date such as 'May 1, 2026'.")]
        if !memory.emotions.isEmpty {
            // "Nervous, Joyful, Tender" in English; the locale's own list
            // separators elsewhere.
            let feelings = memory.emotions.map { $0.displayName }
                .formatted(.list(type: .and, width: .narrow))
            sentences.append(JourneyTimelineSpeech.sentence(feelings))
        }
        if photoURL != nil {
            sentences.append(String(localized: "Has a photo.", comment: "VoiceOver: the memory has a photo"))
        }
        if memory.isUnlockedCapsule(at: now) {
            sentences.append(String(localized: "Capsule opened.", comment: "VoiceOver: this memory was a capsule that has now opened"))
        }
        return sentences.joined(separator: " ")
    }
}

// MARK: - Press

/// Draws nothing itself: it hands the press to the card, which scales as a
/// whole, "Add photo" included, while the two stay separate buttons.
private struct MemoryCardPressStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, pressed in
                isPressed = pressed
            }
    }
}
