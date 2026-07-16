import Photos

/// Real photo-library backend. An `actor` so all PhotoKit access is serialized
/// off the main thread; it only ever hands back `Sendable` `MediaAsset` snapshots.
actor PhotoLibraryService: PhotoLibraryServiceProtocol {

    nonisolated func authorizationStatus() -> PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    @discardableResult
    func requestAuthorization() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    func fetchLargeVideos(limit: Int) async -> [MediaAsset] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
        let result = PHAsset.fetchAssets(with: options)

        var assets: [MediaAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            assets.append(Self.snapshot(of: asset, kind: .video))
        }
        return Array(assets.sorted { $0.byteSize > $1.byteSize }.prefix(limit))
    }

    func fetchScreenshots() async -> [MediaAsset] {
        let collections = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum, subtype: .smartAlbumScreenshots, options: nil
        )
        guard let album = collections.firstObject else { return [] }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(in: album, options: options)

        var assets: [MediaAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            assets.append(Self.snapshot(of: asset, kind: .screenshot))
        }
        return assets
    }

    func libraryBreakdown() async -> LibraryBreakdown {
        var breakdown = LibraryBreakdown()

        // Screenshots first so we don't double-count them as "other photos".
        let screenshots = await fetchScreenshots()
        let screenshotIDs = Set(screenshots.map(\.id))
        for shot in screenshots {
            breakdown.screenshotBytes += shot.byteSize
            breakdown.screenshotCount += 1
        }

        let all = PHAsset.fetchAssets(with: nil)
        all.enumerateObjects { asset, _, _ in
            let size = Self.byteSize(of: asset)
            switch asset.mediaType {
            case .video:
                breakdown.videoBytes += size
                breakdown.videoCount += 1
            case .image where !screenshotIDs.contains(asset.localIdentifier):
                breakdown.otherPhotoBytes += size
                breakdown.otherPhotoCount += 1
            default:
                break
            }
        }
        return breakdown
    }

    func delete(assetIDs: [String]) async throws {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: assetIDs, options: nil)
        var assets: [PHAsset] = []
        fetch.enumerateObjects { asset, _, _ in assets.append(asset) }
        guard !assets.isEmpty else { return }

        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }
    }

    // MARK: - Helpers

    private static func snapshot(of asset: PHAsset, kind: MediaKind) -> MediaAsset {
        MediaAsset(
            id: asset.localIdentifier,
            kind: kind,
            byteSize: byteSize(of: asset),
            creationDate: asset.creationDate,
            duration: asset.duration,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            isLocal: isLocallyAvailable(of: asset)
        )
    }

    /// Whether the full original is on-device (vs. offloaded to iCloud).
    ///
    /// AI-NOTE: `PHAssetResource` exposes the KVC flag `"locallyAvailable"` (same
    /// family as `"fileSize"`). If any resource reports not-local, the original has
    /// been optimized to iCloud. No network hit — safe to call while scanning.
    static func isLocallyAvailable(of asset: PHAsset) -> Bool {
        let resources = PHAssetResource.assetResources(for: asset)
        guard !resources.isEmpty else { return true }
        for resource in resources {
            if let local = resource.value(forKey: "locallyAvailable") as? Bool, local == false {
                return false
            }
        }
        return true
    }

    /// Physical bytes for an asset.
    ///
    /// AI-NOTE: `PHAssetResource` exposes no public size property, but the private
    /// KVC key `"fileSize"` is stable and used by every photo-cleaner app. We sum
    /// across resources (a Live Photo / video may have several). Falls back to 0 if
    /// the key ever disappears — the app still works, just shows 0 for that item.
    static func byteSize(of asset: PHAsset) -> Int64 {
        PHAssetResource.assetResources(for: asset).reduce(Int64(0)) { total, resource in
            if let size = resource.value(forKey: "fileSize") as? Int64 {
                return total + size
            }
            if let size = resource.value(forKey: "fileSize") as? Int {
                return total + Int64(size)
            }
            return total
        }
    }
}
