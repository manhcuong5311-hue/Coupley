//
//  OnboardingComponents.swift
//  Coupley
//
//  Shared UI primitives every onboarding step uses. Keeping these here
//  means each step file stays focused on copy + layout, and the navigation
//  chrome (back arrow, progress, Continue button) is consistent.
//

import SwiftUI

// MARK: - Step Scaffold

/// Standard scaffold every onboarding step renders inside.
///
/// Layout:
///   [TopBar: back · progress · skip]
///   ScrollView { content }
///   [BottomCTA: primary action + optional secondary]
struct OnboardingStepScaffold<Content: View>: View {

    @ObservedObject var viewModel: OnboardingViewModel
    var primaryTitle: String = "Continue"
    var secondaryTitle: String? = nil
    var canAdvance: Bool = true
    var hideBack: Bool = false
    var hideProgress: Bool = false
    var primaryAction: (() -> Void)? = nil
    var secondaryAction: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView(showsIndicators: false) {
                content()
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)

            bottomCTA
        }
        .brandBackground()
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            if !hideBack && viewModel.step.rawValue > 0 {
                Button { viewModel.back() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Brand.textSecondary)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(Brand.surfaceLight)
                                .overlay(Circle().strokeBorder(Brand.divider, lineWidth: 1))
                        )
                }
                .buttonStyle(BouncyButtonStyle())
                .accessibilityLabel("Back")
            } else {
                Color.clear.frame(width: 36, height: 36)
            }

            if !hideProgress, let _ = viewModel.step.progressIndex {
                ProgressBar(step: viewModel.step)
                    .frame(maxWidth: .infinity)
            } else {
                Spacer()
            }

            if viewModel.step.allowsSkip {
                Button("Skip") { viewModel.skip() }
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
                    .frame(width: 50, height: 36)
            } else {
                Color.clear.frame(width: 50, height: 36)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    // MARK: - Bottom CTA

    private var bottomCTA: some View {
        VStack(spacing: 10) {
            if let secondaryTitle, let secondaryAction {
                Button(secondaryTitle, action: secondaryAction)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
            }

            PrimaryButton(title: primaryTitle, isEnabled: canAdvance) {
                if let primaryAction {
                    primaryAction()
                } else {
                    viewModel.advance()
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .padding(.top, 8)
        .background(
            // Subtle shelf so the CTA reads even when content scrolls underneath.
            Brand.backgroundTop.opacity(0.0)
        )
    }
}

// MARK: - Progress Bar

struct ProgressBar: View {
    let step: OnboardingStep

    private var totalInputSteps: Int {
        // Show progress only across the steps that have a `progressIndex`.
        OnboardingStep.allCases.filter { $0.progressIndex != nil }.count
    }

    private var currentIndex: Int {
        guard let raw = step.progressIndex else { return 0 }
        // Re-index from 1 based on order among progress-eligible steps.
        let order = OnboardingStep.allCases
            .filter { $0.progressIndex != nil }
            .map { $0.rawValue }
        return (order.firstIndex(of: raw) ?? 0) + 1
    }

    var body: some View {
        GeometryReader { geo in
            let total = max(1, totalInputSteps)
            let progress = CGFloat(currentIndex) / CGFloat(total)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Brand.divider)
                    .frame(height: 4)

                Capsule()
                    .fill(Brand.accentGradient)
                    .frame(width: geo.size.width * progress, height: 4)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: progress)
            }
        }
        .frame(height: 4)
    }
}

// MARK: - Step Header

/// Title + supporting copy that anchors every step. `eyebrow` is an
/// optional small uppercase label shown above the title.
struct StepHeader: View {
    var eyebrow: String? = nil
    let title: String
    var subtitle: String? = nil
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 10) {
            if let eyebrow {
                Text(eyebrow.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(Brand.accentStart)
            }
            Text(title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(Brand.textPrimary)
                .multilineTextAlignment(textAlignment(for: alignment))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
                    .multilineTextAlignment(textAlignment(for: alignment))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: frameAlignment(for: alignment))
    }

    private func textAlignment(for h: HorizontalAlignment) -> TextAlignment {
        switch h {
        case .leading: return .leading
        case .trailing: return .trailing
        default: return .center
        }
    }

    private func frameAlignment(for h: HorizontalAlignment) -> Alignment {
        switch h {
        case .leading: return .leading
        case .trailing: return .trailing
        default: return .center
        }
    }
}

// MARK: - Hero Illustration

/// Reusable hero block: centered icon in a soft circle + accent glow.
struct OnboardingHeroIcon: View {
    let icon: String
    var tint: Color = Brand.accentStart
    var size: CGFloat = 90

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.15))
                .frame(width: size * 1.8, height: size * 1.8)
                .blur(radius: 32)

            Circle()
                .fill(Brand.surfaceLight)
                .frame(width: size, height: size)
                .overlay(Circle().strokeBorder(Brand.divider, lineWidth: 1))

            Image(systemName: icon)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(tint)
                .symbolRenderingMode(.hierarchical)
        }
    }
}

// MARK: - Selectable Card

/// Reusable selection row used by Goals, Communication Style, etc.
struct SelectableCard<Trailing: View>: View {

    let icon: String
    let title: String
    var subtitle: String? = nil
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    init(icon: String,
         title: String,
         subtitle: String? = nil,
         isSelected: Bool,
         action: @escaping () -> Void,
         @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.isSelected = isSelected
        self.action = action
        self.trailing = trailing
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isSelected
                              ? Brand.accentStart.opacity(0.18)
                              : Brand.accentStart.opacity(0.10))
                        .frame(width: 42, height: 42)

                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Brand.accentStart)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(Brand.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                trailing()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected
                          ? Brand.accentStart.opacity(0.10)
                          : Brand.surfaceLight)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(
                                isSelected ? Brand.accentStart.opacity(0.55) : Brand.divider,
                                lineWidth: isSelected ? 1.5 : 1
                            )
                    )
            )
        }
        .buttonStyle(BouncyButtonStyle(scale: 0.985))
    }
}

// MARK: - Benefit Tile

/// 4-up grid tile used on the BenefitsStep.
struct BenefitTile: View {
    let icon: String
    let tint: Color
    let title: String
    let copy: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(tint.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
            }
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Brand.textPrimary)
            Text(copy)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(Brand.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Brand.surfaceLight)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(Brand.divider, lineWidth: 1)
                )
        )
    }
}
