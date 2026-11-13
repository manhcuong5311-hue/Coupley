//
//  MoodCheckinView.swift
//  Coupley
//

import SwiftUI

struct MoodCheckinView: View {

    @ObservedObject var viewModel: MoodViewModel
    @State private var appearedAt = false
    @State private var showInsights = false

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<21: return "Good evening"
        default:      return "Good night"
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Brand background (variant-aware)
                Brand.bgGradient.ignoresSafeArea()

                // Mood-tinted ambient glow (only in variants that use glow)
                if let mood = viewModel.selectedMood,
                   ThemeVariant.current.showsAmbientGlow {
                    Circle()
                        .fill(mood.color.opacity(0.12))
                        .frame(width: 340, height: 340)
                        .blur(radius: 80)
                        .offset(x: 60, y: -160)
                        .animation(.easeInOut(duration: 0.8), value: viewModel.selectedMood)
                }

                ScrollView {
                    VStack(spacing: 0) {
                        // -- T0 --------------------------------------------
                        headerSection
                            .padding(.horizontal, Brand.Space.gutter)
                            .padding(.top, 8)
                            .opacity(appearedAt ? 1 : 0)
                            .offset(y: appearedAt ? 0 : 12)

                        // `todayCheckinCount += 1` runs on the line BEFORE
                        // `submissionState = .success`, and both are @Published
                        // on the same actor, so SwiftUI coalesces them into one
                        // render pass: the limit branch replaced the button in
                        // the very frame it was meant to say "Saved", and the
                        // third check-in of the day could never confirm.
                        if viewModel.hasReachedDailyLimit,
                           viewModel.submissionState == .idle {
                            Color.clear.frame(height: Brand.Space.zone)
                            BrandCard(tier: .quiet) { dailyLimitBanner }
                                .padding(.horizontal, Brand.Space.gutter)
                                .opacity(appearedAt ? 1 : 0)
                        } else {
                            // -- T1 -- picking a mood and saving it are ONE
                            // act, so they are one container. That is also what
                            // lifts the goal-completing button from ~613pt to
                            // ~300pt inside a ~674pt visible box.
                            Color.clear.frame(height: Brand.Space.sibling)
                            checkinHero
                                .padding(.horizontal, SurfaceTier.hero.gutter)
                                .opacity(appearedAt ? 1 : 0)
                                .offset(y: appearedAt ? 0 : 16)

                            // -- T4 -- optional detail, below the act. zone-16
                            // because a ruled quiet block carries its own 16pt.
                            Color.clear.frame(height: Brand.Space.zone - 16)
                            BrandCard(tier: .quiet) {
                                EnergySelectorView(selectedEnergy: $viewModel.selectedEnergy)
                            }
                            .padding(.horizontal, Brand.Space.gutter)
                            .opacity(appearedAt ? 1 : 0)
                            .offset(y: appearedAt ? 0 : 20)

                            Color.clear.frame(height: Brand.Space.sibling)
                            BrandCard(tier: .quiet, showsRule: false) {
                                NoteInputView(text: $viewModel.noteText)
                            }
                            .padding(.horizontal, Brand.Space.gutter)
                            .opacity(appearedAt ? 1 : 0)
                            .offset(y: appearedAt ? 0 : 24)
                        }

                        Color.clear.frame(height: 120)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationBarHidden(true)
            .onAppear {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.85).delay(0.05)) {
                    appearedAt = true
                }
                viewModel.loadTodayCount()
            }
            .sheet(isPresented: $showInsights) {
                MonthlyMoodInsightView()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                // The screen's one uppercase tracked label, in the masthead,
                // on the page -- never on a hero wash, where 13pt
                // textSecondary measures 3.1-3.8:1 in all four resolutions.
                Eyebrow(greeting)

                Text("How are you\nfeeling today?")
                    .font(BrandType.display)
                    .foregroundStyle(Brand.textPrimary)
                    .lineSpacing(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            insightsButton
        }
    }

    /// The whole act of checking in: pick, then save, in one container.
    private var checkinHero: some View {
        BrandCard(tier: .hero,
                  accent: viewModel.selectedMood?.color ?? Brand.accentStart) {
            VStack(spacing: 18) {
                MoodSelectorView(selectedMood: $viewModel.selectedMood)

                SubmitButtonView(
                    state: viewModel.submissionState,
                    isEnabled: viewModel.isSubmitEnabled
                ) {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil, from: nil, for: nil
                    )
                    viewModel.submitMood()
                }
            }
        }
    }

    /// Top-right button that opens the monthly mood journal. Sized to align
    /// with the first line of the headline so it visually anchors against
    /// "Good morning" rather than floating in the corner.
    private var insightsButton: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showInsights = true
        }) {
            ZStack {
                // surfaceLight + a divider ring, matching Home's masthead
                // buttons. NOT the chip tier: a chip's fill is backgroundTop,
                // which is the page gradient's own first stop, so up here a
                // chip would be the exact colour of the page behind it.
                Circle()
                    .fill(Brand.surfaceLight)
                    .overlay(Circle().strokeBorder(Brand.divider, lineWidth: 1))
                    .frame(width: 42, height: 42)
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Brand.textSecondary)
            }
        }
        .buttonStyle(BouncyButtonStyle(scale: 0.92))
        .accessibilityLabel("Open mood journal")
        .padding(.top, 6)
    }

    private var dailyLimitBanner: some View {
        // A finished state never claims emphasis. This was an 80pt accent
        // circle around a 38pt tick inside a full card -- the loudest object
        // on the screen, saying only that there is nothing left to do.
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Brand.textSecondary)
                Text("You've checked in \(MoodViewModel.dailyLimit) times today")
                    .font(BrandType.title)
                    .foregroundStyle(Brand.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Come back tomorrow to share how you're feeling. Your partner can still see your moods.")
                .font(BrandType.body)
                .foregroundStyle(Brand.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Mood Selector

struct MoodSelectorView: View {

    @Binding var selectedMood: Mood?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ForEach(Mood.allCases) { mood in
                    MoodCard(mood: mood, isSelected: selectedMood == mood) {
                        let impact = UIImpactFeedbackGenerator(style: .light)
                        impact.impactOccurred()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                            selectedMood = mood
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Mood Card

private struct MoodCard: View {

    let mood: Mood
    let isSelected: Bool
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Text(mood.emoji)
                    .font(.system(size: 30))
                    .scaleEffect(isSelected ? 1.18 : isPressed ? 0.92 : 1.0)
                    .shadow(
                        color: isSelected ? mood.color.opacity(0.5) : .clear,
                        radius: isSelected ? 10 : 0,
                        y: isSelected ? 4 : 0
                    )
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)

                Text(mood.label)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? mood.color : Brand.textSecondary)
                    .animation(.easeInOut(duration: 0.2), value: isSelected)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: SurfaceTier.chip.radius, style: Brand.cornerStyle)
                    .fill(Brand.surfaceLight)
                    .overlay(
                        RoundedRectangle(cornerRadius: SurfaceTier.chip.radius, style: Brand.cornerStyle)
                            .fill(isSelected ? mood.color.opacity(0.30) : Color.clear)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: SurfaceTier.chip.radius, style: Brand.cornerStyle)
                    .strokeBorder(
                        isSelected ? mood.color.opacity(0.7) : Brand.divider,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.easeInOut(duration: 0.08)) { isPressed = true }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { isPressed = false }
                }
        )
        .accessibilityLabel("\(mood.label) mood")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Energy Selector

struct EnergySelectorView: View {

    @Binding var selectedEnergy: EnergyLevel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionLabel("Energy")

            HStack(spacing: 0) {
                ForEach(EnergyLevel.allCases) { level in
                    EnergyCapsule(
                        level: level,
                        isSelected: selectedEnergy == level,
                        isFirst: level == EnergyLevel.allCases.first,
                        isLast: level == EnergyLevel.allCases.last
                    ) {
                        let impact = UIImpactFeedbackGenerator(style: .light)
                        impact.impactOccurred()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedEnergy = level
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Energy Capsule

private struct EnergyCapsule: View {

    let level: EnergyLevel
    let isSelected: Bool
    let isFirst: Bool
    let isLast: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: level.icon)
                    .font(.system(size: 13, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? level.color : Brand.textSecondary)

                Text(level.label)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Brand.textPrimary : Brand.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Brand.surfaceMid)
                            .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                    }
                }
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(level.label) energy")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Note Input

struct NoteInputView: View {

    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionLabel("Note")

            ZStack(alignment: .topLeading) {
                // The focus ring was the accent at 1.5pt -- a hero signature
                // on an optional field. Same width, no accent spent.
                RoundedRectangle(cornerRadius: Brand.cardCornerRadius, style: Brand.cornerStyle)
                    .fill(Brand.surfaceLight)
                    .overlay(
                        RoundedRectangle(cornerRadius: Brand.cardCornerRadius, style: Brand.cornerStyle)
                            .strokeBorder(
                                focused ? Brand.textTertiary : Brand.divider,
                                lineWidth: 1
                            )
                    )
                    .animation(.easeInOut(duration: 0.2), value: focused)

                if text.isEmpty {
                    Text("What's on your mind today?")
                        .font(BrandType.body)
                        .foregroundStyle(Brand.textTertiary)
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .allowsHitTesting(false)
                }

                TextField("", text: $text, axis: .vertical)
                    .font(BrandType.body)
                    .foregroundStyle(Brand.textPrimary)
                    .lineLimit(2...5)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .focused($focused)
            }
            // Was 110 -- the largest container on the screen, holding the one
            // field nobody has to fill in.
            .frame(minHeight: 64)
        }
    }
}

// MARK: - Submit Button

struct SubmitButtonView: View {

    let state: SubmissionState
    let isEnabled: Bool
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        let radius = Brand.buttonCornerRadius
        let showGlow = ThemeVariant.current.showsAmbientGlow
        // `resetForm()` nils `selectedMood` BEFORE the confirmation sleep, and
        // `isSubmitEnabled` requires a mood -- so driving the fill off
        // `isEnabled` painted the white "Saved" label on the disabled surface.
        // The fill follows the STATE; only idle/error follow the enablement.
        let isFilled: Bool = {
            switch state {
            case .loading, .success, .queued: return true
            case .idle, .error:               return isEnabled
            }
        }()

        Button(action: action) {
            ZStack {
                // Brand-aware background (gradient in classic, flat terracotta in CoupleSync)
                RoundedRectangle(cornerRadius: radius, style: Brand.cornerStyle)
                    .fill(
                        isFilled
                        ? AnyShapeStyle(Brand.accentGradient)
                        // The app's existing disabled idiom (PrimaryButton):
                        // a dimmed accent, so the control still reads as a
                        // button. surfaceMid read as a dead grey slab.
                        : AnyShapeStyle(Brand.accentStart.opacity(0.35))
                    )
                    .frame(height: 58)
                    .shadow(
                        color: (isFilled && showGlow) ? Brand.accentStart.opacity(0.35) : .clear,
                        radius: isPressed ? 4 : 14,
                        y: isPressed ? 2 : 6
                    )

                // Content
                Group {
                    switch state {
                    case .loading:
                        ProgressView().tint(.white)
                    case .success:
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18, weight: .semibold))
                            Text("Saved")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                    case .queued:
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.triangle.2.circlepath.icloud")
                                .font(.system(size: 18, weight: .semibold))
                            Text("Saved — will sync")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                    default:
                        Text("Save how I feel")
                            .font(BrandType.cta)
                            .foregroundStyle(isFilled ? Color.white : Color.white.opacity(0.75))
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.75), value: state)
            }
        }
        .disabled(!isEnabled)
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Section Label

struct SectionLabel: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        // Was a 13pt uppercase tracked label, identical to the two others on
        // this screen plus the greeting. Four of anything carries no signal.
        Text(title)
            .font(BrandType.label)
            .foregroundStyle(Brand.textTertiary)
    }
}

// MARK: - Mood Color

extension Mood {
    var color: Color {
        switch self {
        case .happy:   return Color(red: 1.0, green: 0.76, blue: 0.18)
        case .neutral: return Color(red: 0.40, green: 0.76, blue: 0.95)
        case .sad:     return Color(red: 0.42, green: 0.56, blue: 1.00)
        case .stressed: return Color(red: 1.0, green: 0.45, blue: 0.32)
        }
    }
}

// MARK: - Energy Color

extension EnergyLevel {
    var color: Color {
        switch self {
        case .low:    return Color(red: 0.42, green: 0.56, blue: 1.00)
        case .medium: return Color(red: 0.40, green: 0.76, blue: 0.55)
        case .high:   return Color(red: 1.0,  green: 0.60, blue: 0.20)
        }
    }
}

#Preview {
    MoodCheckinView(viewModel: MoodViewModel(moodService: LocalMoodService()))
}
