//
//  CoupleProfileView.swift
//  Coupley
//
//  The aggregated "what we've learned about you two" screen. Reads
//  couples/{coupleId}/coupleProfile/current in realtime.
//

import SwiftUI

struct CoupleProfileView: View {

    let coupleId: String
    let userAId: String      // viewer
    let userBId: String      // partner

    @StateObject private var viewModel: CoupleProfileViewModel
    @Environment(\.dismiss) private var dismiss

    init(coupleId: String, userAId: String, userBId: String) {
        self.coupleId = coupleId
        self.userAId = userAId
        self.userBId = userBId
        _viewModel = StateObject(wrappedValue: CoupleProfileViewModel(coupleId: coupleId))
    }

    var body: some View {
        ZStack {
            Brand.bgGradient.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    headerCard
                    topicsSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Couple Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") { dismiss() }
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
            }
        }
        .onAppear  { viewModel.start() }
        .onDisappear { viewModel.stop() }
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Brand.accentStart.opacity(0.14))
                        .frame(width: 54, height: 54)
                    Image(systemName: "sparkles")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Brand.accentStart)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("What we've learned")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                    Text(confidenceCaption)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)
                }
                Spacer(minLength: 0)
            }

            confidenceBar
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: Brand.cardCornerRadius)
                .fill(Brand.surfaceLight)
                .overlay(
                    RoundedRectangle(cornerRadius: Brand.cardCornerRadius)
                        .strokeBorder(Brand.divider, lineWidth: 1)
                )
        )
    }

    private var confidenceCaption: String {
        let score = viewModel.profile.confidenceScore
        switch score {
        case 0:        return "Answer a few quizzes together to start building your profile."
        case 1..<30:   return "Just getting to know you two — keep answering."
        case 30..<60:  return "A picture is forming."
        case 60..<85:  return "We've got a solid read on you."
        default:       return "We know you two pretty well now."
        }
    }

    private var confidenceBar: some View {
        let score = max(0, min(100, viewModel.profile.confidenceScore))
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Confidence")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
                    .textCase(.uppercase)
                    .kerning(0.5)
                Spacer()
                Text("\(score)%")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Brand.accentStart)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Brand.surfaceMid)
                    Capsule()
                        .fill(Brand.accentGradient)
                        .frame(width: geo.size.width * CGFloat(score) / 100.0)
                }
            }
            .frame(height: 8)
        }
    }

    // MARK: - Topics

    private var topicsSection: some View {
        VStack(spacing: 14) {
            ForEach(viewModel.sortedTopics, id: \.topic.id) { pair in
                TopicCard(topic: pair.topic,
                          insight: pair.insight,
                          viewerId: userAId,
                          partnerId: userBId)
            }
        }
    }
}

// MARK: - Topic Card

private struct TopicCard: View {
    let topic: QuizTopic
    let insight: CoupleInsightProfile.TopicInsight?
    let viewerId: String
    let partnerId: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let insight, insight.answeredCount > 0 {
                filled(insight)
            } else {
                emptyState
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Brand.cardCornerRadius)
                .fill(Brand.surfaceLight)
                .overlay(
                    RoundedRectangle(cornerRadius: Brand.cardCornerRadius)
                        .strokeBorder(Brand.divider, lineWidth: 1)
                )
        )
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(topic.emoji).font(.system(size: 22))
            VStack(alignment: .leading, spacing: 2) {
                Text(topic.label)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                if let c = insight?.answeredCount, c > 0 {
                    Text("\(c) \(c == 1 ? "quiz" : "quizzes") answered")
                        .font(.caption)
                        .foregroundStyle(Brand.textSecondary)
                }
            }
            Spacer()
        }
    }

    private var emptyState: some View {
        Text("No quizzes answered in this topic yet.")
            .font(.system(size: 14, design: .rounded))
            .foregroundStyle(Brand.textTertiary)
    }

    @ViewBuilder
    private func filled(_ insight: CoupleInsightProfile.TopicInsight) -> some View {
        // Partners
        HStack(alignment: .top, spacing: 12) {
            partnerColumn(title: "You",
                          trait: traitFor(viewerId, in: insight))
            Divider().overlay(Brand.divider)
            partnerColumn(title: "Partner",
                          trait: traitFor(partnerId, in: insight))
        }

        if !insight.sharedTraits.isEmpty {
            chipsBlock(title: "In sync",
                       items: insight.sharedTraits,
                       tint: Brand.accentStart)
        }

        if !insight.differences.isEmpty {
            chipsBlock(title: "Different takes",
                       items: insight.differences,
                       tint: Brand.textSecondary)
        }
    }

    private func traitFor(_ userId: String,
                          in insight: CoupleInsightProfile.TopicInsight)
    -> CoupleInsightProfile.PartnerTrait? {
        if insight.userA?.userId == userId { return insight.userA }
        if insight.userB?.userId == userId { return insight.userB }
        return nil
    }

    private func partnerColumn(title: String,
                               trait: CoupleInsightProfile.PartnerTrait?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Brand.textTertiary)
                .textCase(.uppercase)
                .kerning(0.5)
            Text(trait?.summary ?? "—")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Brand.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let c = trait?.confidence, c > 0 {
                Text("\(c)% confidence")
                    .font(.caption2)
                    .foregroundStyle(Brand.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chipsBlock(title: String, items: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Brand.textTertiary)
                .textCase(.uppercase)
                .kerning(0.5)
            TraitFlowLayout(spacing: 6) {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(tint.opacity(0.12))
                        )
                }
            }
        }
    }
}

// MARK: - Simple flow layout

/// Minimal wrap/flow layout — used for trait chip lists.
private struct TraitFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize,
                      subviews: Subviews,
                      cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[CGSize]] = [[]]
        var rowWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var currentRowHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth && !rows[rows.count - 1].isEmpty {
                totalHeight += currentRowHeight + spacing
                rows.append([])
                rowWidth = 0
                currentRowHeight = 0
            }
            rows[rows.count - 1].append(size)
            rowWidth += size.width + spacing
            currentRowHeight = max(currentRowHeight, size.height)
        }
        totalHeight += currentRowHeight
        return CGSize(width: maxWidth.isFinite ? maxWidth : rowWidth,
                      height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect,
                       proposal: ProposedViewSize,
                       subviews: Subviews,
                       cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y),
                      proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
