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

    init(session: UserSession, service: CoupleProfileService = FirestoreCoupleProfileService()) {
        self.session = session
        self.service = service
    }

    deinit {
        myListener?.remove()
        partnerListener?.remove()
    }

    // MARK: - Lifecycle

    func startListening() {
        guard myListener == nil else { return }

        myListener = service.observeProfile(userId: session.userId) { [weak self] profile in
            Task { @MainActor [weak self] in
                if let profile { self?.myProfile = profile }
            }
        }

        guard session.isPaired else { return }

        partnerListener = service.observeProfile(userId: session.partnerId) { [weak self] profile in
            Task { @MainActor [weak self] in
                if let profile { self?.partnerProfile = profile }
            }
        }
    }

    func stopListening() {
        myListener?.remove(); myListener = nil
        partnerListener?.remove(); partnerListener = nil
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
