//
//  PartnerConnection.swift
//  Coupley
//
//  Connection-level metadata stored on couples/{coupleId}. The coupleId
//  doubles as the connectionId — every pairing produces a new coupleId,
//  so data from a previous relationship can never leak into a new one.
//

import Foundation
import FirebaseFirestore

// MARK: - Connection Status

enum ConnectionStatus: String {
    case active       = "active"
    case disconnected = "disconnected"
}

// MARK: - Firestore field names

enum ConnectionField {
    // On couples/{coupleId}
    static let status             = "status"
    static let disconnectedAt     = "disconnectedAt"
    static let disconnectedBy     = "disconnectedBy"
    static let userIds            = "userIds"

    // On users/{userId}
    static let coupleId                = "coupleId"
    static let partnerId               = "partnerId"
    static let lastCoupleId            = "lastCoupleId"
    static let lastPartnerId           = "lastPartnerId"
    static let pendingDisconnectNotice = "pendingDisconnectNotice"
    static let lastPartnerName         = "lastPartnerName"
}

// MARK: - Connection Record (read-side)

/// Lightweight projection of the couple document used by the disconnect /
/// cleanup screens. Mirrors fields rather than reusing `CoupleDocument`
/// so we don't have to touch the pairing decoder.
struct PartnerConnection: Equatable {
    let connectionId: String
    let userIds: [String]
    let status: ConnectionStatus
    let disconnectedAt: Date?
    let disconnectedBy: String?

    var isActive: Bool { status == .active }

    init?(connectionId: String, data: [String: Any]) {
        guard !connectionId.isEmpty else { return nil }
        self.connectionId    = connectionId
        self.userIds         = (data[ConnectionField.userIds] as? [String]) ?? []
        self.status          = (data[ConnectionField.status] as? String)
            .flatMap(ConnectionStatus.init(rawValue:)) ?? .active
        self.disconnectedAt  = (data[ConnectionField.disconnectedAt] as? Timestamp)?.dateValue()
        self.disconnectedBy  = data[ConnectionField.disconnectedBy] as? String
    }
}
