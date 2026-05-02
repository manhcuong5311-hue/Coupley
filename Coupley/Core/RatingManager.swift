//
//  RatingManager.swift
//  Coupley
//
//  Coordinates App Store review prompts at three meaningful moments:
//   1. First mood check-in ever
//   2. First partner connection
//   3. One month after install
//
//  StoreKit already caps prompts to 3 per 365 days, but we also enforce
//  our own cap so we never ask more than 3 times per calendar year even
//  on the simulator (where StoreKit limits are not applied).
//

import StoreKit
import UIKit

@MainActor
final class RatingManager {

    static let shared = RatingManager()

    private enum Keys {
        static let installDate            = "rating.installDate"
        static let firstMoodDone          = "rating.firstMoodDone"
        static let firstPairingDone       = "rating.firstPairingDone"
        static let oneMonthMilestoneDone  = "rating.oneMonthMilestoneDone"
        static let countKey               = "rating.yearCount"
        static let yearKey                = "rating.year"
    }

    private init() {
        if UserDefaults.standard.object(forKey: Keys.installDate) == nil {
            UserDefaults.standard.set(Date(), forKey: Keys.installDate)
        }
    }

    // MARK: - Public triggers

    func recordFirstMoodCheckIn() {
        guard !UserDefaults.standard.bool(forKey: Keys.firstMoodDone) else { return }
        UserDefaults.standard.set(true, forKey: Keys.firstMoodDone)
        scheduleRequest()
    }

    func recordFirstPartnerConnection() {
        guard !UserDefaults.standard.bool(forKey: Keys.firstPairingDone) else { return }
        UserDefaults.standard.set(true, forKey: Keys.firstPairingDone)
        scheduleRequest()
    }

    func checkOneMonthMilestone() {
        guard !UserDefaults.standard.bool(forKey: Keys.oneMonthMilestoneDone) else { return }
        guard let install = UserDefaults.standard.object(forKey: Keys.installDate) as? Date else { return }
        let oneMonthAgo = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        guard install <= oneMonthAgo else { return }
        UserDefaults.standard.set(true, forKey: Keys.oneMonthMilestoneDone)
        scheduleRequest()
    }

    // MARK: - Private

    private var requestsThisYear: Int {
        let now = Calendar.current.component(.year, from: Date())
        guard UserDefaults.standard.integer(forKey: Keys.yearKey) == now else { return 0 }
        return UserDefaults.standard.integer(forKey: Keys.countKey)
    }

    private func scheduleRequest() {
        let year = Calendar.current.component(.year, from: Date())
        let count = requestsThisYear
        guard count < 3 else { return }

        // Reset counter when the year rolled over
        if UserDefaults.standard.integer(forKey: Keys.yearKey) != year {
            UserDefaults.standard.set(year, forKey: Keys.yearKey)
            UserDefaults.standard.set(0, forKey: Keys.countKey)
        }
        UserDefaults.standard.set(count + 1, forKey: Keys.countKey)

        Task { @MainActor in
            // Let the triggering interaction settle before the prompt appears.
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }) else { return }
            if #available(iOS 18.0, *) {
                AppStore.requestReview(in: scene)
            } else {
                SKStoreReviewController.requestReview(in: scene)
            }
        }
    }
}
