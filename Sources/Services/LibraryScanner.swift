import Foundation
import Photos

/// The heavy part of a library scan: walks every asset, reads sizes for index misses,
/// and reports progress. Runs off any actor so `PhotoLibraryService` stays responsive
/// (deletes, list reads) while a cold scan of a 100k-item library is in flight.
///
/// AI-NOTE: PHAsset/PHAssetResource are immutable and documented safe to read from any
/// thread; chunks are processed with `concurrentPerform`. Measured on iPhone 14 Pro Max,
/// 101k assets: v1.0 serial read = 229 s before anything showed (see docs/perf.md).
enum LibraryScanner {
    /// Assets per progress report; small enough for ~1 update/s on a cold scan.
    static let reportEvery = 4096
    /// Assets per GCD work item inside a report batch.
    static let chunk = 128

    struct Fetches: @unchecked Sendable {
        let videos: PHFetchResult<PHAsset>
        let images: PHFetchResult<PHAsset>
        let screenshotIDs: Set<String>

        var counts: LibraryBreakdown {
            var b = LibraryBreakdown()
            b.videoCount = videos.count
            b.screenshotCount = screenshotIDs.count
            b.otherPhotoCount = max(0, images.count - screenshotIDs.count)
            return b
        }
    }

    /// Cheap: fetch results are lazy; only the screenshot album is enumerated (ids only).
    static func fetch() -> Fetches {
        let videoOptions = PHFetchOptions()
        videoOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
        let imageOptions = PHFetchOptions()
        imageOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        // Newest first: if the user leaves mid-scan, the recent part is what got measured.
        let newest = [NSSortDescriptor(key: "creationDate", ascending: false)]
        videoOptions.sortDescriptors = newest
        imageOptions.sortDescriptors = newest

        var shots = Set<String>()
        let albums = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumScreenshots, options: nil)
        if let album = albums.firstObject {
            let result = PHAsset.fetchAssets(in: album, options: nil)
            shots.reserveCapacity(result.count)
            result.enumerateObjects { asset, _, _ in shots.insert(asset.localIdentifier) }
        }
        return Fetches(
            videos: PHAsset.fetchAssets(with: videoOptions),
            images: PHAsset.fetchAssets(with: imageOptions),
            screenshotIDs: shots
        )
    }

    /// Walks videos first (they hold most bytes), then images. Calls `report` after each
    /// batch with the bytes measured so far; returns the final measured breakdown.
    static func scan(
        _ fetches: Fetches,
        index: SizeIndex,
        report: (_ measured: LibraryBreakdown, _ scanned: Int, _ fresh: Int) async -> Void
    ) async -> (breakdown: LibraryBreakdown, fresh: Int) {
        var measured = LibraryBreakdown()
        var scanned = 0
        var fresh = 0
        var seen = Set<String>()
        seen.reserveCapacity(fetches.videos.count + fetches.images.count)

        for result in [fetches.videos, fetches.images] {
            var start = 0
            while start < result.count {
                if Task.isCancelled { return (measured, fresh) }
                let end = min(start + reportEvery, result.count)
                let batchStart = Date()
                let batch = processBatch(result, range: start..<end, shots: fetches.screenshotIDs, index: index)
                for (id, entry) in batch.entries {
                    seen.insert(id)
                    measured.add(entry.kind, bytes: entry.bytes)
                }
                fresh += batch.fresh
                scanned += end - start
                start = end
                await report(measured, scanned, fresh)
                if batch.fresh > 0 { await HeatGuard.cooldown(after: Date().timeIntervalSince(batchStart)) } // cached batches cost ~nothing
            }
        }
        index.retain(only: seen)
        return (measured, fresh)
    }

    private final class Collector: @unchecked Sendable {
        let lock = NSLock()
        var entries: [(String, IndexEntry)] = []
        var fresh: [(String, IndexEntry)] = []
    }

    private static func processBatch(
        _ result: PHFetchResult<PHAsset>,
        range: Range<Int>,
        shots: Set<String>,
        index: SizeIndex
    ) -> (entries: [(String, IndexEntry)], fresh: Int) {
        let collector = Collector()
        collector.entries.reserveCapacity(range.count)
        let chunks = stride(from: range.lowerBound, to: range.upperBound, by: chunk).map {
            $0..<min($0 + chunk, range.upperBound)
        }
        DispatchQueue.concurrentPerform(iterations: chunks.count) { i in
            let assets = result.objects(at: IndexSet(integersIn: chunks[i]))
            var local: [(String, IndexEntry)] = []
            var misses: [(String, IndexEntry)] = []
            local.reserveCapacity(assets.count)
            for asset in assets {
                let id = asset.localIdentifier
                let mod = asset.modificationDate?.timeIntervalSince1970 ?? 0
                // A photo indexed before formats were recorded is read once more (v1 → v2).
                if let hit = index.entry(id), hit.mod == mod, hit.kind == .video || !hit.format.isEmpty {
                    local.append((id, hit))
                    continue
                }
                let entry = measure(asset, id: id, mod: mod, isScreenshot: shots.contains(id))
                local.append((id, entry))
                misses.append((id, entry))
            }
            collector.lock.withLock {
                collector.entries.append(contentsOf: local)
                collector.fresh.append(contentsOf: misses)
            }
        }
        index.set(collector.fresh)
        return (collector.entries, collector.fresh.count)
    }

    /// One `assetResources` call yields both size and on-device state.
    ///
    /// AI-NOTE: `"fileSize"` / `"locallyAvailable"` are KVC keys on PHAssetResource, not
    /// public API, but stable for years and used by every cleaner app. Missing → 0 / local.
    static func measure(_ asset: PHAsset, id: String, mod: Double, isScreenshot: Bool) -> IndexEntry {
        var bytes: Int64 = 0
        var isLocal = true
        var uti = ""
        for resource in PHAssetResource.assetResources(for: asset) {
            if resource.type == .photo || (uti.isEmpty && resource.type == .fullSizePhoto) {
                uti = resource.uniformTypeIdentifier
            }
            if resource.uniformTypeIdentifier.contains("raw-image") { uti = resource.uniformTypeIdentifier }
            if let size = resource.value(forKey: "fileSize") as? Int64 {
                bytes += size
            } else if let size = resource.value(forKey: "fileSize") as? Int {
                bytes += Int64(size)
            }
            if let flag = resource.value(forKey: "locallyAvailable") as? Bool, !flag { isLocal = false }
        }
        let kind: MediaKind = asset.mediaType == .video ? .video : (isScreenshot ? .screenshot : .photo)
        return IndexEntry(
            mod: mod, bytes: bytes, isLocal: isLocal, kind: kind,
            created: asset.creationDate?.timeIntervalSince1970 ?? 0,
            duration: asset.duration, width: asset.pixelWidth, height: asset.pixelHeight,
            format: kind == .video ? "" : PhotoFormat.classify(uti: uti, width: asset.pixelWidth,
                                                              height: asset.pixelHeight).rawValue
        )
    }
}
