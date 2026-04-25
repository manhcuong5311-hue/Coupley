//
//  CouplePersonProfileViewModel.swift
//  Coupley
//

import Foundation
import FirebaseFirestore
import UIKit
import Combine

// MARK: - View Model

@MainActor
final class CouplePersonProfileViewModel: ObservableObject {

    @Published var myProfile: CouplePersonProfile = .placeholderSelf
    @Published var partnerProfile: CouplePersonProfile = .placeholderPartner
    @Published var isSaving: Bool = false

    private let session: UserSession
    private let service: CoupleProfileService

    nonisolated(unsafe) private var myListener: ListenerRegistration?
    nonisolated(unsafe) private var partnerListener: ListenerRegistration?

    init(session: UserSession, service: CoupleProfileService? = nil) {
        self.session = session
        self.service = service ?? FirestoreCoupleProfileService()
    }

    deinit {
        myListener?.remove()
        partnerListener?.remove()
    }

    // MARK: - Lifecycle

    func startListening() {
        guard myListener == nil else { return }

        loadProfileCache()

        myListener = service.observeProfile(userId: session.userId) { [weak self] profile in
            Task { @MainActor [weak self] in
                guard let self, let profile else { return }
                self.myProfile = profile
                self.saveProfile(profile, key: self.myCacheKey)
            }
        }

        guard session.isPaired else { return }

        partnerListener = service.observeProfile(userId: session.partnerId) { [weak self] profile in
            Task { @MainActor [weak self] in
                guard let self, let profile else { return }
                self.partnerProfile = profile
                self.saveProfile(profile, key: self.partnerCacheKey)
            }
        }
    }

    func stopListening() {
        myListener?.remove(); myListener = nil
        partnerListener?.remove(); partnerListener = nil
    }

    // MARK: - Profile Cache

    private var myCacheKey: String { "coupley.profile.me.\(session.userId)" }
    private var partnerCacheKey: String { "coupley.profile.partner.\(session.partnerId)" }

    private func loadProfileCache() {
        let ud = UserDefaults.standard
        if let data = ud.data(forKey: myCacheKey),
           let profile = try? JSONDecoder().decode(CouplePersonProfile.self, from: data) {
            myProfile = profile
        }
        if session.isPaired,
           let data = ud.data(forKey: partnerCacheKey),
           let profile = try? JSONDecoder().decode(CouplePersonProfile.self, from: data) {
            partnerProfile = profile
        }
    }

    private func saveProfile(_ profile: CouplePersonProfile, key: String) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    // MARK: - Save

    func setMyAvatar(_ avatar: AvatarOption) {
        myProfile.avatar = avatar
        Task {
            isSaving = true
            defer { isSaving = false }
            do {
                try await service.saveAvatar(userId: session.userId, avatar: avatar)
            } catch {
                print("[CoupleProfileVM] Save failed: \(error.localizedDescription)")
            }
        }
    }

    /// Encodes a UIImage to a compressed base64 JPEG suitable for Firestore.
    /// Documents are capped at ~1 MB so we resize aggressively first.
    func setMyCustomPhoto(_ image: UIImage) {
        let resized = image.resizedSquare(maxSide: 320)
        guard let data = resized.jpegData(compressionQuality: 0.7) else { return }
        let b64 = data.base64EncodedString()
        setMyAvatar(.custom(b64))
    }
}

// MARK: - UIImage helper

private extension UIImage {
    func resizedSquare(maxSide: CGFloat) -> UIImage {
        let side = min(size.width, size.height)
        let cropRect = CGRect(
            x: (size.width  - side) / 2,
            y: (size.height - side) / 2,
            width: side, height: side
        )
        let cropped: UIImage = {
            guard let cg = cgImage?.cropping(to: cropRect) else { return self }
            return UIImage(cgImage: cg, scale: scale, orientation: imageOrientation)
        }()

        let target = CGSize(width: maxSide, height: maxSide)
        let renderer = UIGraphicsImageRenderer(size: target)
        return renderer.image { _ in
            cropped.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
