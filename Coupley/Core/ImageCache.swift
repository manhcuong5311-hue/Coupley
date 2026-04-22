//
//  ImageCache.swift
//  Coupley
//

import UIKit
import SwiftUI
import CryptoKit

// MARK: - Image Cache

/// Two-tier cache: NSCache (in-memory, auto-evicted) + JPEG files on disk
/// (survives app kills). Thread-safe for concurrent reads; disk writes are
/// dispatched to a background queue.
final class ImageCache {

    static let shared = ImageCache()

    private let memory = NSCache<NSString, UIImage>()
    private let diskURL: URL
    private let ioQueue = DispatchQueue(label: "com.coupley.imagecache.io", qos: .utility)

    private init() {
        memory.countLimit = 60
        memory.totalCostLimit = 40 * 1024 * 1024 // 40 MB

        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        diskURL = caches.appendingPathComponent("com.coupley.imagecache", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskURL, withIntermediateDirectories: true)
    }

    // MARK: - Public API

    func image(for url: URL) -> UIImage? {
        let key = cacheKey(for: url) as NSString

        if let cached = memory.object(forKey: key) {
            return cached
        }

        let fileURL = diskURL.appendingPathComponent(String(key))
        guard let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else { return nil }

        memory.setObject(image, forKey: key, cost: data.count)
        return image
    }

    func store(_ image: UIImage, for url: URL) {
        let key = cacheKey(for: url) as NSString
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        memory.setObject(image, forKey: key, cost: data.count)
        let fileURL = diskURL.appendingPathComponent(String(key))
        ioQueue.async { try? data.write(to: fileURL) }
    }

    // MARK: - Private

    private func cacheKey(for url: URL) -> String {
        let hash = SHA256.hash(data: Data(url.absoluteString.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - CachedAsyncImage

/// Drop-in replacement for AsyncImage that persists downloaded images to disk
/// so they are available immediately after the app is killed and relaunched.
///
/// Two reliability improvements over a naive `.task`-on-content approach:
///   1. The initial phase is pre-populated synchronously from the in-memory
///      cache so there is zero flash when the image is already hot.
///   2. The load task is anchored to a `Color.clear` background that always
///      has layout size, preventing SwiftUI from skipping the task when the
///      content closure returns EmptyView during the loading state.
struct CachedAsyncImage<Content: View>: View {

    let url: URL?
    @ViewBuilder let content: (AsyncImagePhase) -> Content

    @State private var phase: AsyncImagePhase

    init(url: URL?, @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        self.url = url
        self.content = content
        // Pre-populate from in-memory cache (synchronous, no async flash)
        if let url, let cached = ImageCache.shared.image(for: url) {
            _phase = State(initialValue: .success(Image(uiImage: cached)))
        } else {
            _phase = State(initialValue: .empty)
        }
    }

    var body: some View {
        content(phase)
            .background(
                // Anchor the task here so it runs even when content is EmptyView
                Color.clear
                    .task(id: url?.absoluteString) {
                        await load()
                    }
            )
    }

    // MARK: - Private

    private func load() async {
        guard let url else { return }
        if case .success = phase { return }   // already loaded from init

        if let cached = ImageCache.shared.image(for: url) {
            phase = .success(Image(uiImage: cached))
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let uiImage = UIImage(data: data) else {
                phase = .failure(URLError(.cannotDecodeContentData))
                return
            }
            ImageCache.shared.store(uiImage, for: url)
            phase = .success(Image(uiImage: uiImage))
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failure(error)
        }
    }
}
