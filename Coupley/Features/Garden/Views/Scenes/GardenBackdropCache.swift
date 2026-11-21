//
//  GardenBackdropCache.swift
//  Coupley
//
//  Our Garden, P5 (Scenes I): the static-layer cache (C2). Keyed by scene,
//  never by tree, so every tree in a scene shares its images.
//
//   1. Memory: a least-recently-used tier on the main actor whose cost limit
//      is GardenBackdropBudget.memoryCostLimit (the selected page and its two
//      neighbours, both sky variants), set by configure(band:scale:). It is
//      a strict limit, unlike NSCache's advisory one, so the tier provably
//      stays within budget; a memory warning empties it, as NSCache would.
//   2. Disk: PNGs under Library/Caches/GardenBackdrops/v<artVersion>/,
//      decoded off the main actor, written in the background after a
//      render, capped at 48 MB (least recently used first); older v<n>
//      folders are deleted. Our own art only, so it survives sign-out.
//   3. Render: ImageRenderer on the main actor, at most one per frame
//      across every caller (backdrops and swatches), only on a miss.
//
//  Layer images and where they go in the band (`frame(of:in:)`): far is
//  1.35 W wide and centred, near is the band, front is the band's bottom
//  32%. Painters always draw in band coordinates (GardenSceneKit header).
//

import CoreGraphics
import Foundation
import ImageIO
import Observation
import SwiftUI
import UIKit
import UniformTypeIdentifiers
#if DEBUG
import os
#endif

@MainActor
@Observable
final class GardenBackdropCache: GardenBackdropProviding {
    static let shared = GardenBackdropCache()

    /// Bumped when an asynchronously rendered swatch lands, so a view that
    /// asked for it in its body (and got nil) draws again.
    private var swatchRevision = 0

    @ObservationIgnored private var memory: [GardenBackdropKey: MemoryEntry] = [:]
    @ObservationIgnored private var memoryBytes = 0
    @ObservationIgnored private var memoryLimit: Int
    @ObservationIgnored private var useCounter: UInt64 = 0
    @ObservationIgnored private var inFlight: [GardenBackdropKey: Task<CGImage?, Never>] = [:]

    @ObservationIgnored private var prewarmQueue: [GardenBackdropKey] = []
    @ObservationIgnored private var prewarmTask: Task<Void, Never>?

    @ObservationIgnored private var swatches: [SwatchKey: MemoryEntry] = [:]
    @ObservationIgnored private var swatchQueue: [SwatchKey] = []
    @ObservationIgnored private var swatchTask: Task<Void, Never>?

    /// The display scale renders use for swatches (backdrop keys carry their own).
    @ObservationIgnored private var scale = 2
    /// When the last ImageRenderer pass ran (system uptime), for one render per frame.
    @ObservationIgnored private var lastRenderAt: TimeInterval = -1

    @ObservationIgnored private let disk = GardenBackdropDiskStore()
    @ObservationIgnored private var diskBytes = 0
    @ObservationIgnored private var hits = 0
    @ObservationIgnored private var misses = 0
    @ObservationIgnored private var renders = 0
    @ObservationIgnored private var memoryWarningObserver: NSObjectProtocol?

    /// One frame at 60 Hz: a render (≤ 8 ms on an A12) never shares a frame with another.
    private static let frameInterval: TimeInterval = 1.0 / 60
    /// Swatches are tiny; this many cover the look carousel, the shelf and the map.
    private static let swatchLimit = 32

    private init() {
        // Until the band is measured, budget for the widest band the spec names (416 pt).
        memoryLimit = GardenBackdropBudget.memoryCostLimit(band: CGSize(width: 416, height: 208), scale: 2)
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.removeAll() }
        }
        Task { [weak self, disk] in
            let bytes = await disk.prepare()
            self?.diskBytes = bytes
        }
    }

    // MARK: GardenBackdropProviding

    func image(for key: GardenBackdropKey) async -> CGImage? {
        let key = Self.normalized(key)
        guard key.width > 0, key.height > 0 else { return nil }
        if let image = touchMemory(key) {
            hits += 1
            return image
        }
        if let pending = inFlight[key] { return await pending.value }
        misses += 1
        let task = Task { await self.load(key) }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        return image
    }

    func cachedImage(for key: GardenBackdropKey) -> CGImage? {
        touchMemory(Self.normalized(key))
    }

    func prewarm(_ keys: [GardenBackdropKey]) {
        prewarmQueue = keys.map(Self.normalized).filter { memory[$0] == nil && $0.width > 0 && $0.height > 0 }
        guard prewarmTask == nil, !prewarmQueue.isEmpty else { return }
        prewarmTask = Task(priority: .low) { [weak self] in await self?.drainPrewarm() }
    }

    func configure(band: CGSize, scale: Int) {
        let scale = Self.clampScale(scale)
        self.scale = scale
        memoryLimit = GardenBackdropBudget.memoryCostLimit(band: band, scale: scale)
        evict(toFit: 0)
    }

    func swatch(scene: GardenSceneID, season: GardenSceneSeason, size: CGSize) -> CGImage? {
        _ = swatchRevision   // observed: a swatch rendered later redraws the asking view
        let key = SwatchKey(scene: scene, season: season, width: Int(size.width.rounded()),
                            height: Int(size.height.rounded()), scale: scale)
        guard key.width > 0, key.height > 0 else { return nil }
        if var entry = swatches[key] {
            entry.lastUse = nextUse()
            swatches[key] = entry
            return entry.image
        }
        // Never rendered inside the asking view's body: it arrives a frame
        // later through `swatchRevision`, one swatch per frame.
        if !swatchQueue.contains(key) { swatchQueue.append(key) }
        if swatchTask == nil {
            swatchTask = Task(priority: .low) { [weak self] in await self?.drainSwatches() }
        }
        return nil
    }

    func removeAll() {
        memory.removeAll()
        memoryBytes = 0
        swatches.removeAll()
        prewarmQueue.removeAll()
        swatchQueue.removeAll()
    }

    // MARK: The lab's Backdrop viewer

    var stats: (memoryBytes: Int, diskBytes: Int, hits: Int, misses: Int, renders: Int) {
        (memoryBytes: memoryBytes, diskBytes: diskBytes, hits: hits, misses: misses, renders: renders)
    }

    /// The memory tier's current limit (the viewer shows use against it).
    var memoryCostLimit: Int { memoryLimit }

    func clearDisk() {
        Task { [weak self, disk] in
            let bytes = await disk.clear()
            self?.diskBytes = bytes
        }
    }

    // MARK: Layout helpers for the scene page

    /// Where a layer's image goes in band coordinates: far is
    /// farWidthFactor wide and centred (offset it by the parallax while
    /// paging), near fills the band, front covers its bottom 32%.
    nonisolated static func frame(of layer: GardenBackdropLayer, in band: CGSize) -> CGRect {
        switch layer {
        case .far:
            let span = GardenSceneKit.farSpan(in: band)
            return CGRect(x: span.lowerBound, y: 0, width: span.upperBound - span.lowerBound, height: band.height)
        case .near:
            return CGRect(origin: .zero, size: band)
        case .front:
            let top = GardenSceneKit.frontTop(in: band)
            return CGRect(x: 0, y: top, width: band.width, height: band.height - top)
        }
    }

    /// The sky variants a page needs now: night only while darkness > 0,
    /// day only while darkness < 1.
    nonisolated static func variants(forDarkness darkness: Double) -> [GardenSkyVariant] {
        var variants: [GardenSkyVariant] = []
        if darkness < 1 { variants.append(.day) }
        if darkness > 0 { variants.append(.night) }
        return variants
    }

    /// Every key one page needs now (three layers × the variants its sky needs),
    /// for `image(for:)`, `cachedImage(for:)` and the neighbours' `prewarm`.
    nonisolated static func keys(scene: GardenSceneID, season: GardenSceneSeason, darkness: Double,
                                 band: CGSize, displayScale: CGFloat) -> [GardenBackdropKey] {
        let width = Int(band.width.rounded()), height = Int(band.height.rounded())
        let scale = clampScale(Int(displayScale.rounded(.up)))
        return variants(forDarkness: darkness).flatMap { variant in
            [GardenBackdropLayer.far, .near, .front].map { layer in
                GardenBackdropKey(scene: scene, layer: layer, style: GardenSceneStyle(variant: variant, season: season),
                                  width: width, height: height, scale: scale)
            }
        }
    }

    // MARK: Loading

    private func load(_ key: GardenBackdropKey) async -> CGImage? {
        if let url = disk.url(for: key.fileName), let image = await GardenBackdropDiskStore.decode(url) {
            insert(image, for: key)
            Task.detached(priority: .background) { [disk] in await disk.touch(key.fileName) }
            return image
        }
        await waitForRenderSlot()
        guard let image = render(key) else { return nil }
        insert(image, for: key)
        Task { [weak self, disk] in
            let bytes = await disk.save(image, named: key.fileName)
            self?.diskBytes = bytes
        }
        return image
    }

    private func drainPrewarm() async {
        while !prewarmQueue.isEmpty {
            let key = prewarmQueue.removeFirst()
            if memory[key] == nil { _ = await image(for: key) }
            await Self.nextRunLoopTurn()
        }
        prewarmTask = nil
    }

    private func drainSwatches() async {
        while !swatchQueue.isEmpty {
            await waitForRenderSlot()
            guard !swatchQueue.isEmpty else { break }
            let key = swatchQueue.removeFirst()
            if swatches[key] == nil, let image = renderSwatch(key) {
                storeSwatch(image, for: key)
                swatchRevision &+= 1
            }
        }
        swatchTask = nil
    }

    // MARK: Rendering (main actor, one per frame)

    /// Suspends until a frame has passed since the last render, then claims
    /// the slot. No suspension between the check and the claim, so two
    /// callers never render in the same frame.
    private func waitForRenderSlot() async {
        while true {
            let wait = lastRenderAt + Self.frameInterval - ProcessInfo.processInfo.systemUptime
            if wait <= 0 {
                lastRenderAt = ProcessInfo.processInfo.systemUptime
                return
            }
            try? await Task.sleep(for: .seconds(wait))
        }
    }

    private func render(_ key: GardenBackdropKey) -> CGImage? {
        #if DEBUG
        let signpost = GardenBackdropSignpost.signposter.beginInterval("garden.backdrop.render")
        defer { GardenBackdropSignpost.signposter.endInterval("garden.backdrop.render", signpost) }
        #endif
        let band = CGSize(width: key.width, height: key.height)
        let renderer = ImageRenderer(content: GardenBackdropLayerCanvas(painter: key.scene.painter, layer: key.layer,
                                                                        style: key.style, band: band))
        renderer.scale = CGFloat(key.scale)
        lastRenderAt = ProcessInfo.processInfo.systemUptime
        renders += 1
        return renderer.cgImage
    }

    private func renderSwatch(_ key: SwatchKey) -> CGImage? {
        let renderer = ImageRenderer(content: GardenSwatchCanvas(scene: key.scene, season: key.season,
                                                                 size: CGSize(width: key.width, height: key.height)))
        renderer.scale = CGFloat(key.scale)
        lastRenderAt = ProcessInfo.processInfo.systemUptime
        renders += 1
        return renderer.cgImage
    }

    // MARK: Memory tier

    private struct MemoryEntry {
        let image: CGImage
        let cost: Int
        var lastUse: UInt64
    }

    private struct SwatchKey: Hashable {
        let scene: GardenSceneID
        let season: GardenSceneSeason
        let width: Int
        let height: Int
        let scale: Int
    }

    private func nextUse() -> UInt64 {
        useCounter &+= 1
        return useCounter
    }

    private func touchMemory(_ key: GardenBackdropKey) -> CGImage? {
        guard var entry = memory[key] else { return nil }
        entry.lastUse = nextUse()
        memory[key] = entry
        return entry.image
    }

    private func insert(_ image: CGImage, for key: GardenBackdropKey) {
        let cost = image.bytesPerRow * image.height
        if let old = memory[key] { memoryBytes -= old.cost }
        memory[key] = nil
        evict(toFit: cost)
        memory[key] = MemoryEntry(image: image, cost: cost, lastUse: nextUse())
        memoryBytes += cost
    }

    /// Drops least recently used images until `incoming` more bytes fit.
    private func evict(toFit incoming: Int) {
        while memoryBytes + incoming > memoryLimit,
              let oldest = memory.min(by: { $0.value.lastUse < $1.value.lastUse }) {
            memoryBytes -= oldest.value.cost
            memory[oldest.key] = nil
        }
    }

    private func storeSwatch(_ image: CGImage, for key: SwatchKey) {
        if swatches.count >= Self.swatchLimit, let oldest = swatches.min(by: { $0.value.lastUse < $1.value.lastUse }) {
            swatches[oldest.key] = nil
        }
        swatches[key] = MemoryEntry(image: image, cost: image.bytesPerRow * image.height, lastUse: nextUse())
    }

    // MARK: Keys

    private nonisolated static func clampScale(_ scale: Int) -> Int { min(2, max(1, scale)) }

    /// Landscapes are soft: 2× is plenty, so a 3× phone shares the 2× images.
    private static func normalized(_ key: GardenBackdropKey) -> GardenBackdropKey {
        var key = key
        key.scale = clampScale(key.scale)
        return key
    }

    /// Resumes on the next turn of the main run loop, so a pre-warm step
    /// never stacks onto the work of the frame that asked for it.
    private static func nextRunLoopTurn() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}

// MARK: - Render views

/// One static layer in band coordinates, cropped to the layer's image frame.
private struct GardenBackdropLayerCanvas: View {
    let painter: any GardenScenePainting
    let layer: GardenBackdropLayer
    let style: GardenSceneStyle
    let band: CGSize

    var body: some View {
        let frame = GardenBackdropCache.frame(of: layer, in: band)
        let painter = painter, layer = layer, style = style, band = band
        Canvas { context, _ in
            context.translateBy(x: -frame.minX, y: -frame.minY)
            painter.drawLayer(layer, in: context, size: band, style: style)
        }
        .frame(width: frame.width, height: frame.height)
    }
}

/// A day swatch: a noon sky and the three static layers of a standard
/// 351 × 208 band, cropped to the swatch's aspect around the space between
/// the landmark and the knoll, and scaled down so props keep their proportions.
private struct GardenSwatchCanvas: View {
    let scene: GardenSceneID
    let season: GardenSceneSeason
    let size: CGSize

    var body: some View {
        let painter = scene.painter, horizonFraction = scene.info.layout.horizon
        let style = GardenSceneStyle(variant: .day, season: season)
        Canvas { context, size in
            let bandHeight: CGFloat = 208
            let windowWidth = bandHeight * size.width / max(1, size.height)
            let band = CGSize(width: max(351, windowWidth), height: bandHeight)
            let left = min(max(0, band.width * 0.45 - windowWidth / 2), band.width - windowWidth)
            context.scaleBy(x: size.height / bandHeight, y: size.height / bandHeight)
            context.translateBy(x: -left, y: 0)
            let horizon = band.height * horizonFraction
            context.fill(Path(CGRect(origin: .zero, size: band)),
                         with: .linearGradient(Gradient(colors: [GardenRGB(0x6FB7EA).color, GardenRGB(0xD8EEF8).color]),
                                               startPoint: .zero, endPoint: CGPoint(x: 0, y: horizon)))
            for layer in [GardenBackdropLayer.far, .near, .front] {
                painter.drawLayer(layer, in: context, size: band, style: style)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

// MARK: - Disk tier

/// Serialises the disk tier's writes, pruning and clearing off the main
/// actor. Reads bypass it (`decode`): files are written to a temporary name
/// and moved into place, so a reader never sees half a PNG.
private actor GardenBackdropDiskStore {
    private let folder: URL?

    init() {
        folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(GardenBackdropBudget.diskFolder, isDirectory: true)
            .appendingPathComponent("v\(GardenBackdropKey.artVersion)", isDirectory: true)
    }

    nonisolated func url(for fileName: String) -> URL? {
        folder?.appendingPathComponent(fileName, isDirectory: false)
    }

    /// Creates the folder, deletes older art versions, returns the bytes on disk.
    func prepare() -> Int {
        guard let folder else { return 0 }
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let root = folder.deletingLastPathComponent()
        let current = folder.lastPathComponent
        for old in (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        where old.lastPathComponent != current {
            try? fileManager.removeItem(at: old)
        }
        return files().reduce(0) { $0 + $1.bytes }
    }

    /// Writes a PNG, then trims the folder to the disk limit, least recently
    /// used first. Returns the bytes on disk.
    func save(_ image: CGImage, named fileName: String) -> Int {
        guard let folder, let destinationURL = url(for: fileName) else { return 0 }
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let temporary = folder.appendingPathComponent(".\(UUID().uuidString).png", isDirectory: false)
        if let destination = CGImageDestinationCreateWithURL(temporary as CFURL, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(destination, image, nil)
            if CGImageDestinationFinalize(destination) {
                try? fileManager.removeItem(at: destinationURL)
                try? fileManager.moveItem(at: temporary, to: destinationURL)
            }
        }
        try? fileManager.removeItem(at: temporary)
        return prune()
    }

    /// Marks a file as just used, so pruning keeps what is being shown.
    func touch(_ fileName: String) {
        guard let url = url(for: fileName) else { return }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
    }

    func clear() -> Int {
        for file in files() { try? FileManager.default.removeItem(at: file.url) }
        return 0
    }

    private func prune() -> Int {
        var entries = files().sorted { $0.used < $1.used }
        var total = entries.reduce(0) { $0 + $1.bytes }
        while total > GardenBackdropBudget.diskLimitBytes, !entries.isEmpty {
            let oldest = entries.removeFirst()
            try? FileManager.default.removeItem(at: oldest.url)
            total -= oldest.bytes
        }
        return total
    }

    private func files() -> [(url: URL, bytes: Int, used: Date)] {
        guard let folder else { return [] }
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys,
                                                                 options: [.skipsHiddenFiles])) ?? []
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return (url: url, bytes: values.fileSize ?? 0, used: values.contentModificationDate ?? .distantPast)
        }
    }

    /// Reads and fully decodes a PNG on a background thread (never on the
    /// main actor), so drawing it later costs nothing.
    nonisolated static func decode(_ url: URL) async -> CGImage? {
        await Task.detached(priority: .userInitiated) { () -> CGImage? in
            #if DEBUG
            let signpost = GardenBackdropSignpost.signposter.beginInterval("garden.backdrop.disk")
            defer { GardenBackdropSignpost.signposter.endInterval("garden.backdrop.disk", signpost) }
            #endif
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
            return CGImageSourceCreateImageAtIndex(source, 0, options)
        }.value
    }
}

#if DEBUG
/// Instruments intervals for C11's measurements (DEBUG builds only).
private nonisolated enum GardenBackdropSignpost {
    static let signposter = OSSignposter(subsystem: "com.SamCorp.Coupley", category: "Garden")
}
#endif
