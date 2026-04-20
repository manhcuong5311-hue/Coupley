//
//  MoodCheckinView.swift
//  Coupley
//

import SwiftUI

struct MoodCheckinView: View {

    @ObservedObject var viewModel: MoodViewModel
    @State private var appearedAt = false

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Good morning 🌤"
        case 12..<17: return "Good afternoon ☀️"
        case 17..<21: return "Good evening 🌅"
        default:      return "Good night 🌙"
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Adaptive background
                Color(.systemBackground)
                    .ignoresSafeArea()

                // Mood-tinted ambient glow
                if let mood = viewModel.selectedMood {
                    Circle()
                        .fill(mood.color.opacity(0.12))
                        .frame(width: 340, height: 340)
                        .blur(radius: 80)
                        .offset(x: 60, y: -160)
                        .animation(.easeInOut(duration: 0.8), value: viewModel.selectedMood)
                }

                ScrollView {
                    VStack(spacing: 0) {
                        // Header
                        headerSection
                            .padding(.horizontal, 28)
                            .padding(.top, 8)
                            .padding(.bottom, 36)
                            .opacity(appearedAt ? 1 : 0)
                            .offset(y: appearedAt ? 0 : 12)

                        // Mood cards
                        MoodSelectorView(selectedMood: $viewModel.selectedMood)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 32)
                            .opacity(appearedAt ? 1 : 0)
                            .offset(y: appearedAt ? 0 : 16)

                        // Energy capsule
                        EnergySelectorView(selectedEnergy: $viewModel.selectedEnergy)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 32)
                            .opacity(appearedAt ? 1 : 0)
                            .offset(y: appearedAt ? 0 : 20)

                        // Note
                        NoteInputView(text: $viewModel.noteText)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 32)
                            .opacity(appearedAt ? 1 : 0)
                            .offset(y: appearedAt ? 0 : 24)

                        // Submit
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
                        .padding(.horizontal, 24)
                        .padding(.bottom, 48)
                        .opacity(appearedAt ? 1 : 0)
                        .offset(y: appearedAt ? 0 : 24)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationBarHidden(true)
            .onAppear {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.85).delay(0.05)) {
                    appearedAt = true
                }
            }
            .sheet(isPresented: $viewModel.showSuggestions) {
                if let context = viewModel.lastMoodContext {
                    SuggestionView(moodContext: context, partnerProfile: .samplePartner)
                }
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(greeting)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            Text("How are you\nfeeling today?")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Mood Selector

struct MoodSelectorView: View {

    @Binding var selectedMood: Mood?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionLabel("Mood")

            HStack(spacing: 12) {
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
                    .font(.system(size: 38))
                    .scaleEffect(isSelected ? 1.18 : isPressed ? 0.92 : 1.0)
                    .shadow(
                        color: isSelected ? mood.color.opacity(0.5) : .clear,
                        radius: isSelected ? 10 : 0,
                        y: isSelected ? 4 : 0
                    )
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)

                Text(mood.label)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? mood.color : Color.secondary)
                    .animation(.easeInOut(duration: 0.2), value: isSelected)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(isSelected
                          ? mood.color.opacity(0.12)
                          : Color(.secondarySystemBackground))
                    .shadow(
                        color: isSelected ? mood.color.opacity(0.18) : Color.black.opacity(0.04),
                        radius: isSelected ? 12 : 4,
                        y: isSelected ? 4 : 2
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(
                        isSelected ? mood.color.opacity(0.5) : Color.clear,
                        lineWidth: 1.5
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
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(.secondarySystemBackground))
            )
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
                    .foregroundStyle(isSelected ? level.color : Color.secondary)

                Text(level.label)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(.systemBackground))
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
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(
                                focused ? Color.accentColor.opacity(0.4) : Color.clear,
                                lineWidth: 1.5
                            )
                    )
                    .animation(.easeInOut(duration: 0.2), value: focused)

                if text.isEmpty {
                    Text("What's on your mind today?")
                        .font(.system(size: 16))
                        .foregroundStyle(Color(.tertiaryLabel))
                        .padding(.horizontal, 18)
                        .padding(.top, 17)
                        .allowsHitTesting(false)
                }

                TextField("", text: $text, axis: .vertical)
                    .font(.system(size: 16))
                    .lineLimit(3...7)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .focused($focused)
            }
            .frame(minHeight: 110)
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
        Button(action: action) {
            ZStack {
                // Gradient background
                RoundedRectangle(cornerRadius: 22)
                    .fill(
                        isEnabled
                        ? LinearGradient(
                            colors: [Color(red: 1.0, green: 0.42, blue: 0.42),
                                     Color(red: 1.0, green: 0.60, blue: 0.30)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                          )
                        : LinearGradient(
                            colors: [Color(.systemGray4), Color(.systemGray4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                          )
                    )
                    .frame(height: 58)
                    .shadow(
                        color: isEnabled ? Color(red: 1.0, green: 0.42, blue: 0.42).opacity(0.35) : .clear,
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
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(isEnabled ? .white : Color(.systemGray2))
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
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .kerning(0.6)
            .textCase(.uppercase)
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
