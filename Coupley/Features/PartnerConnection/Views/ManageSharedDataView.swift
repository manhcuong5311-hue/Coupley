//
//  ManageSharedDataView.swift
//  Coupley
//
//  Deep-cleanup screen for an already-disconnected couple. Summarises
//  what's still in storage and offers a single destructive action:
//  "Delete all shared data".
//

import SwiftUI

struct ManageSharedDataView: View {

    let connectionId: String
    let partnerDisplayName: String?

    @EnvironmentObject private var sessionStore: SessionStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ManagePartnerViewModel()
    @State private var showDeleteConfirm = false

    var body: some View {
        ZStack {
            Brand.bgGradient.ignoresSafeArea()

            List {
                summarySection
                deleteSection
                if let error = viewModel.errorMessage {
                    errorSection(error)
                }
            }
            .scrollContentBackground(.hidden)
            .listRowSpacing(8)
        }
        .navigationTitle("Shared Data")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.loadArchived(connectionId: connectionId) }
        .confirmationDialog(
            "Delete all shared data?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Everything", role: .destructive) {
                guard let userId = sessionStore.session?.userId
                        ?? sessionStore.soloUserId else { return }
                viewModel.deleteSharedData(connectionId: connectionId, userId: userId)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove all shared messages, activities, and events.")
        }
        .onChange(of: viewModel.didDeleteSharedData) { _, done in
            if done { dismiss() }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var summarySection: some View {
        Section {
            row(
                icon: "clock.arrow.circlepath",
                tint: Brand.textSecondary,
                title: Text("Previous partner"),
                subtitle: partnerDisplayName.flatMap { $0.isEmpty ? nil : Text(verbatim: $0) }
                    ?? Text("Former partner", comment: "Stands in for the name of a past partner that wasn't saved")
            )
            row(
                icon: "link",
                tint: Brand.textSecondary,
                title: Text("Connection ID"),
                subtitle: Text(verbatim: connectionId),
                monospaced: true
            )
            if let disconnectedAt = viewModel.archivedConnection?.disconnectedAt {
                row(
                    icon: "calendar",
                    tint: Brand.textSecondary,
                    title: Text("Disconnected", comment: "Row title above the date the connection ended"),
                    subtitle: Text(verbatim: Self.dateFormatter.string(from: disconnectedAt))
                )
            }
        } header: {
            Text("Connection", comment: "Section header: details of a partner connection")
        }
        .listRowBackground(surfaceRowBackground)
    }

    @ViewBuilder
    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                HStack(spacing: 12) {
                    if viewModel.isDeleting {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "trash.fill")
                            .foregroundStyle(Color(red: 1.0, green: 0.40, blue: 0.40))
                    }
                    Text(viewModel.isDeleting ? "Deleting…" : "Delete all shared data")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(red: 1.0, green: 0.40, blue: 0.40))
                    Spacer()
                }
            }
            .disabled(viewModel.isDeleting)
        } footer: {
            Text("Removes messages, moods, quizzes, letters, and insights tied to this connection from the server. This cannot be undone.")
                .font(.system(size: 12, design: .rounded))
        }
        .listRowBackground(surfaceRowBackground)
    }

    private func errorSection(_ message: String) -> some View {
        Section {
            Text(message)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Brand.textSecondary)
        }
        .listRowBackground(surfaceRowBackground)
    }

    // MARK: - Helpers

    /// `Text` parameters: callers pass a literal (app copy, extracted for
    /// translation) or `Text(verbatim:)` for a name, an id or a date.
    private func row(
        icon: String,
        tint: Color,
        title: Text,
        subtitle: Text,
        monospaced: Bool = false
    ) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(tint.opacity(0.15))
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                title
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                // An id keeps its one line, cut in the middle; prose gets a
                // second line, since translations run longer than English.
                subtitle
                    .font(monospaced
                          ? .system(size: 11, design: .monospaced)
                          : .system(size: 12, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
                    .lineLimit(monospaced ? 1 : 2)
                    .truncationMode(monospaced ? .middle : .tail)
            }
            Spacer()
        }
    }

    private var surfaceRowBackground: some View {
        RoundedRectangle(cornerRadius: 12).fill(Brand.surfaceLight)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}
