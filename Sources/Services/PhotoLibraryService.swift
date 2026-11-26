import Foundation
import Photos

/// Real photo-library backend. An `actor` so all PhotoKit state is serialized off the
/// main thread; it only ever hands back `Sendable` snapshots (`MediaAsset`, progress).
///
/// One size scan runs at a time and is shared: the dashboard and both lists subscribe
/// to `scanUpdates`, and the heavy walk itself runs in `LibraryScanner` outside the actor.
actor PhotoLibraryService: PhotoLibraryServiceProtocol {
    typealias Track = @Sendable (_ name: String, _ props: [String: String], _ metrics: [String: Double]) -> Void

    private let index: SizeIndex
    private let track: Track
    private var indexLoaded = false

    private var scanTask: Task<Void, Never>?
    private var latest: LibraryScanProgress?
    private var lastFinished: Date?
    private var listeners: [UUID: AsyncStream<LibraryScanProgress>.Continuation] = [:]

    /// A finished scan younger than this is reused instead of walking 100k assets again.
    private let freshFor: TimeInterval = 120

    init(index: SizeIndex = SizeIndex(url: SizeIndex.defaultURL), track: @escaping Track = { _, _, _ in }) {
        self.index = index
        self.track = track
    }

    nonisolated func authorizationStatus() -> PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    @discardableResult
    func requestAuthorization() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    // MARK: - Scan

    func scanUpdates(force: Bool) -> AsyncStream<LibraryScanProgress> {
        let (stream, continuation) = AsyncStream<LibraryScanProgress>.makeStream()
        let isFresh = lastFinished.map { Date().timeIntervalSince($0) < freshFor } ?? false
        if let latest, latest.isFinished, isFresh, !force, scanTask == nil {
            continuation.yield(latest)
            continuation.finish()
            return stream
        }
        let id = UUID()
        listeners[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeListener(id) }
        }
        if let latest, !latest.isFinished { continuation.yield(latest) }
        if scanTask == nil { startScan() }
        return stream
    }

    private func removeListener(_ id: UUID) { listeners[id] = nil }

    private func publish(_ progress: LibraryScanProgress) {
        latest = progress
        for continuation in listeners.values {
            continuation.yield(progress)
            if progress.isFinished { continuation.finish() }
        }
        if progress.isFinished { listeners.removeAll() }
    }

    private func startScan() {
        let index = index
        let needsLoad = !indexLoaded
        indexLoaded = true
        scanTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let started = Date()
            let fetches = LibraryScanner.fetch()
            let counts = fetches.counts
            // Exact counts on screen before anything else is read.
            await self.publish(LibraryScanProgress(
                phase: .cached, breakdown: counts, scanned: 0, total: counts.totalCount,
                hasCachedSizes: false, seconds: Date().timeIntervalSince(started), measuredFresh: 0
            ))
            if needsLoad { index.load() }
            let cached = index.breakdown()
            let hasCache = cached.totalCount > 0
            var shown = counts
            if hasCache {
                shown.videoBytes = cached.videoBytes
                shown.screenshotBytes = cached.screenshotBytes
                shown.otherPhotoBytes = cached.otherPhotoBytes
                await self.publish(LibraryScanProgress(
                    phase: .cached, breakdown: shown, scanned: 0, total: counts.totalCount,
                    hasCachedSizes: true, seconds: Date().timeIntervalSince(started), measuredFresh: 0
                ))
            }
            self.track("scan_started", ["cache": hasCache ? "warm" : "cold"], ["items": Double(counts.totalCount)])

            let result = await LibraryScanner.scan(fetches, index: index) { measured, scanned, fresh in
                var b = measured
                b.videoCount = counts.videoCount
                b.screenshotCount = counts.screenshotCount
                b.otherPhotoCount = counts.otherPhotoCount
                await self.publish(LibraryScanProgress(
                    phase: .measuring, breakdown: hasCache ? shown : b, scanned: scanned,
                    total: counts.totalCount, hasCachedSizes: hasCache,
                    seconds: Date().timeIntervalSince(started), measuredFresh: fresh
                ))
            }
            index.saveIfNeeded()
            var final = result.breakdown
            final.videoCount = counts.videoCount
            final.screenshotCount = counts.screenshotCount
            final.otherPhotoCount = counts.otherPhotoCount
            let seconds = Date().timeIntervalSince(started)
            self.track("scan_finished", ["cache": hasCache ? "warm" : "cold"], [
                "items": Double(counts.totalCount), "seconds": (seconds * 10).rounded() / 10,
                "measured": Double(result.fresh), "videos": Double(counts.videoCount),
                "screenshots": Double(counts.screenshotCount), "gb": Double(final.totalBytes) / 1e9,
            ])
            await self.finish(LibraryScanProgress(
                phase: .finished, breakdown: final, scanned: counts.totalCount, total: counts.totalCount,
                hasCachedSizes: false, seconds: seconds, measuredFresh: result.fresh
            ))
        }
    }

    private func finish(_ progress: LibraryScanProgress) {
        scanTask = nil
        lastFinished = Date()
        publish(progress)
    }

    // MARK: - Lists (read from the index; complete once the scan has passed them)

    func largestVideos(limit: Int) -> [MediaAsset] {
        Array(index.assets(of: .video).sorted { $0.byteSize > $1.byteSize }.prefix(limit))
    }

    func screenshots() -> [MediaAsset] {
        index.assets(of: .screenshot).sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
    }

    func photos(format: PhotoFormat) -> [MediaAsset] {
        index.assets(format: format).sorted { $0.byteSize > $1.byteSize }
    }

    func libraryFormats() -> FormatMix { index.formatMix() }

    /// Reads the newest `limit` camera photos directly (~2 ms each), so the answer does not
    /// wait for the background scan to reach them.
    func recentFormats(limit: Int) -> FormatMix {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "mediaType == %d AND NOT ((mediaSubtypes & %d) != 0)",
                                        PHAssetMediaType.image.rawValue,
                                        PHAssetMediaSubtype.photoScreenshot.rawValue)
        options.fetchLimit = limit
        var mix = FormatMix()
        PHAsset.fetchAssets(with: options).enumerateObjects { asset, _, _ in
            let mod = asset.modificationDate?.timeIntervalSince1970 ?? 0
            let e = LibraryScanner.measure(asset, id: asset.localIdentifier, mod: mod, isScreenshot: false)
            if let f = PhotoFormat(rawValue: e.format) { mix.add(f, bytes: e.bytes) }
            var liveBytes: Int64 = 0, editBytes: Int64 = 0
            for r in PHAssetResource.assetResources(for: asset) {
                let size = (r.value(forKey: "fileSize") as? Int64) ?? Int64((r.value(forKey: "fileSize") as? Int) ?? 0)
                switch r.type {
                case .pairedVideo, .fullSizePairedVideo, .adjustmentBasePairedVideo: liveBytes += size
                case .fullSizePhoto: editBytes += size
                default: break
                }
            }
            if liveBytes > 0 { mix.live.count += 1; mix.live.bytes += liveBytes }
            if editBytes > 0 { mix.edited.count += 1; mix.edited.bytes += editBytes }
        }
        print("[formats] recent total=\(mix.total) live=\(mix.live.count)/\(mix.live.bytes / 1_000_000)MB "
              + "edited=\(mix.edited.count)/\(mix.edited.bytes / 1_000_000)MB "
              + "all=\(mix.buckets.values.reduce(0) { $0 + $1.bytes } / 1_000_000)MB"); fflush(stdout)
        return mix
    }

    /// Re-reads on-device state for a short list (the index may predate an iCloud
    /// offload or download). ~2 ms per asset, so only for what is on screen.
    func refreshLocality(_ assets: [MediaAsset]) -> [MediaAsset] {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: assets.map(\.id), options: nil)
        var local: [String: Bool] = [:]
        fetch.enumerateObjects { asset, _, _ in
            let resources = PHAssetResource.assetResources(for: asset)
            local[asset.localIdentifier] = !resources.contains {
                ($0.value(forKey: "locallyAvailable") as? Bool) == false
            }
        }
        return assets.compactMap { asset in
            guard let isLocal = local[asset.id] else { return nil } // deleted meanwhile
            return MediaAsset(
                id: asset.id, kind: asset.kind, byteSize: asset.byteSize, creationDate: asset.creationDate,
                duration: asset.duration, pixelWidth: asset.pixelWidth, pixelHeight: asset.pixelHeight,
                isLocal: isLocal
            )
        }
    }

    // MARK: - Delete

    func delete(assetIDs: [String]) async throws {
        let started = Date()
        print("[delete] on-actor n=\(assetIDs.count)"); fflush(stdout)
        defer { print("[delete] done s=\(Date().timeIntervalSince(started))"); fflush(stdout) }
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: assetIDs, options: nil)
        var assets: [PHAsset] = []
        fetch.enumerateObjects { asset, _, _ in assets.append(asset) }
        guard !assets.isEmpty else { return }

        print("[delete] fetched s=\(Date().timeIntervalSince(started))"); fflush(stdout)
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }
        index.remove(assetIDs)
        lastFinished = nil // totals changed; next dashboard visit re-walks (warm, fast)
        Task.detached(priority: .utility) { [index] in index.saveIfNeeded() }
    }
}
