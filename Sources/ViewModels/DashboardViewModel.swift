import Foundation

@Observable
@MainActor
final class DashboardViewModel {
    private let storage: StorageServiceProtocol
    private let library: PhotoLibraryServiceProtocol

    var storageInfo: StorageInfo?
    var breakdown: LibraryBreakdown?
    /// Latest scan step; drives the "Measuring sizes… 34%" line.
    var progress: LibraryScanProgress?
    var isLoading = false
    /// Formats of the newest camera photos: is the camera set to something heavy right now?
    var recent: FormatMix?
    /// Formats across the measured library.
    var formats: FormatMix?

    init(storage: StorageServiceProtocol, library: PhotoLibraryServiceProtocol) {
        self.storage = storage
        self.library = library
    }

    static let recentLimit = 60

    /// Bytes are final (or from the last scan) — vs. still growing on a first scan.
    var sizesAreSettled: Bool {
        guard let progress else { return false }
        return progress.isFinished || progress.hasCachedSizes
    }

    var progressText: String? {
        guard let progress, !progress.isFinished else { return nil }
        if progress.phase == .cached && !progress.hasCachedSizes { return "Measuring sizes…" }
        let percent = Int((progress.fraction * 100).rounded(.down))
        return progress.hasCachedSizes
            ? "Checking for changes… \(percent)%"
            : "Measuring sizes… \(percent)% of \(progress.total.formatted()) items"
    }

    /// Never blocks on the scan for anything but its own updates: the first one (counts)
    /// arrives in milliseconds, sizes follow.
    func load(force: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        storageInfo = try? storage.currentStorage()
        recent = await library.recentFormats(limit: Self.recentLimit)
        for await step in await library.scanUpdates(force: force) {
            progress = step
            breakdown = step.breakdown
            if step.isFinished || formats == nil || step.scanned % 16_384 < 4_096 {
                formats = await library.libraryFormats()
            }
            LaunchClock.mark("first_content")
            if step.hasCachedSizes { LaunchClock.mark("sizes_from_cache") }
            if step.isFinished { LaunchClock.mark("sizes_done") }
        }
    }
}
