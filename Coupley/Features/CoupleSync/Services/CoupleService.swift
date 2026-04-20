//
//  CoupleService.swift
//  Coupley
//
//  Created by Sam Manh Cuong on 1/4/26.
//

import Foundation
import FirebaseFirestore

// MARK: - Couple Service Protocol

protocol CoupleService {
    func fetchCouple(coupleId: String) async throws -> CoupleDocument
    func getPartnerId(coupleId: String, currentUserId: String) async throws -> String
}

// MARK: - Firestore Couple Service

final class FirestoreCoupleService: CoupleService {

    private let db = Firestore.firestore()

    func fetchCouple(coupleId: String) async throws -> CoupleDocument {
        let snapshot = try await db
            .collection(FirestorePath.couples)
            .document(coupleId)
            .getDocument()

        guard let couple = try? snapshot.data(as: CoupleDocument.self) else {
            throw CoupleError.coupleNotFound
        }

        return couple
    }

    func getPartnerId(coupleId: String, currentUserId: String) async throws -> String {
        let couple = try await fetchCouple(coupleId: coupleId)
        guard let partnerId = couple.partnerId(for: currentUserId) else {
            throw CoupleError.partnerNotFound
        }
        return partnerId
    }
}

// MARK: - Mock Couple Service

final class MockCoupleService: CoupleService {

    func fetchCouple(coupleId: String) async throws -> CoupleDocument {
        try await Task.sleep(nanoseconds: 200_000_000)
        return CoupleDocument(userIds: [
            UserSession.demo.userId,
            UserSession.demo.partnerId
        ])
    }

    func getPartnerId(coupleId: String, currentUserId: String) async throws -> String {
        let couple = try await fetchCouple(coupleId: coupleId)
        guard let partnerId = couple.partnerId(for: currentUserId) else {
            throw CoupleError.partnerNotFound
        }
        return partnerId
    }
}

// MARK: - Couple Errors

enum CoupleError: LocalizedError {
    case coupleNotFound
    case partnerNotFound

    var errorDescription: String? {
        switch self {
        case .coupleNotFound: return "Couple not found"
        case .partnerNotFound: return "Partner not found"
        }
    }
}
