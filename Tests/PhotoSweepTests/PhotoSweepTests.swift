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
        MediaAsset(id: "a", kind: .video, byteSize: 100, creationDate: nil, duration: 10, pixelWidth: 1, pixelHeight: 1, isLocal: true),
        MediaAsset(id: "b", kind: .video, byteSize: 50, creationDate: nil, duration: 5, pixelWidth: 1, pixelHeight: 1, isLocal: true),
    ])
    let vm = MediaCleanupViewModel(filter: .largeVideos, library: fake)

    await vm.load()
    #expect(vm.assets.count == 2)
    #expect(vm.assets.first?.id == "a") // size sort: largest first

    vm.toggle("a")
    #expect(vm.selectedBytes == 100)
    vm.selectAll()
    #expect(vm.allSelected)
    #expect(vm.selectedBytes == 150)

    await vm.deleteSelected()
    #expect(vm.assets.isEmpty)
    #expect(vm.selected.isEmpty)
}

@MainActor
@Test func sortByDurationAndLocalBytes() async {
    let fake = FakeLibrary(videos: [
        // Biggest by size, but cloud-only → frees nothing locally.
        MediaAsset(id: "big-cloud", kind: .video, byteSize: 900, creationDate: nil, duration: 5, pixelWidth: 1, pixelHeight: 1, isLocal: false),
        // Smaller, local, longest.
        MediaAsset(id: "long-local", kind: .video, byteSize: 300, creationDate: nil, duration: 120, pixelWidth: 1, pixelHeight: 1, isLocal: true),
    ])
    let vm = MediaCleanupViewModel(filter: .largeVideos, library: fake)
    await vm.load()
    #expect(vm.assets.first?.id == "big-cloud") // default: size

    vm.sortMode = .duration
    #expect(vm.assets.first?.id == "long-local") // now longest first

    vm.selectAll()
    #expect(vm.selectedBytes == 1200)
    #expect(vm.selectedLocalBytes == 300) // only the local one frees on-device space
}

@MainActor
@Test func availabilityFilterHidesCloudItems() async {
    let fake = FakeLibrary(videos: [
        MediaAsset(id: "cloud", kind: .video, byteSize: 900, creationDate: nil, duration: 5, pixelWidth: 1, pixelHeight: 1, isLocal: false),
        MediaAsset(id: "local", kind: .video, byteSize: 300, creationDate: nil, duration: 9, pixelWidth: 1, pixelHeight: 1, isLocal: true),
    ])
    let vm = MediaCleanupViewModel(filter: .largeVideos, library: fake)
    await vm.load()
    #expect(vm.assets.count == 2)
    #expect(vm.localCount == 1)
    #expect(vm.cloudCount == 1)

    vm.availability = .local
    #expect(vm.assets.map(\.id) == ["local"])

    // Select-all only picks visible (local) items; deleting frees real device space.
    vm.selectAll()
    #expect(vm.selected == ["local"])
    #expect(vm.selectedLocalBytes == 300)

    vm.availability = .cloud
    #expect(vm.assets.map(\.id) == ["cloud"])
}

@MainActor
@Test func selectOlderThanPicksOldItems() async {
    let now = Date(timeIntervalSince1970: 1_700_000_000) // fixed reference
    let old = now.addingTimeInterval(-400 * 86_400)      // ~13 months ago
    let recent = now.addingTimeInterval(-30 * 86_400)    // ~1 month ago
    let fake = FakeLibrary(screenshots: [
        MediaAsset(id: "old", kind: .screenshot, byteSize: 10, creationDate: old, duration: 0, pixelWidth: 1, pixelHeight: 1, isLocal: true),
        MediaAsset(id: "recent", kind: .screenshot, byteSize: 10, creationDate: recent, duration: 0, pixelWidth: 1, pixelHeight: 1, isLocal: true),
    ])
    let vm = MediaCleanupViewModel(filter: .screenshots, library: fake)
    await vm.load()

    vm.selectOlderThan(days: 365, now: now)
    #expect(vm.selected == ["old"]) // only the >1yr screenshot
}

@MainActor
@Test func cacheGuardAvoidsRescanUnlessForced() async {
    let fake = FakeLibrary(videos: [
        MediaAsset(id: "a", kind: .video, byteSize: 10, creationDate: nil, duration: 1, pixelWidth: 1, pixelHeight: 1, isLocal: true),
    ])
    let vm = MediaCleanupViewModel(filter: .largeVideos, library: fake)

    await vm.load()          // scans
    await vm.load()          // cached — no rescan
    await vm.load()          // cached — no rescan
    #expect(fake.videoFetchCount == 1)

    await vm.load(force: true) // pull-to-refresh / library change
    #expect(fake.videoFetchCount == 2)
}

/// In-memory fake. `@unchecked Sendable` is fine here: tests drive it serially.
private final class FakeLibrary: PhotoLibraryServiceProtocol, @unchecked Sendable {
    private var videos: [MediaAsset]
    private var screenshots: [MediaAsset]
    private(set) var videoFetchCount = 0

    init(videos: [MediaAsset] = [], screenshots: [MediaAsset] = []) {
        self.videos = videos.sorted { $0.byteSize > $1.byteSize }
        self.screenshots = screenshots
    }

    func authorizationStatus() -> PHAuthorizationStatus { .authorized }
    func requestAuthorization() async -> PHAuthorizationStatus { .authorized }
    func fetchLargeVideos(limit: Int) async -> [MediaAsset] {
        videoFetchCount += 1
        return Array(videos.prefix(limit))
    }
    func fetchScreenshots() async -> [MediaAsset] { screenshots }
    func libraryBreakdown() async -> LibraryBreakdown { LibraryBreakdown() }

    func delete(assetIDs: [String]) async throws {
        let drop = Set(assetIDs)
        videos.removeAll { drop.contains($0.id) }
        screenshots.removeAll { drop.contains($0.id) }
    }
}
