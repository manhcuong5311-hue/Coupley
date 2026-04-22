//
//  AvatarPickerSheet.swift
//  Coupley
//

import SwiftUI
import PhotosUI

// MARK: - Avatar Picker Sheet

struct AvatarPickerSheet: View {

    @ObservedObject var viewModel: CouplePersonProfileViewModel
    @EnvironmentObject private var premiumStore: PremiumStore
    @Environment(\.dismiss) private var dismiss

    @State private var photoItem: PhotosPickerItem?
    @State private var isLoadingPhoto = false
    @State private var showPaywall = false

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    Text("Choose your avatar")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)
                        .padding(.horizontal, 4)

                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(AvatarOption.allDefaults, id: \.self) { option in
                            avatarTile(option)
                        }
                    }

                    customPhotoButton
                }
                .padding(20)
            }
            .background(Brand.bgGradient.ignoresSafeArea())
            .navigationTitle("Your Avatar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Brand.accentStart)
                }
            }
            .onChange(of: photoItem) { _, newItem in
                guard let newItem else { return }
                Task { await loadCustomPhoto(newItem) }
            }
            .sheet(isPresented: $showPaywall) {
                NavigationStack {
                    PremiumPaywallView()
                }
                .environmentObject(premiumStore)
                .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Custom Photo Button

    @ViewBuilder
    private var customPhotoButton: some View {
        if premiumStore.hasAccess(to: .customAvatar) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                uploadPhotoLabel
            }
            .disabled(isLoadingPhoto)
        } else {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showPaywall = true
            } label: {
                ZStack(alignment: .topTrailing) {
                    uploadPhotoLabel
                        .opacity(0.7)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Circle().fill(Color(red: 0.95, green: 0.50, blue: 0.20)))
                        .offset(x: 8, y: -8)
                }
            }
        }
    }

    private var uploadPhotoLabel: some View {
        HStack(spacing: 10) {
            if isLoadingPhoto {
                ProgressView().tint(.white).controlSize(.small)
            } else {
                Image(systemName: "camera.fill")
                    .font(.system(size: 14, weight: .semibold))
            }
            Text(isLoadingPhoto ? "Uploading…" : "Upload your own photo")
                .font(.system(size: 15, weight: .semibold, design: .rounded))

            if !premiumStore.hasAccess(to: .customAvatar) {
                Spacer()
                Text("Premium")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.25)))
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        .background(Brand.accentGradient)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: Brand.accentStart.opacity(0.30), radius: 12, y: 4)
    }

    // MARK: - Tile

    private func avatarTile(_ option: AvatarOption) -> some View {
        let isSelected = viewModel.myProfile.avatar == option
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            viewModel.setMyAvatar(option)
        } label: {
            ZStack {
                Circle()
                    .fill(Brand.surfaceLight)
                    .overlay(
                        Circle().strokeBorder(
                            isSelected ? Brand.accentStart : Brand.divider,
                            lineWidth: isSelected ? 3 : 1
                        )
                    )

                option.image()
                    .clipShape(Circle())
                    .padding(4)

                if isSelected {
                    Circle()
                        .fill(Brand.accentStart)
                        .frame(width: 22, height: 22)
                        .overlay(
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        )
                        .offset(x: 28, y: 28)
                }
            }
            .frame(height: 90)
        }
        .buttonStyle(BouncyButtonStyle(scale: 0.95))
    }

    // MARK: - Photo Loader

    private func loadCustomPhoto(_ item: PhotosPickerItem) async {
        isLoadingPhoto = true
        defer { isLoadingPhoto = false }
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let ui = UIImage(data: data) {
                viewModel.setMyCustomPhoto(ui)
            }
        } catch {
            print("[AvatarPicker] Failed to load photo: \(error.localizedDescription)")
        }
        photoItem = nil
    }
}

#Preview {
    AvatarPickerSheet(viewModel: CouplePersonProfileViewModel(session: .demo))
        .environmentObject(PremiumStore(service: MockPremiumService()))
}
