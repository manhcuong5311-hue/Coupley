//
//  MemoryDetailSheet.swift
//  Coupley
//
//  Read-only / detail view of a single memory. Tapping a memory card in
//  the timeline opens this. Provides a clean reading experience for the
//  story, the photo, and the emotion tags, with an "Edit" affordance
//  in the toolbar.
//
//  For locked capsules, the detail sheet shows the elegant "sealed"
//  treatment with a large countdown — body and photo stay redacted.
//

import SwiftUI

// MARK: - Detail Sheet

struct MemoryDetailSheet: View {

    @ObservedObject var viewModel: TimeTreeViewModel
    let memory: TimeMemory

    @Environment(\.dismiss) private var dismiss
    @State private var showEditor = false

    private var current: TimeMemory {
        viewModel.memories.first(where: { $0.id == memory.id }) ?? memory
    }

    private var isLocked: Bool { current.isLocked(at: viewModel.now) }

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.bgGradient.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        if isLocked {
                            lockedHero
                        } else {
                            openHero
                        }

                        if !isLocked, let note = current.note, !note.isEmpty {
                            noteBlock(note)
                        }

                        if !isLocked, !current.emotions.isEmpty {
                            emotionsBlock
                        }

                        if let attribution = current.attribution, !attribution.isEmpty {
                            attributionBlock(attribution)
                        }

                        Color.clear.frame(height: 60)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            }
            .navigationTitle(isLocked ? "Capsule" : "Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Brand.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") {
                        showEditor = true
                    }
                    .foregroundStyle(Brand.accentStart)
                }
            }
            .sheet(isPresented: $showEditor) {
                MemoryEditorSheet(viewModel: viewModel, mode: .edit(current))
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Open hero

    private var openHero: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let urlString = current.photoURL, let url = URL(string: urlString) {
                CachedAsyncImage(url: url) { phase in
                    ZStack {
                        Brand.accentStart.opacity(0.06)
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)
                    .clipped()
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Brand.divider, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
            }

            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Brand.accentStart.opacity(0.14))
                        .frame(width: 46, height: 46)
                    Text(current.kind.emoji).font(.system(size: 22))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(current.title)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                    Text(current.formattedDate())
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)

                    if current.isUnlockedCapsule(at: viewModel.now) {
                        HStack(spacing: 4) {
                            Image(systemName: "envelope.open.fill")
                                .font(.system(size: 10, weight: .semibold))
                            Text("Capsule opened")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.30))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(Color(red: 1.0, green: 0.78, blue: 0.30).opacity(0.14))
                        )
                        .padding(.top, 4)
                    }
                }
            }
        }
    }

    // MARK: - Locked hero

    private var lockedHero: some View {
        let daysLeft = current.daysUntilUnlock(now: viewModel.now) ?? 0
        return VStack(alignment: .leading, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 1.0, green: 0.85, blue: 0.45).opacity(0.30),
                                Color(red: 0.95, green: 0.55, blue: 0.30).opacity(0.18)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                    )

                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.18))
                            .frame(width: 76, height: 76)
                        Image(systemName: "lock.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.30))
                    }

                    VStack(spacing: 6) {
                        Text("Sealed Capsule")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Brand.textSecondary)
                            .textCase(.uppercase)
                            .tracking(1.0)

                        Text(current.title.isEmpty ? "A future moment for you both" : current.title)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(Brand.textPrimary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }

                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text("\(max(0, daysLeft))")
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .foregroundStyle(Brand.textPrimary)
                            .contentTransition(.numericText())
                            .monospacedDigit()
                        Text(daysLeft == 1 ? "day" : "days")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(Brand.textSecondary)
                            .padding(.bottom, 8)
                    }

                    if let unlockDate = current.unlockDate {
                        Text("Opens \(formatDate(unlockDate))")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(Brand.textSecondary)
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)

            Text("Your partner can't read this yet either. The note, photo, and emotion tags are kept hidden until the unlock day arrives.")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(Brand.textSecondary)
                .multilineTextAlignment(.leading)
                .lineSpacing(2)
                .padding(.horizontal, 4)
        }
    }

    // MARK: - Note block

    private func noteBlock(_ note: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("The Story")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Brand.textSecondary)
                .textCase(.uppercase)
                .tracking(0.8)

            Text(note)
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(Brand.textPrimary.opacity(0.95))
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Brand.surfaceLight)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Brand.divider, lineWidth: 1)
                )
        )
    }

    // MARK: - Emotions block

    private var emotionsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Felt Like")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Brand.textSecondary)
                .textCase(.uppercase)
                .tracking(0.8)

            FlowLayout(spacing: 8) {
                ForEach(current.emotions, id: \.self) { emotion in
                    HStack(spacing: 5) {
                        Text(emotion.emoji).font(.system(size: 12))
                        Text(emotion.displayName)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(Brand.textPrimary)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(
                        Capsule().fill(Brand.accentStart.opacity(0.14))
                            .overlay(
                                Capsule().strokeBorder(Brand.accentStart.opacity(0.30), lineWidth: 1)
                            )
                    )
                }
            }
        }
    }

    // MARK: - Attribution

    private func attributionBlock(_ attribution: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Brand.textTertiary)
            Text(attribution)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Brand.textTertiary)
        }
        .padding(.horizontal, 4)
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .none
        return f.string(from: date)
    }
}
