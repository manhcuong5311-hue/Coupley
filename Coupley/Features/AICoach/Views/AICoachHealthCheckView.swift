//
//  AICoachHealthCheckView.swift
//  Coupley
//
//  Premium tool: 5-pillar relationship health snapshot — trust, communication,
//  emotional intimacy, support, consistency — plus a plain-English summary
//  and any red-flag patterns worth watching.
//

import SwiftUI

struct AICoachHealthCheckView: View {

    @ObservedObject var viewModel: AICoachViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var health: RelationshipHealth?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Brand.bgGradient.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    header
                        .padding(.top, 6)
                        .padding(.horizontal, 20)

                    if isLoading {
                        loadingCard
                            .padding(.horizontal, 20)
                    } else if let h = health {
                        overallCard(h)
                            .padding(.horizontal, 20)

                        pillarsCard(h)
                            .padding(.horizontal, 20)

                        summaryCard(h)
                            .padding(.horizontal, 20)

                        if !h.redFlags.isEmpty {
                            redFlagsCard(h)
                                .padding(.horizontal, 20)
                        }

                        rerunButton
                            .padding(.horizontal, 20)
                    }

                    Color.clear.frame(height: 60)
                }
                .padding(.top, 10)
            }
        }
        .navigationTitle("Health Check")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") { dismiss() }
                    .foregroundStyle(Brand.textSecondary)
            }
        }
        .onAppear { if health == nil { runHealthCheck() } }
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
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.95, green: 0.45, blue: 0.60),
                                Color(red: 1.00, green: 0.65, blue: 0.75)
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Relationship Health")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                Text("A snapshot across five foundations.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
            }
            Spacer()
        }
    }

    private var loadingCard: some View {
        CoachCard {
            VStack(spacing: 14) {
                ProgressView().tint(Brand.accentStart)
                Text("Reading the signals across your connection…")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(30)
        }
    }

    private func overallCard(_ h: RelationshipHealth) -> some View {
        CoachCard {
            VStack(spacing: 14) {
                CoachSectionTitle(text: "Overall Score")
                    .frame(maxWidth: .infinity, alignment: .center)

                ZStack {
                    Circle()
                        .stroke(Brand.divider.opacity(0.5), lineWidth: 10)
                        .frame(width: 140, height: 140)

                    Circle()
                        .trim(from: 0, to: CGFloat(h.overall) / 100)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.95, green: 0.55, blue: 0.72),
                                    Color(red: 0.52, green: 0.44, blue: 0.95)
                                ],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .frame(width: 140, height: 140)
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 2) {
                        Text("\(h.overall)")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundStyle(Brand.textPrimary)
                        Text("of 100")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Brand.textSecondary)
                    }
                }

                Text(verdict(for: h.overall))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
            }
            .padding(20)
            .frame(maxWidth: .infinity)
        }
    }

    private func pillarsCard(_ h: RelationshipHealth) -> some View {
        CoachCard {
            VStack(alignment: .leading, spacing: 18) {
                CoachSectionTitle(text: "By Pillar")
                ForEach(RelationshipHealth.Pillar.allCases, id: \.self) { pillar in
                    CoachPillarMeter(
                        label: pillar.label,
                        icon: pillar.icon,
                        score: h.score(for: pillar)
                    )
                }
            }
            .padding(18)
        }
    }

    private func summaryCard(_ h: RelationshipHealth) -> some View {
        CoachCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "text.bubble.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Brand.accentStart)
                    CoachSectionTitle(text: "Coach's read")
                }

                Text(h.summary)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
        }
    }

    private func redFlagsCard(_ h: RelationshipHealth) -> some View {
        CoachCard(tint: Color(red: 0.95, green: 0.55, blue: 0.35)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(red: 0.95, green: 0.55, blue: 0.35))
                    CoachSectionTitle(text: "Patterns to watch")
                }

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(h.redFlags, id: \.self) { flag in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(Color(red: 0.95, green: 0.55, blue: 0.35))
                                .frame(width: 5, height: 5)
                                .padding(.top, 7)
                            Text(flag)
                                .font(.system(size: 13, design: .rounded))
                                .foregroundStyle(Brand.textPrimary)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(18)
        }
    }

    private var rerunButton: some View {
        Button {
            runHealthCheck()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                Text("Run again")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(Brand.textSecondary)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(
                Capsule()
                    .fill(Brand.surfaceLight)
                    .overlay(Capsule().strokeBorder(Brand.divider, lineWidth: 1))
            )
        }
        .buttonStyle(BouncyButtonStyle())
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func verdict(for score: Int) -> String {
        switch score {
        case 85...: return "Thriving. Keep showing up like this."
        case 75..<85: return "Strong foundation. Minor tune-ups ahead."
        case 65..<75: return "Healthy but uneven — room to deepen."
        case 50..<65: return "Worth some intentional care this month."
        default:      return "Needs attention. The coach has suggestions."
        }
    }

    private func runHealthCheck() {
        isLoading = true
        health = nil
        Task {
            defer { isLoading = false }
            do {
                health = try await viewModel.runHealthCheck()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
