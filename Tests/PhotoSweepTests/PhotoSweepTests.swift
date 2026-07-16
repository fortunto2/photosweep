import Photos
import Testing
@testable import PhotoSweep

// MARK: - Pure formatting / model math

@Test func bytesFormatterProducesHumanString() {
    #expect(Format.bytes(0).isEmpty == false)
    #expect(Format.bytes(1_500_000_000).contains("GB"))
}

@Test func durationFormatsMinutesSeconds() {
    #expect(Format.duration(0) == "")
    #expect(Format.duration(65) == "1:05")
    #expect(Format.duration(9) == "0:09")
}

@Test func storageMathIsConsistent() {
    let info = StorageInfo(totalCapacity: 100, availableCapacity: 40)
    #expect(info.usedCapacity == 60)
    #expect(info.usedFraction == 0.6)

    let empty = StorageInfo(totalCapacity: 0, availableCapacity: 0)
    #expect(empty.usedFraction == 0) // no divide-by-zero
}

@Test func breakdownSumsBuckets() {
    let breakdown = LibraryBreakdown(
        videoBytes: 10, videoCount: 1,
        screenshotBytes: 5, screenshotCount: 2,
        otherPhotoBytes: 2, otherPhotoCount: 3
    )
    #expect(breakdown.totalBytes == 17)
}

@Test func appGuideBuildsOpenURL() {
    let telegram = AppCacheGuide.curated.first { $0.bundleName == "Telegram" }
    #expect(telegram?.openURL == URL(string: "tg://"))
    let safari = AppCacheGuide.curated.first { $0.bundleName == "Safari" }
    #expect(safari?.openURL == nil) // no scheme → guide-only
}

// MARK: - ViewModel selection logic (with a fake library)

@MainActor
@Test func cleanupSelectionAndDeleteFlow() async {
    let fake = FakeLibrary(videos: [
        MediaAsset(id: "a", kind: .video, byteSize: 100, creationDate: nil, duration: 10, pixelWidth: 1, pixelHeight: 1),
        MediaAsset(id: "b", kind: .video, byteSize: 50, creationDate: nil, duration: 5, pixelWidth: 1, pixelHeight: 1),
    ])
    let vm = MediaCleanupViewModel(filter: .largeVideos, library: fake)

    await vm.load()
    #expect(vm.assets.count == 2)
    #expect(vm.assets.first?.id == "a") // sorted largest first by the fake

    vm.toggle("a")
    #expect(vm.selectedBytes == 100)
    vm.selectAll()
    #expect(vm.allSelected)
    #expect(vm.selectedBytes == 150)

    await vm.deleteSelected()
    #expect(vm.assets.isEmpty)
    #expect(vm.selected.isEmpty)
}

/// In-memory fake. `@unchecked Sendable` is fine here: tests drive it serially.
private final class FakeLibrary: PhotoLibraryServiceProtocol, @unchecked Sendable {
    private var videos: [MediaAsset]
    private var screenshots: [MediaAsset]

    init(videos: [MediaAsset] = [], screenshots: [MediaAsset] = []) {
        self.videos = videos.sorted { $0.byteSize > $1.byteSize }
        self.screenshots = screenshots
    }

    func authorizationStatus() -> PHAuthorizationStatus { .authorized }
    func requestAuthorization() async -> PHAuthorizationStatus { .authorized }
    func fetchLargeVideos(limit: Int) async -> [MediaAsset] { Array(videos.prefix(limit)) }
    func fetchScreenshots() async -> [MediaAsset] { screenshots }
    func libraryBreakdown() async -> LibraryBreakdown { LibraryBreakdown() }

    func delete(assetIDs: [String]) async throws {
        let drop = Set(assetIDs)
        videos.removeAll { drop.contains($0.id) }
        screenshots.removeAll { drop.contains($0.id) }
    }
}
