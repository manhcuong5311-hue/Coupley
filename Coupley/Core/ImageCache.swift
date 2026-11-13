//
//  ImageCache.swift
//  Coupley
//

import Foundation
import UIKit
import SwiftUI
import CryptoKit
import ImageIO

// MARK: - Image Cache

/// Two-tier cache: NSCache of decoded images (in-memory, auto-evicted) +
/// image files on disk (survive app kills).
///
/// - The memory tier is charged what an image really costs once decoded
///   (pixel width × height × 4 bytes), not its compressed size, so the limit
///   means what it says.
/// - Disk reads and writes, JPEG encoding and the decoding done by
///   `diskImage` / `storeDownloaded` run off the main thread (only the legacy
///   synchronous `image(for:)` reads on the caller's thread). Disk access
///   goes through one concurrent queue on which writes are barriers, so a
///   read queued after a write always sees the file, and files are written
///   atomically, so a read never sees half of one.
/// - Asking for `maxPixelSize` decodes a downsampled copy (ImageIO), cached
///   in memory under its own key; the disk keeps the original bytes once.
final class ImageCache {

    static let shared = ImageCache()

    private let memory = NSCache<NSString, UIImage>()
    private let diskURL: URL
    private let diskQueue = DispatchQueue(label: "com.coupley.imagecache.disk",
                                          qos: .userInitiated,
                                          attributes: .concurrent)

    private init() {
        memory.countLimit = 100
        memory.totalCostLimit = 64 * 1024 * 1024 // 64 MB of decoded pixels

        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        diskURL = caches.appendingPathComponent("com.coupley.imagecache", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskURL, withIntermediateDirectories: true)
    }

    // MARK: - Lookup

    /// Memory first, then disk, synchronously on the caller's thread. Kept for
    /// existing callers; views use `memoryImage` + `diskImage` instead.
    func image(for url: URL) -> UIImage? {
        if let cached = memoryImage(for: url) {
            return cached
        }
        guard let data = try? Data(contentsOf: fileURL(for: url)),
              let image = UIImage(data: data) else { return nil }
        remember(image, forKey: Self.memoryKey(for: url, maxPixelSize: nil))
        return image
    }

    /// In-memory only; never touches the disk, so it is cheap enough for a
    /// view's init. A downsampled request is also answered by the full-size
    /// image when that is already in memory.
    func memoryImage(for url: URL, maxPixelSize: CGFloat? = nil) -> UIImage? {
        if let exact = memory.object(forKey: Self.memoryKey(for: url, maxPixelSize: maxPixelSize) as NSString) {
            return exact
        }
        guard maxPixelSize != nil else { return nil }
        return memory.object(forKey: Self.memoryKey(for: url, maxPixelSize: nil) as NSString)
    }

    /// Reads and decodes the stored file off the main thread (downsampled
    /// when `maxPixelSize` is set), then keeps the result in memory.
    func diskImage(for url: URL, maxPixelSize: CGFloat? = nil) async -> UIImage? {
        let file = fileURL(for: url)
        let queue = diskQueue
        let decoded: UIImage? = await withCheckedContinuation { continuation in
            queue.async {
                guard let data = try? Data(contentsOf: file) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: Self.decodedImage(data: data, maxPixelSize: maxPixelSize))
            }
        }
        guard let decoded else { return nil }
        remember(decoded, forKey: Self.memoryKey(for: url, maxPixelSize: maxPixelSize))
        return decoded
    }

    // MARK: - Store

    /// Keeps `image` in memory and writes it to disk as JPEG. The encode
    /// happens off the main thread.
    func store(_ image: UIImage, for url: URL) {
        remember(image, forKey: Self.memoryKey(for: url, maxPixelSize: nil))
        let file = fileURL(for: url)
        diskQueue.async(flags: .barrier) {
            guard let data = image.jpegData(compressionQuality: 0.85) else { return }
            try? data.write(to: file, options: .atomic)
        }
    }

    /// Writes already-encoded image bytes to disk exactly as they are (no
    /// re-encode) and keeps the image in memory. Use it with the bytes that
    /// were just uploaded or downloaded.
    func store(data: Data, for url: URL) {
        guard let image = UIImage(data: data) else { return }
        remember(image, forKey: Self.memoryKey(for: url, maxPixelSize: nil))
        let file = fileURL(for: url)
        diskQueue.async(flags: .barrier) {
            try? data.write(to: file, options: .atomic)
        }
    }

    /// Freshly downloaded bytes: decoded off the main thread (downsampled
    /// when asked), written to disk as-is only if they really are an image,
    /// and kept in memory. Returns nil when the bytes are not an image.
    func storeDownloaded(_ data: Data, for url: URL, maxPixelSize: CGFloat? = nil) async -> UIImage? {
        let file = fileURL(for: url)
        let queue = diskQueue
        let decoded: UIImage? = await withCheckedContinuation { continuation in
            queue.async {
                let image = Self.decodedImage(data: data, maxPixelSize: maxPixelSize)
                if image != nil {
                    queue.async(flags: .barrier) {
                        try? data.write(to: file, options: .atomic)
                    }
                }
                continuation.resume(returning: image)
            }
        }
        guard let decoded else { return nil }
        remember(decoded, forKey: Self.memoryKey(for: url, maxPixelSize: maxPixelSize))
        return decoded
    }

    // MARK: - Decoding

    /// A copy of the image in `data` whose longest side is at most
    /// `maxPixelSize` PIXELS (not points), decoded now and rotated upright
    /// from its EXIF orientation. Never upscales. Safe on any thread.
    nonisolated static func downsampledImage(data: Data, maxPixelSize: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, Int(maxPixelSize.rounded(.up)))
        ] as [CFString: Any] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// Decodes `data` now, off the main thread. Without a `maxPixelSize` the
    /// image keeps its size up to a ceiling far above any screen, so a huge
    /// photo saved by an old version can't take hundreds of MB.
    nonisolated private static func decodedImage(data: Data, maxPixelSize: CGFloat?) -> UIImage? {
        downsampledImage(data: data, maxPixelSize: maxPixelSize ?? 2400)
    }

    // MARK: - Keys

    /// The memory-tier key: the URL's hash, plus the pixel size for a
    /// downsampled copy.
    nonisolated static func memoryKey(for url: URL, maxPixelSize: CGFloat?) -> String {
        let base = urlHash(url)
        guard let maxPixelSize else { return base }
        return "\(base)@\(max(1, Int(maxPixelSize.rounded(.up))))"
    }

    nonisolated private static func urlHash(_ url: URL) -> String {
        let hash = SHA256.hash(data: Data(url.absoluteString.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Private

    /// The disk file for a URL (named by the URL's hash, as before, so files
    /// cached by earlier versions stay valid).
    private func fileURL(for url: URL) -> URL {
        diskURL.appendingPathComponent(Self.urlHash(url))
    }

    private func remember(_ image: UIImage, forKey key: String) {
        memory.setObject(image, forKey: key as NSString, cost: Self.decodedCost(of: image))
    }

    /// Bytes the image takes once decoded: pixel width × height × 4.
    nonisolated private static func decodedCost(of image: UIImage) -> Int {
        if let cgImage = image.cgImage {
            return cgImage.width * cgImage.height * 4
        }
        let width = image.size.width * image.scale
        let height = image.size.height * image.scale
        return Int(width * height * 4)
    }
}

// MARK: - CachedAsyncImage

/// Drop-in replacement for AsyncImage that persists downloaded images to disk
/// so they are available immediately after the app is killed and relaunched.
///
/// - The initial phase is pre-populated synchronously from the IN-MEMORY
///   cache only, so there is zero flash when the image is already hot and a
///   parent's re-render never reads the disk on the main thread. The disk
///   read, the download and all decoding happen in the task.
/// - `maxPixelSize` (pixels: points × display scale) decodes a downsampled
///   copy, e.g. for an 84 pt thumbnail, instead of the whole photo.
/// - The phase remembers which URL and size it shows, so a new URL (a
///   replaced photo) never keeps displaying the previous picture.
/// - The load task is anchored to a `Color.clear` background that always
///   has layout size, preventing SwiftUI from skipping the task when the
///   content closure returns EmptyView during the loading state.
struct CachedAsyncImage<Content: View>: View {

    let url: URL?
    let maxPixelSize: CGFloat?
    @ViewBuilder let content: (AsyncImagePhase) -> Content

    @State private var phase: AsyncImagePhase
    /// The memory key of the picture `phase` belongs to.
    @State private var phaseKey: String?

    init(url: URL?,
         maxPixelSize: CGFloat? = nil,
         @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        self.url = url
        self.maxPixelSize = maxPixelSize
        self.content = content
        // Memory only: this runs on every parent re-render.
        if let url, let cached = ImageCache.shared.memoryImage(for: url, maxPixelSize: maxPixelSize) {
            _phase = State(initialValue: .success(Image(uiImage: cached)))
            _phaseKey = State(initialValue: ImageCache.memoryKey(for: url, maxPixelSize: maxPixelSize))
        } else {
            _phase = State(initialValue: .empty)
            _phaseKey = State(initialValue: nil)
        }
    }

    var body: some View {
        content(phase)
            .background(
                // Anchor the task here so it runs even when content is EmptyView
                Color.clear
                    .task(id: taskID) {
                        await load()
                    }
            )
    }

    // MARK: - Private

    private var taskID: String {
        guard let url else { return "" }
        let size = maxPixelSize.map { String(Int($0.rounded(.up))) } ?? "full"
        return "\(url.absoluteString)#\(size)"
    }

    private func load() async {
        guard let url else {
            if phaseKey != nil {
                phaseKey = nil
                phase = .empty
            }
            return
        }
        let cache = ImageCache.shared
        let key = ImageCache.memoryKey(for: url, maxPixelSize: maxPixelSize)
        if phaseKey == key, case .success = phase { return }   // already showing it

        if let hot = cache.memoryImage(for: url, maxPixelSize: maxPixelSize) {
            show(hot, key: key)
            return
        }
        // A different picture from the one on screen: don't keep showing it.
        if phaseKey != key {
            phaseKey = nil
            phase = .empty
        }

        if let stored = await cache.diskImage(for: url, maxPixelSize: maxPixelSize) {
            guard !Task.isCancelled else { return }
            show(stored, key: key)
            return
        }
        guard !Task.isCancelled else { return }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            guard let image = await cache.storeDownloaded(data, for: url, maxPixelSize: maxPixelSize) else {
                throw URLError(.cannotDecodeContentData)
            }
            guard !Task.isCancelled else { return }
            show(image, key: key)
        } catch {
            guard !Task.isCancelled else { return }
            phaseKey = key
            phase = .failure(error)
        }
    }

    private func show(_ image: UIImage, key: String) {
        phaseKey = key
        phase = .success(Image(uiImage: image))
    }
}
