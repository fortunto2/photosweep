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

@Observable
@MainActor
final class MediaCleanupViewModel {
    let filter: MediaFilter
    private let library: PhotoLibraryServiceProtocol

    /// How many videos to surface — the big ones are what matters.
    private let videoLimit = 200

    var assets: [MediaAsset] = []
    var selected: Set<String> = []
    var isLoading = false
    var isDeleting = false
    var errorMessage: String?
    var sortMode: SortMode = .size {
        didSet { assets = Self.sorted(assets, by: sortMode) }
    }

    init(filter: MediaFilter, library: PhotoLibraryServiceProtocol) {
        self.filter = filter
        self.library = library
    }

    /// Total on-device bytes of selected assets that are actually local — i.e. what
    /// deleting will really free on *this* device (cloud-only originals free ~0 here).
    var selectedLocalBytes: Int64 {
        assets.filter { selected.contains($0.id) && $0.isLocal }.reduce(0) { $0 + $1.byteSize }
    }

    private static func sorted(_ items: [MediaAsset], by mode: SortMode) -> [MediaAsset] {
        switch mode {
        case .size: items.sorted { $0.byteSize > $1.byteSize }
        case .duration: items.sorted { $0.duration > $1.duration }
        case .newest: items.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
        }
    }

    var selectedBytes: Int64 {
        assets.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.byteSize }
    }

    var allSelected: Bool { !assets.isEmpty && selected.count == assets.count }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        let fetched: [MediaAsset]
        switch filter {
        case .largeVideos:
            fetched = await library.fetchLargeVideos(limit: videoLimit)
        case .screenshots:
            fetched = await library.fetchScreenshots()
        }
        assets = Self.sorted(fetched, by: sortMode)
        // Drop selections whose assets no longer exist.
        let ids = Set(assets.map(\.id))
        selected = selected.intersection(ids)
    }

    func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    func selectAll() { selected = Set(assets.map(\.id)) }
    func clearSelection() { selected.removeAll() }

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
