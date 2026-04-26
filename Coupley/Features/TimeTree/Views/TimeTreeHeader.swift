//
//  TimeTreeHeader.swift
//  Coupley
//
//  Section 1 of the Time Tree screen: the live countdown header.
//  Three premium-feeling cards stacked vertically:
//
//   1. Days Together hero card — large numeric value, soft gradient,
//      computed from the relationship anchor.
//   2. Next Anniversary card — days until the upcoming yearly
//      anniversary, the date, and the year number that will be reached.
//   3. Next Milestone card — the next crown on the ladder (100 Days,
//      1 Year, 500 Days, etc.) with a thin progress capsule.
//
//  When no anchor is set, the header collapses into a single "Set the
//  beginning of your story" CTA card.
//

import SwiftUI

// MARK: - Header View

struct TimeTreeHeader: View {

    let anchor: RelationshipAnchor?
    let now: Date
    let onSetAnchorTapped: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            if let anchor {
                daysTogetherCard(anchor: anchor)
                HStack(spacing: 12) {
                    nextAnniversaryCard(anchor: anchor)
                    nextMilestoneCard(anchor: anchor)
                }
            } else {
                setAnchorCard
            }
        }
    }

    // MARK: - Days Together (hero)

    private func daysTogetherCard(anchor: RelationshipAnchor) -> some View {
        let days = anchor.daysTogether(now: now)
        let stage = TreeGrowthStage.from(daysTogether: days)
        let season = TreeSeason.current(now: now)

        return ZStack {
            // Soft gradient base
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Brand.accentStart.opacity(0.30),
                            Brand.accentEnd.opacity(0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(.white.opacity(0.10), lineWidth: 0.8)
                )

            // Glassy highlight
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.10), .clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                )

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label {
                        Text("Together")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    } icon: {
                        Image(systemName: "infinity")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(Brand.textPrimary.opacity(0.78))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(.white.opacity(0.12))
                    )

                    Spacer()

                    HStack(spacing: 4) {
                        Text(season.emoji)
                        Text(stage.displayName)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Brand.textSecondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(.white.opacity(0.08)))
                }

                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    Text("\(days)")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                        .contentTransition(.numericText())
                        .monospacedDigit()
                    Text(days == 1 ? "Day Together" : "Days Together")
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)
                        .padding(.bottom, 6)
                }

                Text(stage.poeticCaption)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
                    .lineLimit(2)
            }
            .padding(22)
        }
        .frame(maxWidth: .infinity)
        .shadow(color: Brand.accentStart.opacity(0.18), radius: 20, y: 8)
    }

    // MARK: - Next anniversary

    private func nextAnniversaryCard(anchor: RelationshipAnchor) -> some View {
        let daysLeft = anchor.daysUntilNextAnniversary(now: now)
        let nextDate = anchor.nextYearlyAnniversary(now: now)
        let yearNumber = anchor.yearsCompleted(now: now) + 1

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 11, weight: .semibold))
                Text("Next Anniversary")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(Brand.textSecondary)

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(daysLeft)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                    .contentTransition(.numericText())
                    .monospacedDigit()
                Text(daysLeft == 1 ? "day" : "days")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
                    .padding(.bottom, 4)
            }

            Text(yearLabel(year: yearNumber))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Brand.accentStart)

            Text(formatDate(nextDate))
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundStyle(Brand.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Brand.surfaceLight)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Brand.divider, lineWidth: 1)
                )
        )
    }

    // MARK: - Next Milestone

    @ViewBuilder
    private func nextMilestoneCard(anchor: RelationshipAnchor) -> some View {
        if let milestone = CrownMilestone.next(after: anchor.startDate, now: now) {
            let daysLeft = milestone.daysUntil(anchor: anchor.startDate, now: now)
            let progress = milestoneProgress(milestone: milestone, anchor: anchor)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Next Milestone")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(Brand.textSecondary)

                Text(milestone.displayTitle)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)

                Text("\(daysLeft) day\(daysLeft == 1 ? "" : "s") to go")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.30))

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Brand.divider.opacity(0.6))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 1.0, green: 0.85, blue: 0.45),
                                        Color(red: 0.95, green: 0.55, blue: 0.30)
                                    ],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                            .frame(width: max(4, geo.size.width * progress))
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Brand.surfaceLight)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color(red: 1.0, green: 0.85, blue: 0.45).opacity(0.50),
                                        Color(red: 0.95, green: 0.55, blue: 0.30).opacity(0.30)
                                    ],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
        } else {
            // The couple has cleared the entire ladder — celebrate that.
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("All Crowns Earned")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(Brand.textSecondary)

                Text("Legendary")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)

                Text("Every milestone — completed.")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(Brand.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Brand.surfaceLight)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Brand.divider, lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Set anchor card

    private var setAnchorCard: some View {
        Button(action: onSetAnchorTapped) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Brand.accentStart.opacity(0.18))
                        .frame(width: 52, height: 52)
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Brand.accentStart)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Plant your Time Tree")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                    Text("Set the day your story began to start growing.")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Brand.textTertiary)
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Brand.surfaceLight)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Brand.accentStart.opacity(0.55),
                                        Brand.accentEnd.opacity(0.30)
                                    ],
                                    startPoint: .leading, endPoint: .trailing
                                ),
                                lineWidth: 1.5
                            )
                    )
                    .shadow(color: Brand.accentStart.opacity(0.20), radius: 16, y: 6)
            )
        }
        .buttonStyle(BouncyButtonStyle())
    }

    // MARK: - Helpers

    private func yearLabel(year: Int) -> String {
        switch year {
        case 1:  return "1st year"
        case 2:  return "2nd year"
        case 3:  return "3rd year"
        default: return "\(year)th year"
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }

    /// Progress 0…1 from the *previous* milestone's reach date to this
    /// milestone. For the first milestone, progresses from the anchor.
    private func milestoneProgress(
        milestone: CrownMilestone,
        anchor: RelationshipAnchor
    ) -> Double {
        let calendar = Calendar.current
        let target = calendar.startOfDay(for: milestone.date(anchor: anchor.startDate, calendar: calendar))
        let today  = calendar.startOfDay(for: now)

        // Find previous milestone (or use anchor as the start)
        let previousStart: Date = {
            let reached = CrownMilestone.reached(after: anchor.startDate, now: now)
            if let last = reached.last {
                return calendar.startOfDay(for: last.date(anchor: anchor.startDate, calendar: calendar))
            }
            return calendar.startOfDay(for: anchor.startDate)
        }()

        let total = target.timeIntervalSince(previousStart)
        guard total > 0 else { return 1 }
        let elapsed = today.timeIntervalSince(previousStart)
        return max(0, min(1, elapsed / total))
    }
}
