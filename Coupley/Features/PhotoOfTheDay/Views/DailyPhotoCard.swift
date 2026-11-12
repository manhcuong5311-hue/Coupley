//
//  DailyPhotoCard.swift
//  Coupley
//
//  Home card for the daily photo prompt. Three states, matching the quiz's
//  shape: send yours, wait for theirs, then both at once.
//
//  The partner's photo is never fetched before the reveal — it is simply not
//  rendered — so the wait is real rather than a UI curtain over data the
//  device already holds.
//

import SwiftUI
import PhotosUI

struct DailyPhotoCard: View {

    @ObservedObject var viewModel: DailyPhotoViewModel
    let partnerName: String

    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        Group {
            switch viewModel.state {
            case .hidden:
                EmptyView()
            case .loading:
                EmptyView()
            case .awaitingMe(let photo):
                card(accent: Brand.accentStart) { awaitingMe(photo) }
            case .awaitingPartner(let photo):
                card(accent: waiting) { awaitingPartner(photo) }
            case .revealed(let photo):
                card(accent: done) { revealed(photo) }
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.85), value: viewModel.state)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    viewModel.submit(image)
                }
                await MainActor.run { pickerItem = nil }
            }
        }
    }

    private var waiting: Color { Color(red: 0.52, green: 0.44, blue: 0.95) }
    private var done: Color { Color(red: 0.25, green: 0.75, blue: 0.50) }

    // MARK: - Container

    private func card<C: View>(accent: Color, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Photo of the day")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Text(subtitle)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Brand.textTertiary)
                }
                Spacer()
                Image(systemName: "camera.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent)
            }
            content()

            // Without this a failed upload is indistinguishable from never
            // having tapped: the button simply returns to its idle title and
            // the card says nothing. The view model has always recorded the
            // error; nothing rendered it.
            if let error = viewModel.errorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.45))
                    Text(error)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(red: 1.0, green: 0.45, blue: 0.45).opacity(0.12))
                )
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Brand.surfaceLight)
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .strokeBorder(accent.opacity(0.22), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.08), radius: 12, y: 3)
        )
    }

    private var subtitle: String {
        switch viewModel.state {
        case .awaitingMe:      return "Send yours to unlock theirs"
        case .awaitingPartner: return "\(partnerName) hasn't sent one yet"
        case .revealed:        return "Both of you, same moment"
        case .loading, .hidden: return " "
        }
    }

    // MARK: - States

    private func awaitingMe(_ photo: DailyPhoto) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(photo.prompt)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(Brand.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if photo.hasSubmitted(viewModel.partnerUserId) {
                Text("\(partnerName) already sent theirs. It stays hidden until you do.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            PhotosPicker(selection: $pickerItem, matching: .images) {
                HStack(spacing: 7) {
                    if viewModel.isUploading {
                        ProgressView().tint(.white).controlSize(.small)
                    } else {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    Text(viewModel.isUploading ? "Sending…" : "Send a photo")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: Brand.buttonCornerRadius)
                        .fill(Brand.accentGradient)
                )
            }
            .disabled(viewModel.isUploading)
        }
    }

    private func awaitingPartner(_ photo: DailyPhoto) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(photo.prompt)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Brand.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                thumbnail(photo.photoURL(for: viewModel.myUserId), label: "You")
                lockedThumbnail
            }

            Text("\(partnerName)'s photo appears the moment they send one.")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(Brand.textTertiary)
        }
    }

    private func revealed(_ photo: DailyPhoto) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(photo.prompt)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Brand.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                thumbnail(photo.photoURL(for: viewModel.myUserId), label: "You")
                thumbnail(photo.photoURL(for: viewModel.partnerUserId), label: partnerName)
            }
        }
    }

    // MARK: - Pieces

    private func thumbnail(_ urlString: String?, label: String) -> some View {
        VStack(spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(Brand.backgroundTop)
                if let urlString, let url = URL(string: urlString) {
                    // Not AsyncImage: it refetches whenever the row is
                    // rebuilt, which inside a ScrollView is every time it
                    // scrolls back into range.
                    CachedRemoteImage(url: url) {
                        ProgressView().tint(Brand.accentStart)
                    } failure: {
                        Image(systemName: "photo")
                            .foregroundStyle(Brand.textTertiary)
                    }
                    .scaledToFill()
                }
            }
            .frame(height: 112)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Brand.textTertiary)
        }
    }

    private var lockedThumbnail: some View {
        VStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 14)
                .fill(Brand.backgroundTop)
                .overlay(
                    Image(systemName: "lock.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Brand.textTertiary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Brand.divider, lineWidth: 1)
                )
                .frame(height: 112)
                .frame(maxWidth: .infinity)

            Text(partnerName)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Brand.textTertiary)
        }
    }
}
