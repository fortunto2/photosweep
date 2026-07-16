import Foundation

/// Which cleanable bucket a `MediaListView` is showing.
enum MediaFilter: Sendable {
    case largeVideos
    case screenshots

    var title: String {
        switch self {
        case .largeVideos: "Large Videos"
        case .screenshots: "Screenshots"
        }
    }

    var systemImage: String {
        switch self {
        case .largeVideos: "video.fill"
        case .screenshots: "camera.viewfinder"
        }
    }

    var emptyMessage: String {
        switch self {
        case .largeVideos: "No videos found in your library."
        case .screenshots: "No screenshots found."
        }
    }
}

/// How to order the media grid.
enum SortMode: String, CaseIterable, Sendable {
    case size = "Size"
    case duration = "Length"
    case newest = "Newest"
}

/// Show all items, only the on-device ones, or only the iCloud-offloaded ones.
/// Filtering to `.local` is the point: those are what actually free device space.
enum AvailabilityFilter: String, CaseIterable, Sendable {
    case all = "All"
    case local = "On device"
    case cloud = "iCloud"

    var systemImage: String {
        switch self {
        case .all: "square.stack.3d.up"
        case .local: "iphone"
        case .cloud: "icloud"
        }
    }

    func matches(_ asset: MediaAsset) -> Bool {
        switch self {
        case .all: true
        case .local: asset.isLocal
        case .cloud: !asset.isLocal
        }
    }
}

@Observable
@MainActor
final class MediaCleanupViewModel {
    let filter: MediaFilter
    private let library: PhotoLibraryServiceProtocol

    /// How many videos to surface — the big ones are what matters.
    private let videoLimit = 200

    /// Everything fetched (sorted); `assets` is the availability-filtered view of it.
    private var allAssets: [MediaAsset] = []

    var assets: [MediaAsset] = []
    var selected: Set<String> = []
    var isLoading = false
    var isDeleting = false
    var errorMessage: String?
    var sortMode: SortMode = .size {
        didSet { rebuild() }
    }
    var availability: AvailabilityFilter = .all {
        didSet { rebuild() }
    }

    init(filter: MediaFilter, library: PhotoLibraryServiceProtocol) {
        self.filter = filter
        self.library = library
    }

    /// Counts for the availability segmented control, so the user sees how many
    /// videos are local vs. offloaded before choosing.
    var localCount: Int { allAssets.count { $0.isLocal } }
    var cloudCount: Int { allAssets.count { !$0.isLocal } }

    /// Did the library return anything at all (before availability filtering)?
    var hasAnyAssets: Bool { !allAssets.isEmpty }

    /// Bytes of selected assets that are actually on-device — i.e. what deleting
    /// really frees on *this* device (cloud-only originals free ~0 here).
    var selectedLocalBytes: Int64 {
        allAssets.filter { selected.contains($0.id) && $0.isLocal }.reduce(0) { $0 + $1.byteSize }
    }

    var selectedBytes: Int64 {
        allAssets.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.byteSize }
    }

    /// True when every *visible* item is selected.
    var allSelected: Bool { !assets.isEmpty && assets.allSatisfy { selected.contains($0.id) } }

    private static func sorted(_ items: [MediaAsset], by mode: SortMode) -> [MediaAsset] {
        switch mode {
        case .size: items.sorted { $0.byteSize > $1.byteSize }
        case .duration: items.sorted { $0.duration > $1.duration }
        case .newest: items.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
        }
    }

    /// Recompute the visible list from `allAssets` using current sort + availability.
    private func rebuild() {
        assets = Self.sorted(allAssets.filter { availability.matches($0) }, by: sortMode)
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        switch filter {
        case .largeVideos:
            allAssets = await library.fetchLargeVideos(limit: videoLimit)
        case .screenshots:
            allAssets = await library.fetchScreenshots()
        }
        rebuild()
        // Drop selections whose assets no longer exist.
        let ids = Set(allAssets.map(\.id))
        selected = selected.intersection(ids)
    }

    func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    /// Selects only the currently-visible (filtered) items.
    func selectAll() { selected.formUnion(assets.map(\.id)) }
    func clearSelection() { selected.removeAll() }

    /// Adds every visible item older than `days` to the selection — e.g. "screenshots
    /// older than a year". `now` is injectable so the logic is deterministically testable.
    func selectOlderThan(days: Int, now: Date = Date()) {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: now) else { return }
        let ids = assets.filter { ($0.creationDate ?? .distantFuture) < cutoff }.map(\.id)
        selected.formUnion(ids)
    }

    /// Sends selected assets to Recently Deleted (iOS shows its own confirmation).
    func deleteSelected() async {
        guard !selected.isEmpty else { return }
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await library.delete(assetIDs: Array(selected))
            selected.removeAll()
            await load()
        } catch {
            errorMessage = "Couldn't delete: \(error.localizedDescription)"
        }
    }
}
