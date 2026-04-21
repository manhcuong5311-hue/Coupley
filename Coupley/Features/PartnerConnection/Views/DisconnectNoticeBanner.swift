//
//  DisconnectNoticeBanner.swift
//  Coupley
//
//  One-shot banner shown to the user whose partner disconnected. Reads
//  the `pendingDisconnectNotice` flag from SessionStore and clears it
//  when dismissed.
//

import SwiftUI

struct DisconnectNoticeBanner: View {

    @EnvironmentObject private var sessionStore: SessionStore
    private let service: ConnectionService = FirestoreConnectionService()

    var body: some View {
        if sessionStore.pendingDisconnectNotice,
           let userId = sessionStore.soloUserId ?? sessionStore.session?.userId {
            banner(userId: userId)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func banner(userId: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(red: 1.0, green: 0.40, blue: 0.40).opacity(0.18))
                    .frame(width: 36, height: 36)
                Image(systemName: "heart.slash.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(red: 1.0, green: 0.40, blue: 0.40))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Your partner has disconnected")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button {
                Task {
                    try? await service.acknowledgeDisconnectNotice(userId: userId)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Brand.textSecondary)
                    .padding(8)
                    .background(Circle().fill(Brand.surfaceLight))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Brand.backgroundTop)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color(red: 1.0, green: 0.40, blue: 0.40).opacity(0.30), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        )
    }

    private var subtitle: String {
        if let name = sessionStore.lastPartnerName, !name.isEmpty {
            return "\(name) ended the connection. Your shared data is still saved — you can review or delete it from Settings."
        }
        return "Your shared data is still saved — you can review or delete it from Settings."
    }
}
