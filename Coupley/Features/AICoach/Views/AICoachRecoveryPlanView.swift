//
//  AICoachRecoveryPlanView.swift
//  Coupley
//
//  Premium tool: 3-day or 7-day reconnect plan. Day-by-day actions, a
//  themed message the user can send, and a simple ritual to follow.
//

import SwiftUI

struct AICoachRecoveryPlanView: View {

    @ObservedObject var viewModel: AICoachViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var length: RecoveryPlan.Length = .threeDay
    @State private var issue: CoachIssueType? = nil
    @State private var plan: RecoveryPlan?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var expandedDay: Int? = 1
    @State private var copiedDay: Int?

    var body: some View {
        ZStack {
            Brand.bgGradient.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    header
                        .padding(.top, 6)
                        .padding(.horizontal, 20)

                    setupCard
                        .padding(.horizontal, 20)

                    if isLoading {
                        loadingCard.padding(.horizontal, 20)
                    } else if let plan {
                        planHeader(plan)
                            .padding(.horizontal, 20)

                        ForEach(plan.days) { day in
                            dayCard(day)
                                .padding(.horizontal, 20)
                        }
                    }

                    Color.clear.frame(height: 80)
                }
                .padding(.top, 10)
            }
        }
        .navigationTitle("Recovery Plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") { dismiss() }
                    .foregroundStyle(Brand.textSecondary)
            }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.48, green: 0.75, blue: 0.56),
                                Color(red: 0.72, green: 0.88, blue: 0.64)
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Reconnect, on purpose")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                Text("A day-by-day plan, no pressure.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
            }
            Spacer()
        }
    }

    private var setupCard: some View {
        CoachCard {
            VStack(alignment: .leading, spacing: 14) {
                CoachSectionTitle(text: "Build your plan")

                VStack(alignment: .leading, spacing: 8) {
                    Text("Plan length")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)
                    HStack(spacing: 8) {
                        ForEach(RecoveryPlan.Length.allCases) { l in
                            chip(title: l.label, isSelected: length == l) {
                                length = l
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Focus (optional)")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)

                    CoachFlowLayout(spacing: 8) {
                        chip(title: "General", isSelected: issue == nil) { issue = nil }
                        ForEach([CoachIssueType.fight, .distance, .trust, .reconnect, .communication], id: \.self) { i in
                            chip(title: i.title, isSelected: issue == i) { issue = i }
                        }
                    }
                }

                PrimaryButton(
                    title: plan == nil ? "Generate plan" : "Generate new plan",
                    isLoading: isLoading
                ) {
                    runPlan()
                }
            }
            .padding(18)
        }
    }

    private func chip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(isSelected ? .white : Brand.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    Capsule()
                        .fill(isSelected ? AnyShapeStyle(Brand.accentGradient) : AnyShapeStyle(Brand.surfaceLight))
                        .overlay(
                            Capsule().strokeBorder(isSelected ? .clear : Brand.divider, lineWidth: 1)
                        )
                )
        }
        .buttonStyle(BouncyButtonStyle(scale: 0.95))
    }

    private var loadingCard: some View {
        CoachCard {
            HStack(spacing: 12) {
                ProgressView().tint(Brand.accentStart)
                Text("Designing your reconnect plan…")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func planHeader(_ p: RecoveryPlan) -> some View {
        CoachCard(tint: Color(red: 0.48, green: 0.75, blue: 0.56)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(red: 0.48, green: 0.75, blue: 0.56))
                    Text(p.length.label.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.48, green: 0.75, blue: 0.56))
                        .tracking(0.6)
                }
                Text(p.title)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                Text(p.intro)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
        }
    }

    private func dayCard(_ day: RecoveryPlan.Day) -> some View {
        let isExpanded = expandedDay == day.dayNumber
        return CoachCard {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        expandedDay = isExpanded ? nil : day.dayNumber
                    }
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Brand.accentStart.opacity(0.14))
                                .frame(width: 40, height: 40)
                            Text("\(day.dayNumber)")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(Brand.accentStart)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Day \(day.dayNumber)")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(Brand.textSecondary)
                                .textCase(.uppercase)
                                .tracking(0.5)
                            Text(day.theme)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(Brand.textPrimary)
                        }
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Brand.textTertiary)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                    .padding(16)
                }
                .buttonStyle(.plain)

                if isExpanded {
                    VStack(alignment: .leading, spacing: 14) {
                        Divider().opacity(0.4).padding(.horizontal, 16)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Today's actions")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(Brand.textSecondary)
                                .textCase(.uppercase)
                                .tracking(0.5)
                            ForEach(day.actions, id: \.self) { action in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "circle")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Brand.textTertiary)
                                        .padding(.top, 2)
                                    Text(action)
                                        .font(.system(size: 14, design: .rounded))
                                        .foregroundStyle(Brand.textPrimary)
                                        .lineSpacing(3)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(.horizontal, 16)

                        suggestedMessageBlock(dayNumber: day.dayNumber, message: day.message)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private func suggestedMessageBlock(dayNumber: Int, message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Message to send")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer()
                Button {
                    UIPasteboard.general.string = message
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    copiedDay = dayNumber
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 1_400_000_000)
                        if copiedDay == dayNumber { copiedDay = nil }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copiedDay == dayNumber ? "checkmark" : "doc.on.doc")
                        Text(copiedDay == dayNumber ? "Copied" : "Copy")
                    }
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.accentStart)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Brand.accentStart.opacity(0.14)))
                }
            }
            Text(message)
                .font(.system(size: 13, design: .rounded))
                .italic()
                .foregroundStyle(Brand.textPrimary)
                .lineSpacing(3)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Brand.backgroundTop.opacity(0.6))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Brand.divider, lineWidth: 1))
                )
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func runPlan() {
        isLoading = true
        plan = nil
        Task {
            defer { isLoading = false }
            do {
                plan = try await viewModel.runRecoveryPlan(length: length, issue: issue)
                expandedDay = 1
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - CoachFlowLayout (simple wrapping HStack for chips)

private struct CoachFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var maxRowWidth: CGFloat = 0

        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            if rowWidth + s.width > maxWidth {
                totalHeight += rowHeight + spacing
                maxRowWidth = max(maxRowWidth, rowWidth - spacing)
                rowWidth = s.width + spacing
                rowHeight = s.height
            } else {
                rowWidth += s.width + spacing
                rowHeight = max(rowHeight, s.height)
            }
        }
        totalHeight += rowHeight
        maxRowWidth = max(maxRowWidth, rowWidth - spacing)
        return CGSize(width: maxRowWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}
