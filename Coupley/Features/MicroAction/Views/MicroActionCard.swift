//
//  MicroActionCard.swift
//  Coupley
//

import SwiftUI

// MARK: - Home Card

struct MicroActionCard: View {

    @ObservedObject var viewModel: MicroActionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let focus = focusAction {
                focusView(focus)
            } else if viewModel.isGenerating {
                loadingView
            } else {
                emptyView
            }

            if !secondaryActions.isEmpty {
                Divider().opacity(0.6)
                VStack(spacing: 10) {
                    ForEach(secondaryActions) { action in
                        secondaryRow(action)
                    }
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Brand.surfaceLight)
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .strokeBorder(toneAccent.opacity(0.20), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.08), radius: 12, y: 3)
        )
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.todaysActions)
    }

    // MARK: - Derived

    private var focusAction: MicroAction? {
        viewModel.todaysActions.first { $0.isActionable }
            ?? viewModel.todaysActions.first
    }

    private var secondaryActions: [MicroAction] {
        guard let focus = focusAction else { return [] }
        return viewModel.todaysActions.filter { $0.id != focus.id }
    }

    private var toneAccent: Color {
        switch focusAction?.tone {
        case .support: return Color(red: 0.50, green: 0.40, blue: 1.0)
        case .bonding: return Color(red: 1.0, green: 0.55, blue: 0.25)
        case .light, .none: return Brand.accentStart
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("For you today")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Text(headerSubtitle)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(Brand.textTertiary)
            }

            Spacer()

            if let focusAction, focusAction.status == .done {
                doneBadge
            } else {
                toneBadge
            }
        }
    }

    private var headerSubtitle: String {
        switch focusAction?.tone {
        case .support: return "Soft and steady"
        case .bonding: return "Ride the moment"
        case .light:   return "Low-key care"
        case .none:    return "A gentle idea"
        }
    }

    private var toneBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(toneAccent)
                .frame(width: 6, height: 6)
            Text("Private")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Brand.textTertiary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Brand.backgroundTop)
                .overlay(Capsule().strokeBorder(Brand.divider, lineWidth: 1))
        )
    }

    private var doneBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
            Text("Done")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(Color(red: 0.25, green: 0.75, blue: 0.50))
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color(red: 0.25, green: 0.75, blue: 0.50).opacity(0.12))
        )
    }

    // MARK: - Focus

    private func focusView(_ action: MicroAction) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(action.text)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Brand.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
                .strikethrough(action.status == .done, color: Brand.textTertiary)

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "sparkle")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(toneAccent.opacity(0.8))
                    .padding(.top, 2)
                Text(action.rationale)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }

            if action.status == .pending || action.status == .snoozed {
                actionButtons(for: action)
                    .padding(.top, 2)
            } else if action.status == .snoozed, let until = action.snoozedUntil {
                snoozedNotice(until: until)
            }
        }
    }

    // MARK: - Secondary

    private func secondaryRow(_ action: MicroAction) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: action.status == .done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(action.status == .done ? Color(red: 0.25, green: 0.75, blue: 0.50) : Brand.textTertiary)
                .padding(.top, 2)
                .onTapGesture {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    if action.status == .done {
                        viewModel.skip(action)
                    } else {
                        viewModel.markDone(action)
                    }
                }

            Text(action.text)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(action.status == .done ? Brand.textTertiary : Brand.textSecondary)
                .strikethrough(action.status == .done, color: Brand.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Action buttons

    private func actionButtons(for action: MicroAction) -> some View {
        HStack(spacing: 10) {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                viewModel.markDone(action)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                    Text("Done")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(
                    Capsule().fill(toneAccent.opacity(0.92))
                )
            }
            .buttonStyle(BouncyButtonStyle())

            Menu {
                Button("In 30 minutes")  { viewModel.snooze(action, minutes: 30) }
                Button("In 2 hours")     { viewModel.snooze(action, minutes: 120) }
                Button("Tonight")        { viewModel.snooze(action, minutes: minutesUntilTonight()) }
                Divider()
                Button("Skip", role: .destructive) { viewModel.skip(action) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "bell.badge")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Remind me")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(Brand.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(
                    Capsule()
                        .fill(Brand.backgroundTop)
                        .overlay(Capsule().strokeBorder(Brand.divider, lineWidth: 1))
                )
            }
        }
    }

    private func snoozedNotice(until: Date) -> some View {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return Text("Reminder set for \(formatter.string(from: until))")
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(Brand.textTertiary)
    }

    // MARK: - States

    private var loadingView: some View {
        HStack(spacing: 10) {
            ProgressView().tint(Brand.accentStart).controlSize(.small)
            Text("Thinking of something small…")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(Brand.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private var emptyView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nothing to suggest right now.")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Brand.textPrimary)
            Text("Ideas appear here based on your partner's mood.")
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(Brand.textSecondary)
        }
    }

    // MARK: - Helpers

    private func minutesUntilTonight() -> Int {
        let cal = Calendar.current
        var components = cal.dateComponents([.year, .month, .day], from: Date())
        components.hour = 20
        components.minute = 0
        let tonight = cal.date(from: components) ?? Date().addingTimeInterval(3600)
        let delta = Int(tonight.timeIntervalSinceNow / 60)
        return max(60, delta)
    }
}
