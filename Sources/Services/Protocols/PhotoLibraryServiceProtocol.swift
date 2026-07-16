import Photos

/// Abstraction over the photo library so ViewModels stay testable
/// (a fake conforming type can drive them without a real library).
protocol PhotoLibraryServiceProtocol: Sendable {
    func authorizationStatus() -> PHAuthorizationStatus
    @discardableResult
    func requestAuthorization() async -> PHAuthorizationStatus

    /// Videos sorted by physical size, largest first.
    func fetchLargeVideos(limit: Int) async -> [MediaAsset]

    /// Screenshots (newest first).
    func fetchScreenshots() async -> [MediaAsset]

    /// Aggregate cleanable-bucket sizes for the dashboard.
    func libraryBreakdown() async -> LibraryBreakdown

    /// Move the given assets to Recently Deleted. iOS shows its own confirmation
    /// alert; throws `PHPhotosError.userCancelled`-style errors if the user declines.
    func delete(assetIDs: [String]) async throws
}
