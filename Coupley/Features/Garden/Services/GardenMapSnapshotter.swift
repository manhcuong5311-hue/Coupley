//
//  GardenMapSnapshotter.swift
//  Coupley
//
//  Map snapshots for postcards, the seed sheet and lists (D5): exact places
//  get an 800 m span with a tree pin, areas a 6 km span with a soft circle.
//  Memory and disk caches, at most two snapshotters at once; nil offline or
//  on failure so the caller shows the scene swatch. Purged when the app
//  leaves `.ready`.
//
//  Only the MKMapSnapshotter call and the pin's position run on the main
//  actor. Compositing the pin or the circle onto the snapshot, PNG encoding,
//  writing, and decoding a disk hit (fully, so drawing it costs nothing)
//  all run off it. The disk tier keeps a 30-day TTL and a size cap: it is
//  swept once a session, on first use, and after every write.
//
//  Snapshots carry no Apple legal label of their own, so every view that
//  shows one (GardenSnapshotImage) overlays the attribution.
//

import Foundation
import CoreGraphics
import CryptoKit
import ImageIO
import MapKit
import UIKit
import UniformTypeIdentifiers

@MainActor
final class GardenMapSnapshotter: GardenMapSnapshotting {

    static let shared = GardenMapSnapshotter()

    /// At most this many MKMapSnapshotters run at once (D5).
    private static let maxConcurrent = 2
    /// Disk files rendered longer ago than this are rendered again (a hit
    /// never touches a file's date, so it stays "rendered at").
    nonisolated private static let diskTTL: TimeInterval = 30 * 24 * 3600
    /// The disk tier's cap: past it, the oldest renders go first.
    nonisolated private static let diskLimitBytes = 20 * 1024 * 1024
    nonisolated private static let folderName = "GardenSnapshots"
    /// Exact spots: the span around the pin. Areas: the span around the circle.
    private static let exactSpanMeters: CLLocationDistance = 800
    private static let areaSpanMeters: CLLocationDistance = 6000
    /// The soft circle of an area place (about the 2-decimal rounding).
    private static let areaRadiusMeters: CLLocationDistance = 600

    private let memory: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.countLimit = 30
        return cache
    }()

    private var running = 0
    /// Callers waiting for a free snapshotter, oldest first.
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Bool, Never>)] = []
    /// The disk tier has been swept this session.
    private var hasSwept = false

    private init() {}

    // MARK: GardenMapSnapshotting

    func snapshot(_ request: GardenSnapshotRequest) async -> CGImage? {
        guard request.width > 0, request.height > 0 else { return nil }
        sweepOncePerSession()
        let key = Self.cacheKey(request)
        if let hit = memory.object(forKey: key as NSString) { return hit }

        if let image = await Self.readDisk(Self.fileURL(key)) {
            memory.setObject(image, forKey: key as NSString)
            return image
        }

        // A row that scrolled away cancels its job while it waits for a slot.
        guard await acquireSlot() else { return nil }
        defer { releaseSlot() }
        // Another caller may have rendered it meanwhile.
        if let hit = memory.object(forKey: key as NSString) { return hit }
        guard !Task.isCancelled, let image = await render(request) else { return nil }

        memory.setObject(image, forKey: key as NSString)
        if let url = Self.fileURL(key) { Self.writeDisk(image, to: url) }
        return image
    }

    /// Memory, disk and this phone's recent place picks (E11).
    func purge() {
        memory.removeAllObjects()
        GardenPlaceSearch.purgeRecentPicks()
        if let folder = Self.folderURL {
            Task.detached(priority: .utility) {
                try? FileManager.default.removeItem(at: folder)
            }
        }
    }

    // MARK: Rendering

    private func render(_ request: GardenSnapshotRequest) async -> CGImage? {
        let center = CLLocationCoordinate2D(latitude: request.latitude, longitude: request.longitude)
        let span = request.precision == .exact ? Self.exactSpanMeters : Self.areaSpanMeters
        let scale = min(3, max(1, UITraitCollection.current.displayScale))

        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: center, latitudinalMeters: span, longitudinalMeters: span)
        options.size = CGSize(width: request.width, height: request.height)
        let configuration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        configuration.pointOfInterestFilter = .excludingAll
        options.preferredConfiguration = configuration
        options.traitCollection = UITraitCollection { traits in
            traits.userInterfaceStyle = request.isDark ? .dark : .light
            traits.displayScale = scale
        }

        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }

        // Here only where the pin or the circle goes; the drawing runs off
        // the main actor.
        let point = snapshot.point(for: center)
        let mark: SnapshotMark
        switch request.precision {
        case .exact:
            mark = .pin(at: point, isDark: request.isDark)
        case .area:
            // The circle's radius in points, measured along the meridian.
            let north = CLLocationCoordinate2D(
                latitude: center.latitude + Self.areaRadiusMeters / 111_320,
                longitude: center.longitude)
            let radius = abs(point.y - snapshot.point(for: north).y)
            mark = .area(at: point, radius: max(12, radius))
        }
        let base = snapshot.image
        return await Task.detached(priority: .userInitiated) {
            Self.composite(base, mark: mark)
        }.value
    }

    /// What is drawn on the map: a pin on an exact spot, a circle on an area.
    nonisolated private enum SnapshotMark: Sendable {
        case pin(at: CGPoint, isDark: Bool)
        case area(at: CGPoint, radius: CGFloat)
    }

    /// The snapshot with its pin or circle, at the snapshot's own scale.
    /// Off the main actor (UIGraphicsImageRenderer is thread-safe).
    nonisolated private static func composite(_ base: UIImage, mark: SnapshotMark) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = base.scale
        let renderer = UIGraphicsImageRenderer(size: base.size, format: format)
        let image = renderer.image { context in
            base.draw(at: .zero)
            switch mark {
            case .pin(let point, let isDark):
                drawPin(at: point, in: context.cgContext, isDark: isDark)
            case .area(let point, let radius):
                drawArea(at: point, radius: radius, in: context.cgContext)
            }
        }
        return image.cgImage
    }

    /// A small round tree pin: a white disc with a green tree glyph.
    nonisolated private static func drawPin(at point: CGPoint, in context: CGContext, isDark: Bool) {
        let diameter: CGFloat = 26
        let rect = CGRect(x: point.x - diameter / 2, y: point.y - diameter / 2, width: diameter, height: diameter)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 1.5), blur: 4,
                          color: UIColor.black.withAlphaComponent(0.35).cgColor)
        context.setFillColor(UIColor.white.cgColor)
        context.fillEllipse(in: rect)
        context.restoreGState()
        context.setStrokeColor(pinGreen.cgColor)
        context.setLineWidth(2)
        context.strokeEllipse(in: rect.insetBy(dx: 1, dy: 1))

        let configuration = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        if let glyph = UIImage(systemName: "tree.fill", withConfiguration: configuration)?
            .withTintColor(pinGreen, renderingMode: .alwaysOriginal) {
            let size = glyph.size
            glyph.draw(in: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                  width: size.width, height: size.height))
        }
    }

    /// A soft, unpinned circle: only the area is known.
    nonisolated private static func drawArea(at point: CGPoint, radius: CGFloat, in context: CGContext) {
        let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        context.setFillColor(pinGreen.withAlphaComponent(0.18).cgColor)
        context.fillEllipse(in: rect)
        context.setStrokeColor(pinGreen.withAlphaComponent(0.55).cgColor)
        context.setLineWidth(1.5)
        context.strokeEllipse(in: rect.insetBy(dx: 0.75, dy: 0.75))
    }

    nonisolated private static let pinGreen = UIColor(red: 0.30, green: 0.58, blue: 0.33, alpha: 1)

    // MARK: Slots

    private func acquireSlot() async -> Bool {
        if Task.isCancelled { return false }
        if running < Self.maxConcurrent {
            running += 1
            return true
        }
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiters.append((id, continuation))
            }
        } onCancel: {
            Task { @MainActor in self.cancelWaiter(id) }
        }
    }

    /// Hands the slot to the oldest waiter, or frees it.
    private func releaseSlot() {
        if waiters.isEmpty {
            running -= 1
        } else {
            waiters.removeFirst().continuation.resume(returning: true)
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(returning: false)
    }

    // MARK: Disk tier

    /// sha256 of the exact (4-decimal) spot, precision, size and scheme.
    nonisolated private static func cacheKey(_ request: GardenSnapshotRequest) -> String {
        let raw = String(format: "%.4f,%.4f,%@,%d,%d,%@", request.latitude, request.longitude,
                         request.precision.rawValue, request.width, request.height,
                         request.isDark ? "dark" : "light")
        return SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private static var folderURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(folderName, isDirectory: true)
    }

    nonisolated private static func fileURL(_ key: String) -> URL? {
        folderURL?.appendingPathComponent(key + ".png")
    }

    /// The file's image, read and fully decoded off the main actor (so
    /// drawing it later costs nothing there); nil when missing or older
    /// than the TTL.
    nonisolated private static func readDisk(_ url: URL?) async -> CGImage? {
        guard let url else { return nil }
        return await Task.detached(priority: .userInitiated) { () -> CGImage? in
            let manager = FileManager.default
            guard let attributes = try? manager.attributesOfItem(atPath: url.path),
                  let modified = attributes[.modificationDate] as? Date else { return nil }
            guard Date().timeIntervalSince(modified) < diskTTL else {
                try? manager.removeItem(at: url)
                return nil
            }
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
            return CGImageSourceCreateImageAtIndex(source, 0, options)
        }.value
    }

    /// PNG-encodes and writes a render off the main actor, then sweeps.
    nonisolated private static func writeDisk(_ image: CGImage, to url: URL) {
        Task.detached(priority: .utility) {
            let folder = url.deletingLastPathComponent()
            guard let data = pngData(image) else { return }
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
            sweep(folder)
        }
    }

    nonisolated private static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString,
                                                                 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// Once a session, on first use: renders past the TTL whose key is never
    /// asked for again (another size, the other appearance, a place tried
    /// and dropped) would otherwise stay.
    private func sweepOncePerSession() {
        guard !hasSwept, let folder = Self.folderURL else { return }
        hasSwept = true
        Task.detached(priority: .utility) {
            Self.sweep(folder)
        }
    }

    /// Deletes every render older than the TTL, then the oldest renders
    /// until the folder is under the cap.
    nonisolated private static func sweep(_ folder: URL) {
        let manager = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let urls = try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys,
                                                          options: [.skipsHiddenFiles]) else { return }
        let now = Date()
        var files: [(url: URL, bytes: Int, renderedAt: Date)] = []
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            let renderedAt = values.contentModificationDate ?? .distantPast
            if now.timeIntervalSince(renderedAt) >= diskTTL {
                try? manager.removeItem(at: url)
            } else {
                files.append((url: url, bytes: values.fileSize ?? 0, renderedAt: renderedAt))
            }
        }
        var total = files.reduce(0) { $0 + $1.bytes }
        guard total > diskLimitBytes else { return }
        files.sort { $0.renderedAt < $1.renderedAt }
        for file in files {
            guard total > diskLimitBytes else { break }
            try? manager.removeItem(at: file.url)
            total -= file.bytes
        }
    }
}
