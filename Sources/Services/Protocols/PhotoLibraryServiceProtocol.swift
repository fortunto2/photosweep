import Photos

/// Abstraction over the photo library so ViewModels stay testable
/// (a fake conforming type can drive them without a real library).
protocol PhotoLibraryServiceProtocol: Sendable {
    func authorizationStatus() -> PHAuthorizationStatus
    @discardableResult
    func requestAuthorization() async -> PHAuthorizationStatus

    /// Progress of the shared background size scan. The first element arrives at once
    /// with exact counts; the stream finishes after the `.finished` element. A scan that
    /// finished recently is replayed instead of re-run unless `force` is set.
    func scanUpdates(force: Bool) async -> AsyncStream<LibraryScanProgress>

    /// Videos measured so far, largest first. Complete once the scan has finished.
    func largestVideos(limit: Int) async -> [MediaAsset]

    /// Screenshots measured so far, newest first.
    func screenshots() async -> [MediaAsset]

    /// Camera photos (not screenshots) measured so far, largest first.
    func largestPhotos(limit: Int) async -> [MediaAsset]

    /// Photos of one format measured so far (e.g. every RAW), largest first.
    func photos(format: PhotoFormat) async -> [MediaAsset]

    /// Formats of the newest camera photos (screenshots excluded): what the camera is set to now.
    func recentFormats(limit: Int) async -> FormatMix

    /// Formats across the photos measured so far.
    func libraryFormats() async -> FormatMix

    /// Originals on this iPhone vs only in iCloud, across everything measured.
    func storageSplit() async -> StorageSplit

    /// Fresh on-device/iCloud state for a short list; drops assets that no longer exist.
    func refreshLocality(_ assets: [MediaAsset]) async -> [MediaAsset]

    /// Move the given assets to Recently Deleted. iOS shows its own confirmation
    /// alert; throws `PHPhotosError.userCancelled`-style errors if the user declines.
    func delete(assetIDs: [String]) async throws
}

extension PhotoLibraryServiceProtocol {
    func photos(format: PhotoFormat) async -> [MediaAsset] { [] }
    func largestPhotos(limit: Int) async -> [MediaAsset] { [] }
    func recentFormats(limit: Int) async -> FormatMix { FormatMix() }
    func libraryFormats() async -> FormatMix { FormatMix() }
    func storageSplit() async -> StorageSplit { StorageSplit() }
}
