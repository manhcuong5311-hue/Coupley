//
//  DreamDetailSheet.swift
//  Coupley
//
//  Detail view for a single dream. Hero photo/gradient at the top, then the
//  inspiration quote, the description, the optional first step, and a
//  "turn this into a goal" CTA — the most important conversion path on the
//  Dream Board, since it bridges from emotional dream to active goal.
//

import SwiftUI

struct DreamDetailSheet: View {

    let dream: Dream
    @ObservedObject var viewModel: TogetherViewModel
    let onTurnIntoGoal: (Dream) -> Void

    @EnvironmentObject private var premiumStore: PremiumStore
    @Environment(\.dismiss) private var dismiss

    @State private var showEditor: Bool = false

    var body: some View {
        let live = viewModel.dreams.first { $0.id == dream.id } ?? dream

        return NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    heroBlock(live)

                    if let inspiration = live.inspiration, !inspiration.isEmpty {
                        inspirationBlock(text: inspiration, colorway: live.colorway)
                    }

                    if let note = live.note, !note.isEmpty {
                        noteBlock(text: note)
                    }

                    if let firstStep = live.firstStep, !firstStep.isEmpty {
                        firstStepBlock(text: firstStep, colorway: live.colorway)
                    }

                    turnIntoGoalButton(live)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
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
                                await viewModel.deleteDream(live)
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
                DreamEditorSheet(viewModel: viewModel, mode: .edit(live))
                    .environmentObject(premiumStore)
                    .presentationDetents([.large])
            }
        }
    }

    // MARK: - Hero

    private func heroBlock(_ live: Dream) -> some View {
        ZStack {
            live.colorway.gradient

            // Photo (when premium + present)
            if let url = live.photoURL, let parsed = URL(string: url) {
                CachedAsyncImage(url: parsed) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                    }
                }
            }

            LinearGradient(
                colors: [.clear, .black.opacity(0.45)],
                startPoint: .top, endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(live.horizon.label)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .kerning(0.4)
                        .textCase(.uppercase)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(.white.opacity(0.20)))
                    Spacer()
                }

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: live.category.icon)
                        .font(.system(size: 12, weight: .semibold))
                    Text(live.category.label)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .kerning(0.4)
                        .textCase(.uppercase)
                }
                .foregroundStyle(.white.opacity(0.85))

                Text(live.title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineSpacing(1)
            }
            .padding(22)
        }
        .frame(height: 240)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: live.colorway.deep.opacity(0.30), radius: 16, y: 8)
    }

    // MARK: - Sub Blocks

    private func inspirationBlock(text: String, colorway: TogetherColorway) -> some View {
        TogetherCard(tint: colorway) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "quote.opening")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(colorway.deep)
                Text(text)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func noteBlock(text: String) -> some View {
        TogetherCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Description")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .kerning(0.4)
                    .textCase(.uppercase)
                    .foregroundStyle(Brand.textSecondary)
                Text(text)
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func firstStepBlock(text: String, colorway: TogetherColorway) -> some View {
        TogetherCard(tint: colorway) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                    Text("First step")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .kerning(0.4)
                        .textCase(.uppercase)
                }
                .foregroundStyle(colorway.deep)

                Text(text)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Turn Into Goal CTA

    private func turnIntoGoalButton(_ live: Dream) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            dismiss()
            onTurnIntoGoal(live)
        }) {
            HStack(spacing: 12) {
                Image(systemName: "target")
                    .font(.system(size: 16, weight: .bold))
                Text("Turn this into a goal")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(live.colorway.gradient)
                    .shadow(color: live.colorway.primary.opacity(0.4), radius: 14, y: 5)
            )
        }
        .buttonStyle(BouncyButtonStyle())
    }
}
