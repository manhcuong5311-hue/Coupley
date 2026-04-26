//
//  MemoryCard.swift
//  Coupley
//
//  A single luxury memory card. Two visual modes:
//   - Standard: hero photo, title, date, note, emotion chips, attribution.
//   - Capsule (locked): photo placeholder is fully obscured, body and
//     emotions are redacted, but a beautiful "X days until unlock"
//     countdown is rendered with a sealed-envelope motif.
//

import SwiftUI

// MARK: - Memory Card

struct MemoryCard: View {

    let memory: TimeMemory
    let now: Date
    /// Position in the timeline (used for the small node + connecting
    /// line on the leading edge — drawn outside the card by the parent).
    var indexInTimeline: Int = 0
    var onTap: () -> Void = {}

    private var isLocked: Bool { memory.isLocked(at: now) }

    var body: some View {
        Button(action: onTap) {
            if isLocked {
                lockedBody
            } else {
                openBody
            }
        }
        .buttonStyle(BouncyButtonStyle(scale: 0.98))
    }

    // MARK: - Open (standard) body

    private var openBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let urlString = memory.photoURL, let url = URL(string: urlString) {
                heroPhoto(url: url)
            }

            VStack(alignment: .leading, spacing: 14) {
                header

                if let note = memory.note, !note.isEmpty {
                    Text(note)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
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
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Brand.textTertiary)
                        Text(attribution)
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(Brand.textTertiary)
                    }
                }
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 14, y: 4)
    }

    // MARK: - Hero photo

    private func heroPhoto(url: URL) -> some View {
        CachedAsyncImage(url: url) { phase in
            ZStack {
                Brand.accentStart.opacity(0.06)
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                }
                LinearGradient(
                    colors: [.clear, .black.opacity(0.32)],
                    startPoint: .center,
                    endPoint: .bottom
                )
            }
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .clipped()
        }
        .clipShape(UnevenRoundedRectangle(
            topLeadingRadius: 22,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: 22
        ))
    }

    // MARK: - Header (title + kind badge + date)

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(Brand.accentStart.opacity(0.12))
                    .frame(width: 38, height: 38)
                Text(memory.kind.emoji)
                    .font(.system(size: 18))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(memory.title)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(memory.formattedDate())
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Brand.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if memory.isUnlockedCapsule(at: now) {
                Image(systemName: "envelope.open.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.30))
            }
        }
    }

    // MARK: - Emotion chips

    private var emotionChips: some View {
        FlowLayout(spacing: 6) {
            ForEach(memory.emotions, id: \.self) { emotion in
                HStack(spacing: 4) {
                    Text(emotion.emoji).font(.system(size: 10))
                    Text(emotion.displayName)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                }
                .foregroundStyle(Brand.textSecondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Capsule().fill(Brand.surfaceMid))
            }
        }
    }

    // MARK: - Locked (capsule) body

    private var lockedBody: some View {
        let daysLeft = memory.daysUntilUnlock(now: now) ?? 0

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.85, blue: 0.45).opacity(0.30),
                                    Color(red: 0.95, green: 0.55, blue: 0.30).opacity(0.18)
                                ],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .frame(width: 44, height: 44)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.30))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Memory Capsule")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)
                        .textCase(.uppercase)
                        .tracking(0.6)

                    Text(memory.title.isEmpty ? "A future moment for you both" : memory.title)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                        .lineLimit(2)
                }

                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text("\(max(0, daysLeft))")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                        .contentTransition(.numericText())
                        .monospacedDigit()
                    Text(daysLeft == 1 ? "day until it opens" : "days until it opens")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)
                        .padding(.bottom, 6)
                }

                if let unlockDate = memory.unlockDate {
                    Text("Sealed for \(formatDate(unlockDate))")
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(Brand.textTertiary)
                }
            }

            // Decorative wax-seal style strip
            HStack(spacing: 0) {
                ForEach(0..<14, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            (i % 2 == 0)
                            ? Color(red: 1.0, green: 0.78, blue: 0.30).opacity(0.65)
                            : Color(red: 0.95, green: 0.55, blue: 0.30).opacity(0.45)
                        )
                        .frame(height: 4)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Brand.surfaceLight)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.85, blue: 0.45).opacity(0.55),
                                    Color(red: 0.95, green: 0.55, blue: 0.30).opacity(0.30)
                                ],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color(red: 1.0, green: 0.65, blue: 0.30).opacity(0.18), radius: 14, y: 4)
        )
    }

    // MARK: - Card background

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Brand.surfaceLight)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Brand.divider, lineWidth: 1)
            )
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .none
        return f.string(from: date)
    }
}
