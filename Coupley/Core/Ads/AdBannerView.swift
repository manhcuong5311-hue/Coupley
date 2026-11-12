//
// AdBannerView.swift
// Coupley
//
// Anchored *adaptive* AdMob banner. Renders nothing for ad-free users or
// while the keyboard is up, and collapses to 0 height until an ad has
// actually loaded.
//
// Why adaptive rather than the fixed 320×50 this used to request: on a modern
// iPhone (390–430pt wide) a 320pt banner leaves a dead margin on both sides
// and competes for a shrinking pool of fixed-size creatives. An anchored
// adaptive banner fills the width and asks Google for a height tuned to the
// device (50–90pt, never more than 15% of screen height), which both fills
// better and prices better.
//
// Note the API choice: `currentOrientationAnchoredAdaptiveBanner(width:)` is
// deprecated in the SDK this project pins (12.11); `largeAnchoredAdaptiveBanner`
// is its stated replacement and picks portrait/landscape itself.
//

import SwiftUI
import UIKit
import GoogleMobileAds

struct AdBannerView: View {

    @ObservedObject private var ads = AdsManager.shared

    var body: some View {
        if ads.adsEnabled && ads.isReady && !ads.isKeyboardVisible, ads.bannerWidth > 0 {
            let size = AdsConfig.adaptiveBannerSize(width: ads.bannerWidth)

            // The banner view keeps its full frame at all times — the SDK
            // rejects a load from a zero-height view ("Invalid ad width or
            // height"). Only the outer slot collapses until an ad loads.
            BannerRepresentable(adSize: size)
                .frame(width: size.size.width, height: size.size.height)
                .frame(height: ads.bannerHeight > 0 ? size.size.height : 0, alignment: .top)
                .clipped()
                .frame(maxWidth: .infinity)
                .padding(.bottom, ads.bannerHeight > 0 ? AdsConfig.bannerSpacing : 0)
        }
    }
}

private struct BannerRepresentable: UIViewRepresentable {

    let adSize: AdSize

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: adSize)
        banner.adUnitID = AdsConfig.bannerUnitID
        banner.delegate = context.coordinator
        context.coordinator.loadedWidth = adSize.size.width
        banner.load(Request())
        return banner
    }

    func updateUIView(_ banner: BannerView, context: Context) {
        // Rotation (or any width change) invalidates the creative that is on
        // screen: it was sized for the old width. Re-request at the new size.
        guard abs(context.coordinator.loadedWidth - adSize.size.width) > 0.5 else { return }
        context.coordinator.loadedWidth = adSize.size.width
        banner.adSize = adSize
        banner.load(Request())

        // Collapsing the slot publishes to AdsManager, and this runs inside a
        // SwiftUI update pass — doing it synchronously is the "Modifying state
        // during view update" warning. Hand it to the next runloop turn.
        Task { @MainActor in AdsManager.shared.bannerDidFail() }
    }

    final class Coordinator: NSObject, BannerViewDelegate {

        /// Width the currently requested creative was sized for.
        var loadedWidth: CGFloat = 0

        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            AdsManager.shared.bannerDidLoad(height: bannerView.adSize.size.height)
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            print("[AdsManager] Banner load failed: \(error.localizedDescription)")
            AdsManager.shared.bannerDidFail()
        }
    }
}

// MARK: - Tab content inset

extension View {
    /// Pins the banner to the bottom of a tab's content, right above the tab
    /// bar, and shrinks the content so nothing hides behind the ad.
    func adBannerInset() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            AdBannerView()
        }
    }
}
