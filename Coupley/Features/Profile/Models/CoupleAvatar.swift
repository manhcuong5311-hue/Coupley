//
//  CoupleAvatar.swift
//  Coupley
//

import Foundation
import SwiftUI

// MARK: - Avatar Option

/// Identifier for a user avatar — either one of the 6 bundled assets or a
/// user-uploaded photo encoded as base64 in the user's Firestore document.
enum AvatarOption: Equatable, Hashable, Codable {
    case asset(String)
    case custom(String)   // base64-encoded JPEG

    // MARK: - Codable (custom so the format is stable)

    private enum CodingKeys: String, CodingKey { case type, value }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .asset(let name):
            try c.encode("asset", forKey: .type)
            try c.encode(name,    forKey: .value)
        case .custom(let b64):
            try c.encode("custom", forKey: .type)
            try c.encode(b64,      forKey: .value)
        }
    }

    init(from decoder: Decoder) throws {
        let c    = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        let val  = try c.decode(String.self, forKey: .value)
        switch type {
        case "asset":  self = .asset(val)
        case "custom": self = .custom(val)
        default:       self = .placeholderPartner
        }
    }

    static let men1   = AvatarOption.asset("Men1")
    static let men2   = AvatarOption.asset("Men2")
    static let men3   = AvatarOption.asset("Men3")
    static let woman1 = AvatarOption.asset("Woman1")
    static let woman2 = AvatarOption.asset("woman2")
    static let woman3 = AvatarOption.asset("Women3")

    static let defaultsMen:    [AvatarOption] = [.men1, .men2, .men3]
    static let defaultsWomen:  [AvatarOption] = [.woman1, .woman2, .woman3]
    static let allDefaults:    [AvatarOption] = defaultsMen + defaultsWomen

    /// Default fallback when nothing is stored yet.
    static let placeholderSelf:    AvatarOption = .woman1
    static let placeholderPartner: AvatarOption = .men1

    // MARK: - Persistence Encoding

    /// String form stored in Firestore: "asset:Men1" or "custom".
    /// Custom photo bytes live in a separate `avatarPhoto` field so the
    /// avatarId stays small and quick to read.
    var firestoreId: String {
        switch self {
        case .asset(let name): return "asset:\(name)"
        case .custom:          return "custom"
        }
    }

    init?(firestoreId: String, customBase64: String?) {
        if firestoreId == "custom", let b64 = customBase64, !b64.isEmpty {
            self = .custom(b64)
            return
        }
        if firestoreId.hasPrefix("asset:") {
            self = .asset(String(firestoreId.dropFirst("asset:".count)))
            return
        }
        return nil
    }
}

// MARK: - SwiftUI Image Helper

extension AvatarOption {
    /// Renders the avatar as a SwiftUI `Image`. Falls back to a placeholder
    /// system symbol if a custom photo can't be decoded.
    @ViewBuilder
    func image() -> some View {
        switch self {
        case .asset(let name):
            Image(name)
                .resizable()
                .scaledToFill()
        case .custom(let b64):
            if let data = Data(base64Encoded: b64),
               let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Brand.textTertiary)
            }
        }
    }
}
