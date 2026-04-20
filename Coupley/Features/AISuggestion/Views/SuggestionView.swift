//
//  SuggestionView.swift
//  Coupley
//
//  Created by Sam Manh Cuong on 1/4/26.
//

import SwiftUI

// MARK: - Suggestion View

struct SuggestionView: View {

    @StateObject private var viewModel: SuggestionViewModel
    @Environment(\.dismiss) private var dismiss

    init(
        moodContext: MoodContext,
        partnerProfile: PartnerProfile,
        suggestionService: AISuggestionService = MockAISuggestionService()
    ) {
        _viewModel = StateObject(wrappedValue: SuggestionViewModel(
            moodContext: moodContext,
            partnerProfile: partnerProfile,
            suggestionService: suggestionService
        ))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.loadState {
                case .idle, .loading:
                    loadingView

                case .loaded:
                    contentView

                case .error(let message):
                    errorView(message: message)
                }
            }
            .navigationTitle("For You")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.medium)
                }
            }
        }
        .onAppear {
            viewModel.loadSuggestions()
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 20) {
            Spacer()

            ProgressView()
                .controlSize(.large)

            Text("Thinking of the best way\nto support your partner...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Content View

    private var contentView: some View {
        ScrollView {
            VStack(spacing: 32) {
                headerSection

                messagesSection

                if let action = viewModel.action {
                    actionSection(action: action)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("\(viewModel.partnerProfile.name) seems \(viewModel.moodContext.mood.label.lowercased())")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Here are some ways you can show you care")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .padding(.top, 8)
    }

    // MARK: - Messages Section

    private var messagesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Send a message", systemImage: "bubble.left.fill")
                .font(.headline)

            ForEach(viewModel.messages) { message in
                MessageCard(
                    message: message,
                    isCopied: viewModel.copiedMessageID == message.id,
                    onCopy: { viewModel.copyMessage(message) }
                )
            }
        }
    }

    // MARK: - Action Section

    private func actionSection(action: ActionSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Do something special", systemImage: "sparkles")
                .font(.headline)

            ActionCard(
                action: action,
                onMarkDone: { viewModel.markActionDone() }
            )
        }
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "cloud.bolt.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Try Again") {
                viewModel.retry()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Message Card

private struct MessageCard: View {

    let message: MessageSuggestion
    let isCopied: Bool
    let onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Tone badge
            Label(message.tone.label, systemImage: message.tone.icon)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(toneColor)

            // Message text
            Text(message.text)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            // Action buttons
            HStack(spacing: 12) {
                Button {
                    onCopy()
                } label: {
                    Label(
                        isCopied ? "Copied!" : "Copy",
                        systemImage: isCopied ? "checkmark" : "doc.on.doc"
                    )
                    .font(.caption)
                    .fontWeight(.medium)
                }
                .foregroundStyle(isCopied ? .green : .accentColor)
                .animation(.default, value: isCopied)

                ShareLink(item: message.text) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }

    private var toneColor: Color {
        switch message.tone {
        case .warm: return .orange
        case .playful: return .purple
        case .supportive: return .blue
        }
    }
}

// MARK: - Action Card

private struct ActionCard: View {

    let action: ActionSuggestion
    let onMarkDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: action.icon)
                    .font(.title3)
                    .foregroundStyle(.orange)

                Text(action.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }

            Text(action.description)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                onMarkDone()
            } label: {
                Label(
                    action.isCompleted ? "Done!" : "Mark as Done",
                    systemImage: action.isCompleted ? "checkmark.circle.fill" : "circle"
                )
                .font(.subheadline)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(action.isCompleted ? .green : .accentColor)
            .disabled(action.isCompleted)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: action.isCompleted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.orange.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.orange.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Previews

#Preview("Loaded") {
    SuggestionView(
        moodContext: MoodContext(
            mood: .sad,
            energy: .low,
            note: "Had a rough day at work",
            lastInteraction: Calendar.current.date(byAdding: .hour, value: -3, to: Date())
        ),
        partnerProfile: .samplePartner
    )
}
