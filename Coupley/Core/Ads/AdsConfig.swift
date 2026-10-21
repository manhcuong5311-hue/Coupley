//
// AdsConfig.swift
// Coupley
//
// AdMob unit IDs + frequency caps. The only ads file that changes per app.
// Ads are shown only while the user (or their partner) has NOT bought
// "Remove Ads" and never subscribed to the old Premium.
//

import CoreGraphics
import Foundation

enum AdsConfig {

    // MARK: - Ad unit IDs
    // AdMob app ID lives in Coupley-Info.plist (GADApplicationIdentifier):
    //   ca-app-pub-5982140566133654~6205449640  (Couple Mood Sync: CoupleyAI)
    // DEBUG builds always use Google's test units so we never click our own live ads.

    #if DEBUG
    static let bannerUnitID       = "ca-app-pub-3940256099942544/2934735716"   // Google test banner
    static let interstitialUnitID = "ca-app-pub-3940256099942544/4411468910"   // Google test interstitial
    #else
    static let bannerUnitID       = releaseBannerUnitID
    static let interstitialUnitID = releaseInterstitialUnitID
    #endif

    static let releaseBannerUnitID       = "ca-app-pub-5982140566133654/9567864172"   // Coupley Banner - above tab bar
    static let releaseInterstitialUnitID = "ca-app-pub-5982140566133654/1292868460"   // Coupley Interstitial - after actions

    // MARK: - Frequency caps

    /// An interstitial may only follow every Nth qualifying action
    /// (Coupley: a mood check-in, a saved memory, a finished quiz, an AI answer).
    static let interstitialEveryNActions = 3

    /// Minimum gap between two interstitials.
    static let minSecondsBetweenInterstitials: TimeInterval = 180

    /// Short pause after the qualifying action, so its feedback (toast, sheet dismissal)
    /// is seen before the ad covers the screen.
    static let interstitialPresentationDelay: TimeInterval = 1.0

    /// Pause before the consent form / ATT prompt once the main UI is on screen.
    static let startupDelay: TimeInterval = 1.5

    // MARK: - Layout

    /// Gap between the banner and the tab bar.
    static let bannerSpacing: CGFloat = 4
}
