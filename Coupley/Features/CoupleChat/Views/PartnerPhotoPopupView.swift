//
//  PartnerPhotoPopupView.swift
//  Coupley
//
//  Full-screen overlay shown when a partner sends a photo.
//  Auto-dismisses after 5 minutes or when the user taps the close button.
//

import SwiftUI

struct PartnerPhotoPopupView: View {

    let imageURL: String
    let onDismiss: () -> Void

    @State private var loadedImage: UIImage? = nil
    @State private var isLoading = true
    @State private var dismissTask: Task<Void, Never>? = nil

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("From your partner")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                        Text("Sent you a photo")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    Button(action: dismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding(.horizontal, 24)

                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white.opacity(0.1))
                        .frame(maxWidth: .infinity)
                        .frame(height: 360)

                    if let img = loadedImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .frame(maxWidth: .infinity)
                            .frame(maxHeight: 360)
                    } else if isLoading {
                        ProgressView()
                            .tint(.white)
                            .controlSize(.large)
                    } else {
                        Image(systemName: "photo.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                .padding(.horizontal, 24)

                Button(action: dismiss) {
                    Text("Close")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(.white.opacity(0.2))
                                .overlay(RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(.white.opacity(0.3), lineWidth: 1))
                        )
                }
                .padding(.horizontal, 24)
            }
        }
        .task {
            await loadImage()
            startAutoDismiss()
        }
        .onDisappear {
            dismissTask?.cancel()
        }
    }

    private func dismiss() {
        dismissTask?.cancel()
        onDismiss()
    }

    private func startAutoDismiss() {
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000_000) // 5 minutes
            guard !Task.isCancelled else { return }
            await MainActor.run { onDismiss() }
        }
    }

    private func loadImage() async {
        guard let url = URL(string: imageURL) else {
            isLoading = false
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let img = UIImage(data: data)
            await MainActor.run {
                loadedImage = img
                isLoading = false
            }
        } catch {
            await MainActor.run { isLoading = false }
        }
    }
}
