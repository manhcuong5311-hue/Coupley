//
//  GoalDetailSheet.swift
//  Coupley
//
//  Detail view for a single goal. Shows the hero progress, the contribution
//  split, the history, and an "add contribution" CTA. The CTA is the
//  feature's most important interaction — making it tactile is the point.
//

import SwiftUI

struct GoalDetailSheet: View {

    let goal: TogetherGoal
    @ObservedObject var viewModel: TogetherViewModel

    @EnvironmentObject private var premiumStore: PremiumStore
    @Environment(\.dismiss) private var dismiss

    @State private var contributionText: String = ""
    @State private var showEditor: Bool = false
    @State private var isContributing: Bool = false

    @FocusState private var contributionFocused: Bool

    var body: some View {
        // Read the live goal from the view model so progress updates as the
        // listener fires while the sheet is open.
        let live = viewModel.goals.first { $0.id == goal.id } ?? goal

        return NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    heroBlock(live)
                    contributionSplitCard(live)
                    contributionInput(live)
                    if let note = live.note, !note.isEmpty {
                        notePanel(note: note, colorway: live.colorway)
                    }
                    historyPanel(live)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Brand.bgGradient.ignoresSafeArea())
            .navigationTitle(live.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Brand.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showEditor = true } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            Task {
                                await viewModel.deleteGoal(live)
                                dismiss()
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(Brand.textSecondary)
                    }
                }
            }
            .sheet(isPresented: $showEditor) {
                GoalEditorSheet(viewModel: viewModel, mode: .edit(live))
                    .environmentObject(premiumStore)
                    .presentationDetents([.large])
            }
        }
    }

    // MARK: - Hero Block

    private func heroBlock(_ live: TogetherGoal) -> some View {
        ZStack {
            TogetherHeroBackground(colorway: live.colorway)

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: live.category.icon)
                        .font(.system(size: 12, weight: .semibold))
                    Text(live.category.label)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .kerning(0.4)
                        .textCase(.uppercase)
                }
                .foregroundStyle(.white.opacity(0.85))

                Text("\(Int(live.progress * 100))%")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()

                Text(live.progressLabel)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))

                TogetherProgressBar(progress: live.progress, colorway: live.colorway, height: 12, showsHighlight: false)
                    .padding(.top, 4)

                if let estimate = live.estimatedCompletion(), !live.isComplete {
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Est. complete \(estimate.formatted(.dateTime.month(.wide).year()))")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(.white.opacity(0.78))
                    .padding(.top, 2)
                }
            }
            .padding(22)
        }
    }

    // MARK: - Contribution Split

    private func contributionSplitCard(_ live: TogetherGoal) -> some View {
        let myShare = live.contribution.share(for: viewModel.sessionUserId)
        let myAmount = live.contribution.amount(for: viewModel.sessionUserId)
        let partnerAmount = live.contribution.total - myAmount

        return TogetherCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Contribution split")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                    Spacer()
                    CouplePairAvatar(size: 22,
                                     leading: live.colorway.primary,
                                     trailing: live.colorway.deep)
                }

                // Two-tone bar
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        Rectangle()
                            .fill(live.colorway.primary)
                            .frame(width: max(8, geo.size.width * myShare))
                        Rectangle()
                            .fill(live.colorway.deep)
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 12)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("You")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Brand.textSecondary)
                        Text(live.formatAmount(myAmount))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(Brand.textPrimary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Partner")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Brand.textSecondary)
                        Text(live.formatAmount(partnerAmount))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(Brand.textPrimary)
                    }
                }
            }
        }
    }

    // MARK: - Contribution Input

    private func contributionInput(_ live: TogetherGoal) -> some View {
        TogetherCard(tint: live.colorway) {
            VStack(alignment: .leading, spacing: 12) {
                Text(live.trackingMode == .currency ? "Add a contribution" : "Add a step")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)

                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Text(live.trackingMode == .currency
                             ? live.currencyInfo.symbol
                             : "+")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(Brand.textSecondary)
                        TextField(live.trackingMode == .currency
                                    ? String(Int(live.currencyInfo.quickBaseUnit))
                                    : "1",
                                  text: $contributionText)
                            .keyboardType(.numberPad)
                            .focused($contributionFocused)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Brand.surfaceMid.opacity(0.5))
                    )

                    Button(action: { handleContribute(live) }) {
                        Group {
                            if isContributing {
                                ProgressView().tint(.white)
                            } else {
                                Text("Add")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                            }
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .frame(minWidth: 80)
                        .background(
                            Capsule()
                                .fill(live.colorway.gradient)
                                .shadow(color: live.colorway.primary.opacity(0.4), radius: 8, y: 2)
                        )
                    }
                    .buttonStyle(BouncyButtonStyle())
                    .disabled(isContributing || (Double(contributionText) ?? 0) <= 0)
                }

                // Quick contribute chips for fast taps. Amounts scale with the
                // goal's currency — USD shows $25/$50/$100/$250/$500 while VND
                // shows ₫50K/₫100K/₫250K/₫500K/₫1M for the same UX feel.
                if live.trackingMode == .currency {
                    let base = live.currencyInfo.quickBaseUnit
                    let ladder: [Double] = [base, 2 * base, 5 * base, 10 * base, 20 * base]
                    HStack(spacing: 8) {
                        ForEach(ladder, id: \.self) { amount in
                            quickChip(label: live.formatAmount(amount)) {
                                contributionText = "\(Int(amount))"
                                handleContribute(live)
                            }
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        quickChip(label: "+1 step") {
                            contributionText = "1"
                            handleContribute(live)
                        }
                    }
                }
            }
        }
    }

    private func quickChip(label: String, onTap: @escaping () -> Void) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTap()
        }) {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Brand.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(Brand.surfaceMid.opacity(0.6))
                        .overlay(Capsule().strokeBorder(Brand.divider, lineWidth: 1))
                )
        }
        .buttonStyle(BouncyButtonStyle(scale: 0.95))
    }

    // MARK: - Note Panel

    private func notePanel(note: String, colorway: TogetherColorway) -> some View {
        TogetherCard(tint: colorway) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "quote.opening")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(colorway.deep)
                    Text("Why this matters")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .kerning(0.4)
                        .textCase(.uppercase)
                        .foregroundStyle(colorway.deep)
                }
                Text(note)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - History Panel

    private func historyPanel(_ live: TogetherGoal) -> some View {
        TogetherCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Story so far")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)

                historyRow(
                    icon: "leaf.fill",
                    title: "Goal started",
                    detail: live.createdAt.formatted(date: .abbreviated, time: .omitted),
                    accent: live.colorway.primary
                )

                Divider().opacity(0.4)

                historyRow(
                    icon: "arrow.up.right",
                    title: "Progress so far",
                    detail: "\(live.formatAmount(live.contribution.total)) of \(live.formatAmount(live.target))",
                    accent: Brand.accentStart
                )

                if let due = live.dueDate {
                    Divider().opacity(0.4)
                    historyRow(
                        icon: "calendar",
                        title: "Target date",
                        detail: due.formatted(date: .long, time: .omitted),
                        accent: Brand.accentStart
                    )
                }

                if let completed = live.completedAt {
                    Divider().opacity(0.4)
                    historyRow(
                        icon: "checkmark.seal.fill",
                        title: "Completed",
                        detail: completed.formatted(date: .long, time: .omitted),
                        accent: Color(red: 0.30, green: 0.78, blue: 0.50)
                    )
                }
            }
        }
    }

    private func historyRow(icon: String, title: String, detail: String, accent: Color) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.18))
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                Text(detail)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
            }
            Spacer()
        }
    }

    // MARK: - Actions

    private func handleContribute(_ live: TogetherGoal) {
        let amount = Double(contributionText) ?? 0
        guard amount > 0 else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        contributionFocused = false

        Task {
            isContributing = true
            await viewModel.contributeToGoal(live, delta: amount)
            isContributing = false
            contributionText = ""
        }
    }
}
