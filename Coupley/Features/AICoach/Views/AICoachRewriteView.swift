//
//  AICoachRewriteView.swift
//  Coupley
//
//  Premium tool: user types a message they're about to send and the coach
//  returns three rewritten versions — softer, honest, and repair-focused.
//

import SwiftUI

struct AICoachRewriteView: View {

    @ObservedObject var viewModel: AICoachViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var draft: String = ""
    @State private var rewrites: [MessageRewrite] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var copiedRewriteId: UUID?
    @FocusState private var inputFocused: Bool

    var body: some View {
        ZStack {
            Brand.bgGradient.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    header
                        .padding(.top, 6)
                        .padding(.horizontal, 20)

                    inputCard
                        .padding(.horizontal, 20)

                    if isLoading {
                        loadingCard
                            .padding(.horizontal, 20)
                    } else if !rewrites.isEmpty {
                        ForEach(rewrites) { rewrite in
                            rewriteCard(rewrite)
                                .padding(.horizontal, 20)
                        }
                    }

                    Color.clear.frame(height: 80)
                }
                .padding(.top, 10)
            }
        }
        .navigationTitle("Rewrite Message")
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
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.52, green: 0.44, blue: 0.95),
                                    Color(red: 0.75, green: 0.55, blue: 0.98)
                                ],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Say it the way you meant it")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                    Text("Three versions, three tones.")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)
                }
                Spacer()
            }
        }
    }

    private var inputCard: some View {
        CoachCard {
            VStack(alignment: .leading, spacing: 12) {
                CoachSectionTitle(text: "What you want to send")

                ZStack(alignment: .topLeading) {
                    if draft.isEmpty {
                        Text("e.g. \"I'm sorry if you feel hurt\"")
                            .font(.system(size: 14, design: .rounded))
                            .foregroundStyle(Brand.textTertiary)
                            .padding(.horizontal, 4)
                            .padding(.top, 10)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $draft)
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 110)
                        .focused($inputFocused)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Brand.backgroundTop.opacity(0.6))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Brand.divider, lineWidth: 1))
                )

                PrimaryButton(
                    title: isLoading ? "Rewriting…" : "Rewrite for me",
                    isLoading: isLoading,
                    isEnabled: !draft.trimmingCharacters(in: .whitespaces).isEmpty
                ) {
                    runRewrite()
                }
            }
            .padding(18)
        }
    }

    private var loadingCard: some View {
        CoachCard {
            HStack(spacing: 12) {
                ProgressView().tint(Brand.accentStart)
                Text("Rephrasing with warmth and honesty…")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func rewriteCard(_ r: MessageRewrite) -> some View {
        CoachCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(toneTint(r.tone).opacity(0.16))
                            .frame(width: 34, height: 34)
                        Image(systemName: r.tone.icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(toneTint(r.tone))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.tone.label)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(Brand.textPrimary)
                        Text(r.tone.description)
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(Brand.textSecondary)
                    }
                    Spacer()
                    Button {
                        UIPasteboard.general.string = r.rewritten
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        copiedRewriteId = r.id
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 1_400_000_000)
                            if copiedRewriteId == r.id { copiedRewriteId = nil }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: copiedRewriteId == r.id ? "checkmark" : "doc.on.doc")
                            Text(copiedRewriteId == r.id ? "Copied" : "Copy")
                        }
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(toneTint(r.tone))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(toneTint(r.tone).opacity(0.14)))
                    }
                }

                Text(r.rewritten)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
        }
    }

    private func toneTint(_ tone: MessageRewrite.Tone) -> Color {
        switch tone {
        case .soft:   return Color(red: 0.48, green: 0.75, blue: 0.56)
        case .honest: return Color(red: 0.44, green: 0.70, blue: 1.00)
        case .repair: return Color(red: 0.95, green: 0.45, blue: 0.60)
        }
    }

    private func runRewrite() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputFocused = false
        isLoading = true
        rewrites = []
        Task {
            defer { isLoading = false }
            do {
                rewrites = try await viewModel.rewrite(text)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
