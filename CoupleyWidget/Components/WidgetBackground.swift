//
//  WidgetBackground.swift
//  CoupleyWidget
//
//  Two-mode background system:
//   - When a couple photo file exists in the App Group container, render
//     it edge-to-edge with a dark vertical scrim for legibility plus a
//     subtle top blur so the foreground type sits on a calm canvas.
//   - Otherwise fall back to the romantic gradient with two ambient
//     blurred orbs that carry the brand's "warm + soft" feel.
//

import SwiftUI

struct WidgetBackground: View {

    let snapshot: WidgetSnapshot

    private var photoURL: URL? {
        WidgetSnapshotStore.resolvePhotoURL(filename: snapshot.couplePhotoFilename)
    }

    var body: some View {
        ZStack {
            if let photoURL, let uiImage = UIImage(contentsOfFile: photoURL.path) {
                photoBackground(uiImage: uiImage)
            } else {
                gradientBackground
            }
        }
    }

    // MARK: - Photo

    private func photoBackground(uiImage: UIImage) -> some View {
        GeometryReader { geo in
            ZStack {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()

                LinearGradient.widgetPhotoScrim

                // Subtle warm wash to keep the brand feeling even on cool photos.
                LinearGradient(
                    colors: [
                        WidgetPalette.gradientMid.opacity(0.18),
                        Color.clear,
                        Color.black.opacity(0.12)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    // MARK: - Gradient

    private var gradientBackground: some View {
        ZStack {
            LinearGradient.widgetRomantic

            // Soft ambient orbs — clipped by the parent container shape.
            Circle()
                .fill(Color.white.opacity(0.22))
                .frame(width: 220, height: 220)
                .blur(radius: 60)
                .offset(x: -60, y: -90)

            Circle()
                .fill(WidgetPalette.gradientBottom.opacity(0.35))
                .frame(width: 260, height: 260)
                .blur(radius: 70)
                .offset(x: 90, y: 110)

            // Faint gloss across the top edge — sells the premium feel
            // without tipping into skeuomorphism.
            LinearGradient(
                colors: [Color.white.opacity(0.18), Color.clear],
                startPoint: .top,
                endPoint: .center
            )
        }
    }
}
