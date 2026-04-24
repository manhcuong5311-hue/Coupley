//
//  AICoachComponents.swift
//  Coupley
//
//  Shared visual components used across the AI Coach feature.
//

import SwiftUI

// MARK: - Coach Tint → Color Pair

extension CoachTint {
    var primary: Color {
        switch self {
        case .warm:    return Color(red: 1.00, green: 0.55, blue: 0.42)
        case .cool:    return Color(red: 0.44, green: 0.70, blue: 1.00)
        case .rose:    return Color(red: 1.00, green: 0.45, blue: 0.60)
        case .sage:    return Color(red: 0.48, green: 0.75, blue: 0.56)
        case .indigo:  return Color(red: 0.52, green: 0.44, blue: 0.95)
        case .neutral: return Brand.accentStart
        }
    }
    var secondary: Color {
        switch self {
        case .warm:    return Color(red: 1.00, green: 0.78, blue: 0.42)
        case .cool:    return Color(red: 0.60, green: 0.85, blue: 1.00)
        case .rose:    return Color(red: 1.00, green: 0.68, blue: 0.80)
        case .sage:    return Color(red: 0.72, green: 0.88, blue: 0.76)
        case .indigo:  return Color(red: 0.74, green: 0.68, blue: 1.00)
        case .neutral: return Brand.accentEnd
        }
    }
    var gradient: LinearGradient {
        LinearGradient(
            colors: [primary, secondary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Soft Card

struct CoachCard<Content: View>: View {
    var cornerRadius: CGFloat = 22
    var tint: Color? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Brand.surfaceLight)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .strokeBorder(
                                (tint ?? Brand.divider).opacity(tint == nil ? 1 : 0.25),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: .black.opacity(0.09), radius: 14, y: 4)
            )
    }
}

// MARK: - Section Title

struct CoachSectionTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(Brand.textSecondary)
            .textCase(.uppercase)
            .tracking(0.6)
    }
}

// MARK: - Premium Badge

struct CoachPremiumBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "crown.fill")
                .font(.system(size: 9, weight: .bold))
            Text("PREMIUM")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(0.5)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(
                LinearGradient(
                    colors: [
                        Color(red: 1.00, green: 0.82, blue: 0.30),
                        Color(red: 0.95, green: 0.55, blue: 0.20)
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
            )
        )
    }
}

// MARK: - Typing Indicator

struct CoachTypingIndicator: View {

    @State private var phase = 0

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Brand.accentStart.opacity(phase == i ? 1 : 0.35))
                    .frame(width: 7, height: 7)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Brand.surfaceLight)
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Brand.divider, lineWidth: 1))
        )
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { _ in
                Task { @MainActor in
                    phase = (phase + 1) % 3
                }
            }
        }
    }
}

// MARK: - Coach Avatar

struct CoachAvatar: View {
    var size: CGFloat = 34
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.95, green: 0.55, blue: 0.72),
                            Color(red: 0.52, green: 0.44, blue: 0.95)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .shadow(color: Color(red: 0.95, green: 0.55, blue: 0.72).opacity(0.40), radius: 8, y: 2)

            Image(systemName: "sparkle")
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Pillar Meter

struct CoachPillarMeter: View {
    let label: String
    let icon: String
    let score: Int  // 0–100

    private var tint: Color {
        switch score {
        case 80...:  return Color(red: 0.48, green: 0.75, blue: 0.56) // sage
        case 60..<80: return Color(red: 1.00, green: 0.65, blue: 0.30) // warm
        default:      return Color(red: 0.95, green: 0.45, blue: 0.55) // rose
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(tint.opacity(0.18))
                        .frame(width: 30, height: 30)
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tint)
                }
                Text(label)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                Spacer()
                Text("\(score)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Brand.divider.opacity(0.6))
                        .frame(height: 6)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.75), tint],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: max(10, geo.size.width * CGFloat(score) / 100), height: 6)
                }
            }
            .frame(height: 6)
        }
    }
}
