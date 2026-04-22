//
//  AnniversaryCard.swift
//  Coupley
//

import SwiftUI

// MARK: - Card

struct AnniversaryCard: View {

    let anniversary: Anniversary
    let now: Date
    var onTap: () -> Void = {}

    private var state: CountdownState {
        CountdownEngine.state(for: anniversary.date, now: now)
    }

    private var progress: Double? {
        CountdownEngine.progress(anniversary: anniversary, now: now)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {

                // MARK: Hero image
                if let urlString = anniversary.imageURL, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity)
                                .frame(height: 160)
                                .clipped()
                        }
                    }
                    .clipShape(UnevenRoundedRectangle(
                        topLeadingRadius: 22, bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0, topTrailingRadius: 22
                    ))
                }

                // MARK: Content
                VStack(alignment: .leading, spacing: 18) {
                    header

                    VStack(alignment: .leading, spacing: 6) {
                        Text(state.marker)
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundStyle(accent)
                            .contentTransition(.numericText())

                        Text(state.caption)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(Brand.textSecondary)
                    }

                    if let note = anniversary.note, !note.isEmpty {
                        Text(note)
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .foregroundStyle(Brand.textSecondary)
                            .italic()
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }

                    if let progress, state.isFuture {
                        progressBar(progress)
                    }
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(Brand.surfaceLight)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22)
                            .strokeBorder(accent.opacity(0.18), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.08), radius: 14, y: 4)
            )
            .clipShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(BouncyButtonStyle(scale: 0.98))
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(anniversary.title)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                    .lineLimit(2)

                Text(anniversary.formattedDate())
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Brand.textTertiary)
            }

            Spacer()

            Image(systemName: "heart.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(accent.opacity(0.55))
        }
    }

    // MARK: - Progress

    private func progressBar(_ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Brand.divider.opacity(0.6))
                    Capsule()
                        .fill(accent.opacity(0.85))
                        .frame(width: max(4, geo.size.width * value))
                }
            }
            .frame(height: 6)

            Text("\(Int(value * 100))% of the way there")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Brand.textTertiary)
        }
    }

    // MARK: - Accent

    private var accent: Color {
        switch state {
        case .future: return Brand.accentStart
        case .today:  return Color(red: 1.0, green: 0.55, blue: 0.25)
        case .past:   return Color(red: 0.55, green: 0.55, blue: 0.70)
        }
    }
}
