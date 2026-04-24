//
//  PartnerAndMeProfileView.swift
//  Coupley
//
//  Hub screen opened from the Chat header. Shows "Me" and "Partner"
//  avatars side-by-side and pushes into the appropriate detail screen.
//

import SwiftUI

struct PartnerAndMeProfileView: View {

    @ObservedObject var profileViewModel: CouplePersonProfileViewModel
    let session: UserSession

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.bgGradient.ignoresSafeArea()

                VStack(spacing: 24) {
                    Text("Get to know each other")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                        .padding(.top, 8)

                    Text("Tap an avatar to see likes, dislikes, communication style, and shared activities.")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    HStack(spacing: 18) {
                        avatarLink(
                            profile: profileViewModel.myProfile,
                            userId: session.userId,
                            mode: .mine,
                            subtitle: "You"
                        )

                        avatarLink(
                            profile: profileViewModel.partnerProfile,
                            userId: session.partnerId,
                            mode: .partner,
                            subtitle: "Partner"
                        )
                        .opacity(session.isPaired ? 1 : 0.45)
                        .disabled(!session.isPaired)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                    if !session.isPaired {
                        Text("Connect your partner from Home to view their profile.")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(Brand.textTertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }

                    Spacer()
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Brand.accentStart)
                }
            }
        }
    }

    // MARK: - Avatar tile (NavigationLink)

    private func avatarLink(
        profile: CouplePersonProfile,
        userId: String,
        mode: PartnerProfileDetailViewModel.Mode,
        subtitle: String
    ) -> some View {
        NavigationLink {
            PartnerProfileDetailView(
                targetUserId: userId,
                currentUserId: session.userId,
                mode: mode,
                hasPartner: session.isPaired,
                avatar: profile.avatar,
                displayName: profile.displayName,
                // Non-owner contributor in both screens is always the viewer's
                // partner, so the pronoun label is derived from their avatar.
                partnerPronounLabel: profileViewModel.partnerProfile.avatar.pronounLabel
            )
        } label: {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Brand.backgroundTop)
                        .overlay(Circle().strokeBorder(Brand.divider, lineWidth: 1))
                    profile.avatar.image()
                        .clipShape(Circle())
                        .padding(4)
                }
                .frame(width: 118, height: 118)
                .shadow(color: .black.opacity(0.15), radius: 16, y: 6)

                Text(profile.displayName)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                    .lineLimit(1)

                Text(subtitle.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.textTertiary)
                    .tracking(0.6)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(Brand.surfaceLight)
                    .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Brand.divider, lineWidth: 1))
            )
        }
        .buttonStyle(BouncyButtonStyle(scale: 0.96))
    }
}
