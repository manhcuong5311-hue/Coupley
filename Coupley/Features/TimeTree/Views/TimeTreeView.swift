//
//  TimeTreeView.swift
//  Coupley
//
//  The Time Tree tab root. Replaces the previous AnniversaryListView.
//  Composition:
//   1. Section 1 — TimeTreeHeader (days together + countdowns)
//   2. Section 2 — RelationshipTreeCanvas (the animated hero tree),
//      flanked by tap chips for the growth stage and the next milestone.
//   3. Section 3 — MemoryTimelineSection (locked capsules + visible memories)
//
//  Top-bar trailing button opens the milestone picker. Tapping the tree
//  opens the anchor editor (or the setup sheet on first run). Tapping
//  any memory card opens the detail sheet.
//
//  Crown celebrations are surfaced via the overlay layer and only fire
//  on the day a milestone is reached, gated by a per-couple-per-device
//  flag inside the view model.
//

import SwiftUI

// MARK: - Tab Root

struct TimeTreeView: View {

    @StateObject private var viewModel: TimeTreeViewModel
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var premiumStore: PremiumStore

    @Environment(\.scenePhase) private var scenePhase

    private let session: UserSession
    private let displayName: String?

    @State private var showMilestonePicker = false
    @State private var pendingNewKind: MemoryKind?
    @State private var showMemoryEditor = false
    @State private var selectedMemory: TimeMemory?
    @State private var showAnchorSheet = false

    init(session: UserSession, displayName: String? = nil) {
        self.session = session
        self.displayName = displayName
        _viewModel = StateObject(wrappedValue: TimeTreeViewModel(session: session))
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        Color.clear.frame(height: 8)

                        if !session.isPaired {
                            notPairedCard
                                .padding(.horizontal, 20)
                        } else {
                            // Section 1
                            TimeTreeHeader(
                                anchor: viewModel.anchor,
                                now: viewModel.now,
                                onSetAnchorTapped: { showAnchorSheet = true }
                            )
                            .padding(.horizontal, 20)

                            // Section 2 — only when an anchor exists
                            if viewModel.anchor != nil {
                                treeStage
                                    .padding(.horizontal, 12)
                            }

                            // Section 3
                            MemoryTimelineSection(
                                lockedCapsules: viewModel.lockedCapsules,
                                visibleMemories: viewModel.visibleMemories,
                                now: viewModel.now,
                                onAddTapped: { showMilestonePicker = true },
                                onSelectMemory: { memory in
                                    selectedMemory = memory
                                }
                            )
                            .padding(.horizontal, 20)
                        }

                        Color.clear.frame(height: 120)
                    }
                }
                .background(Brand.bgGradient.ignoresSafeArea())

                // Crown celebration overlay
                if let crown = viewModel.pendingCrownCelebration {
                    CrownCelebrationOverlay(
                        milestone: crown,
                        onDismiss: { viewModel.acknowledgeCrown() }
                    )
                    .transition(.opacity)
                    .zIndex(900)
                }
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.85),
                       value: viewModel.pendingCrownCelebration?.id)
            .navigationTitle("Time Tree")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if session.isPaired && viewModel.anchor != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        addButton
                    }
                }
            }
            .onAppear {
                viewModel.startListening()
            }
            .onDisappear {
                viewModel.stopListening()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { viewModel.refresh() }
            }
            .sheet(isPresented: $showMilestonePicker) {
                MilestonePickerSheet { kind in
                    pendingNewKind = kind
                    showMemoryEditor = true
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showMemoryEditor, onDismiss: { pendingNewKind = nil }) {
                if let kind = pendingNewKind {
                    MemoryEditorSheet(viewModel: viewModel, mode: .create(kind))
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                }
            }
            .sheet(item: $selectedMemory) { memory in
                MemoryDetailSheet(viewModel: viewModel, memory: memory)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showAnchorSheet) {
                AnchorSetupSheet(
                    viewModel: viewModel,
                    existing: viewModel.anchor,
                    displayName: displayName
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Tree stage (Section 2)

    private var treeStage: some View {
        VStack(spacing: 12) {
            // The animated tree
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Brand.surfaceLight.opacity(0.85),
                                Brand.surfaceLight.opacity(0.45)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Brand.divider,
                                        Brand.accentStart.opacity(0.18)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )

                RelationshipTreeCanvas(
                    stage: viewModel.growthStage,
                    season: viewModel.currentSeason,
                    daysTogether: viewModel.daysTogether ?? 0,
                    memoryCount: viewModel.visibleMemories.count,
                    crownActive: viewModel.growthStage.showsAmbientCrown
                )
                .frame(maxWidth: .infinity)
                .frame(height: 360)

                // Bottom-left tap target on the tree (edit anchor)
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            showAnchorSheet = true
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "pencil")
                                    .font(.system(size: 10, weight: .semibold))
                                Text("Anchor")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                            }
                            .foregroundStyle(Brand.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(.ultraThinMaterial)
                                    .overlay(Capsule().strokeBorder(Brand.divider, lineWidth: 0.5))
                            )
                        }
                        .buttonStyle(BouncyButtonStyle(scale: 0.94))
                        .padding(.trailing, 14)
                        .padding(.bottom, 14)
                    }
                }
            }
            .frame(height: 360)
            .padding(.horizontal, 8)

            // Stage + season chips
            HStack(spacing: 8) {
                stageChip(
                    icon: viewModel.growthStage == .ancient ? "tree.fill" : "leaf.fill",
                    label: viewModel.growthStage.displayName,
                    accent: Brand.accentStart
                )

                stageChip(
                    icon: "circle.dotted",
                    label: viewModel.currentSeason.displayName,
                    accent: seasonAccent
                )

                Spacer()

                memoryCountChip
            }
            .padding(.horizontal, 12)
        }
    }

    private var seasonAccent: Color {
        switch viewModel.currentSeason {
        case .spring: return Color(red: 0.55, green: 0.78, blue: 0.50)
        case .summer: return Color(red: 0.95, green: 0.65, blue: 0.30)
        case .autumn: return Color(red: 0.85, green: 0.45, blue: 0.25)
        case .winter: return Color(red: 0.55, green: 0.70, blue: 0.85)
        }
    }

    private func stageChip(icon: String, label: String, accent: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(accent)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(accent.opacity(0.14))
                .overlay(Capsule().strokeBorder(accent.opacity(0.25), lineWidth: 0.5))
        )
    }

    private var memoryCountChip: some View {
        let count = viewModel.visibleMemories.count + viewModel.lockedCapsules.count
        return HStack(spacing: 5) {
            Image(systemName: "sparkles")
                .font(.system(size: 10, weight: .semibold))
            Text("\(count) \(count == 1 ? "memory" : "memories")")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(Brand.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Brand.surfaceLight)
                .overlay(Capsule().strokeBorder(Brand.divider, lineWidth: 0.5))
        )
    }

    // MARK: - Add button

    private var addButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            showMilestonePicker = true
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

    // MARK: - Not Paired

    private var notPairedCard: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Brand.accentStart.opacity(0.10))
                    .frame(width: 76, height: 76)
                Image(systemName: "leaf.fill")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Brand.accentStart.opacity(0.85))
            }

            VStack(spacing: 6) {
                Text("Connect with your partner first")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                Text("Your Time Tree grows together — pair up to plant the seed.")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity)
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

// MARK: - Preview

#Preview {
    TimeTreeView(session: .demo, displayName: "Sam")
        .environmentObject(SessionStore())
        .environmentObject(PremiumStore())
}
