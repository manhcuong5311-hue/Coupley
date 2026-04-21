//
//  StatsPreviewCard.swift
//  Coupley
//
//  Created by Sam Manh Cuong on 1/4/26.
//

import SwiftUI

// MARK: - Stats Preview Card (For Dashboard)

struct StatsPreviewCard: View {

    @ObservedObject var viewModel: CoupleStatsViewModel

    var body: some View {
        HStack(spacing: 0) {
            // Streak
            streakMini
                .frame(maxWidth: .infinity)

            Divider()
                .frame(height: 50)

            // Sync Score
            syncMini
                .frame(maxWidth: .infinity)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: Brand.cardCornerRadius)
                .fill(Brand.surfaceLight)
                .overlay(
                    RoundedRectangle(cornerRadius: Brand.cardCornerRadius)
                        .strokeBorder(Brand.divider, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        )
        .onAppear {
            viewModel.loadStats()
        }
    }

    // MARK: - Streak Mini

    private var streakMini: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.caption)
                    .foregroundStyle(Brand.accentStart)

                Text("\(viewModel.streak.currentStreak)")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
            }

            Text(viewModel.streak.currentStreak == 1 ? "day streak" : "day streak")
                .font(.caption2)
                .foregroundStyle(Brand.textSecondary)
        }
    }

    // MARK: - Sync Mini

    private var syncMini: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                if let score = viewModel.todaySyncScore {
                    Text(score.syncLevel.emoji)
                        .font(.caption)

                    Text("\(score.score)%")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                } else {
                    Text("--")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)
                }
            }

            Text(viewModel.todaySyncScore != nil ? "sync score" : "check in first")
                .font(.caption2)
                .foregroundStyle(Brand.textSecondary)
        }
    }
}

#Preview {
    StatsPreviewCard(viewModel: CoupleStatsViewModel())
        .padding()
}
