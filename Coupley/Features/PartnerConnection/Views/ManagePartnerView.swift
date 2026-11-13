//
//  ManagePartnerView.swift
//  Coupley
//
//  Opened from Settings → Partner when a partner is connected. Shows the
//  current connection, the Disconnect button with confirmation dialog,
//  and a link into "Manage shared data" after disconnect.
//

import SwiftUI

struct ManagePartnerView: View {

    let session: UserSession
    let partnerDisplayName: String?

    @EnvironmentObject private var sessionStore: SessionStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ManagePartnerViewModel()
    @State private var showDisconnectConfirm = false

    var body: some View {
        ZStack {
            Brand.bgGradient.ignoresSafeArea()

            List {
                statusSection
                disconnectSection
                sharedDataSection
                if let error = viewModel.errorMessage {
                    errorSection(error)
                }
            }
            .scrollContentBackground(.hidden)
            .listRowSpacing(8)
        }
        .navigationTitle(Text("Partner", comment: "Navigation title: manage the connection with your partner"))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Disconnect from your partner?",
            isPresented: $showDisconnectConfirm,
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) {
                viewModel.disconnect(
                    session: session,
                    partnerDisplayName: partnerDisplayName
                )
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will stop syncing with this person. Your shared data will be kept unless you choose to remove it later.")
        }
        .onChange(of: viewModel.didDisconnect) { _, done in
            // After disconnect, SessionStore flips appState → needsPairing
            // and the RootView rebuilds. This dismiss just closes the
            // Settings stack cleanly so the user lands on the pairing UI.
            if done { dismiss() }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var statusSection: some View {
        Section {
            row(icon: "heart.fill", tint: Brand.accentStart,
                title: partnerDisplayName.flatMap { $0.isEmpty ? nil : Text(verbatim: $0) }
                    ?? Text("Your partner"),
                subtitle: Text("Connected · syncing in real time"))
            row(icon: "link", tint: Brand.textSecondary,
                title: Text("Connection ID"),
                subtitle: Text(verbatim: session.coupleId),
                monospaced: true)
        } header: {
            Text("Connection", comment: "Section header: details of a partner connection")
        }
        .listRowBackground(surfaceRowBackground)
    }

    @ViewBuilder
    private var disconnectSection: some View {
        Section {
            Button(role: .destructive) {
                showDisconnectConfirm = true
            } label: {
                HStack(spacing: 12) {
                    if viewModel.isDisconnecting {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "link.badge.plus")
                            .rotationEffect(.degrees(45))
                            .foregroundStyle(Color(red: 1.0, green: 0.40, blue: 0.40))
                    }
                    Text(viewModel.isDisconnecting ? "Disconnecting…" : "Disconnect")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(red: 1.0, green: 0.40, blue: 0.40))
                    Spacer()
                }
            }
            .disabled(viewModel.isDisconnecting)
        } footer: {
            Text("Disconnecting stops real-time sync immediately. Your shared data stays in storage until you choose to delete it.")
                .font(.system(size: 12, design: .rounded))
        }
        .listRowBackground(surfaceRowBackground)
    }

    @ViewBuilder
    private var sharedDataSection: some View {
        if let lastCoupleId = sessionStore.lastCoupleId, !lastCoupleId.isEmpty {
            Section("Previous connection") {
                NavigationLink {
                    ManageSharedDataView(
                        connectionId: lastCoupleId,
                        partnerDisplayName: sessionStore.lastPartnerName
                    )
                } label: {
                    row(icon: "tray.full.fill", tint: Brand.textSecondary,
                        title: Text("Manage shared data"),
                        subtitle: Text("Review or delete data from a past partner"))
                }
            }
            .listRowBackground(surfaceRowBackground)
        }
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
    /// translation) or `Text(verbatim:)` for a name or an id.
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
}
