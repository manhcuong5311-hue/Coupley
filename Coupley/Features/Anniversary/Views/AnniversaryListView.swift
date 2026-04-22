//
//  AnniversaryListView.swift
//  Coupley
//

import SwiftUI

// MARK: - List View (Tab Root)

struct AnniversaryListView: View {

    @StateObject private var viewModel: AnniversaryViewModel
    @EnvironmentObject private var sessionStore: SessionStore

    @Environment(\.scenePhase) private var scenePhase

    @State private var editorMode: AnniversaryEditorSheet.Mode?
    @State private var showingEditor = false

    private let session: UserSession

    init(session: UserSession) {
        self.session = session
        _viewModel = StateObject(wrappedValue: AnniversaryViewModel(session: session))
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    Color.clear.frame(height: 12)

                    header
                        .padding(.horizontal, 20)

                    if !session.isPaired {
                        notPairedCard
                            .padding(.horizontal, 20)
                    } else if viewModel.anniversaries.isEmpty {
                        emptyState
                            .padding(.horizontal, 20)
                    } else {
                        ForEach(sortedAnniversaries) { item in
                            AnniversaryCard(anniversary: item, now: viewModel.now) {
                                editorMode = .edit(item)
                                showingEditor = true
                            }
                            .padding(.horizontal, 20)
                        }
                    }

                    Color.clear.frame(height: 120)
                }
            }
            .background(Brand.bgGradient.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if session.isPaired {
                    ToolbarItem(placement: .topBarTrailing) {
                        addButton
                    }
                }
            }
            .sheet(isPresented: $showingEditor) {
                if let editorMode {
                    AnniversaryEditorSheet(viewModel: viewModel, mode: editorMode)
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                }
            }
            .onAppear { viewModel.startListening() }
            .onDisappear { viewModel.stopListening() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { viewModel.refresh() }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Our Countdowns")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Brand.textPrimary)

            Text("Shared moments to look forward to.")
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(Brand.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Sorted

    /// Future events first (soonest → furthest), then past events (most recent first).
    private var sortedAnniversaries: [Anniversary] {
        let now = viewModel.now
        return viewModel.anniversaries.sorted { lhs, rhs in
            let lState = CountdownEngine.state(for: lhs.date, now: now)
            let rState = CountdownEngine.state(for: rhs.date, now: now)
            switch (lState, rState) {
            case (.past, .past): return lhs.date > rhs.date
            case (.past, _):     return false
            case (_, .past):     return true
            default:             return lhs.date < rhs.date
            }
        }
    }

    // MARK: - Add Button

    private var addButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            editorMode = .create
            showingEditor = true
        } label: {
            ZStack {
                Circle()
                    .fill(Brand.accentGradient)
                    .frame(width: 34, height: 34)
                    .shadow(color: Brand.accentStart.opacity(0.35), radius: 8, y: 3)
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(BouncyButtonStyle(scale: 0.92))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Brand.accentStart.opacity(0.10))
                    .frame(width: 80, height: 80)
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(Brand.accentStart.opacity(0.85))
            }

            VStack(spacing: 6) {
                Text("No countdowns yet")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)

                Text("Create your first shared moment.\nYour partner will see it instantly.")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            Button {
                editorMode = .create
                showingEditor = true
            } label: {
                Text("Add anniversary")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Brand.accentGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: Brand.accentStart.opacity(0.30), radius: 12, y: 4)
            }
            .buttonStyle(BouncyButtonStyle())
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Brand.surfaceLight)
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Brand.divider, lineWidth: 1))
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        )
    }

    // MARK: - Not Paired

    private var notPairedCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "link.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(Brand.accentStart)

            Text("Connect with your partner first")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Brand.textPrimary)

            Text("Anniversaries sync between both of you —\npair up to start sharing countdowns.")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(Brand.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Brand.surfaceLight)
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Brand.divider, lineWidth: 1))
        )
    }
}

// MARK: - Preview

#Preview {
    AnniversaryListView(session: .demo)
        .environmentObject(SessionStore())
}
