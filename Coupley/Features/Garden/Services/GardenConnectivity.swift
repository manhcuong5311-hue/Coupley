//
//  GardenConnectivity.swift
//  Coupley
//
//  An NWPathMonitor wrapper. Consent transactions fail fast with
//  GardenError.offline when `isOnline` is false, instead of letting the
//  Firestore SDK retry for many seconds (spec I4).
//
//  It reports online until the monitor's first answer, so a slow first
//  path update never blocks an action that would have worked.
//

import Foundation
import Network

final class GardenConnectivity: GardenConnectivityMonitoring {

    private(set) var isOnline = true

    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.isOnline = online }
        }
        monitor.start(queue: DispatchQueue(label: "com.coupley.garden.connectivity", qos: .utility))
    }

    deinit {
        monitor.cancel()
    }
}

/// A build without the garden (GardenFeature.isEnabled false) reads no
/// connectivity, so it runs no path monitor: this one answers online.
final class GardenNoConnectivityMonitor: GardenConnectivityMonitoring {
    let isOnline = true
}
