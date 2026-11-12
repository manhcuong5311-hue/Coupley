//
//  CachedRemoteImage.swift
//  Coupley
//
//  A drop-in replacement for `AsyncImage` that actually keeps what it
//  downloads.
//
//  `AsyncImage` re-fetches every time its view is recreated — which, inside a
//  SwiftUI `ScrollView`, is every time the row scrolls back into range. On the
//  daily photo card that meant the same two photos being pulled from Firebase
//  Storage repeatedly for as long as the couple stayed on the Home tab: the
//  user's mobile data, and billed egress, for bytes the phone already had.
//
//  Two layers:
//    – an in-memory `NSCache` of decoded images, so scrolling costs nothing
//      and the system can evict under pressure;
//    – `URLCache` on disk, so the bytes survive relaunches.
//
//  Firebase download URLs carry a token but are stable per object, so they
//  are a sound cache key.
//

import SwiftUI
import UIKit

// MARK: - Store

final class RemoteImageStore {

    static let shared = RemoteImageStore()

    private let memory = NSCache<NSString, UIImage>()
    private let session: URLSession

    private init() {
        // Decoded images are large; cap by cost rather than count.
        memory.totalCostLimit = 64 * 1024 * 1024

        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(
            memoryCapacity: 16 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024,
            directory: nil
        )
        // Photos at a given URL never change, so a cached copy is always
        // good: ask the network only when there isn't one.
        config.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: config)
    }

    func cached(_ url: URL) -> UIImage? {
        memory.object(forKey: url.absoluteString as NSString)
    }

    func image(for url: URL) async -> UIImage? {
        if let hit = cached(url) { return hit }
        do {
            let (data, _) = try await session.data(from: url)
            guard let image = UIImage(data: data) else { return nil }
            memory.setObject(image, forKey: url.absoluteString as NSString,
                             cost: data.count)
            return image
        } catch {
            return nil
        }
    }
}

// MARK: - View

struct CachedRemoteImage<Placeholder: View, Failure: View>: View {

    let url: URL?
    @ViewBuilder var placeholder: () -> Placeholder
    @ViewBuilder var failure: () -> Failure

    @State private var image: UIImage?
    @State private var didFail = false

    init(
        url: URL?,
        @ViewBuilder placeholder: @escaping () -> Placeholder,
        @ViewBuilder failure: @escaping () -> Failure
    ) {
        self.url = url
        self.placeholder = placeholder
        self.failure = failure
        // Seed synchronously from memory so a cached photo never flashes a
        // spinner on the way back into view.
        if let url {
            _image = State(initialValue: RemoteImageStore.shared.cached(url))
        }
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable()
            } else if didFail {
                failure()
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard image == nil, let url else { return }
            let loaded = await RemoteImageStore.shared.image(for: url)
            await MainActor.run {
                if let loaded { image = loaded } else { didFail = true }
            }
        }
    }
}
