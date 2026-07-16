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

    init(filter: MediaFilter, library: PhotoLibraryServiceProtocol) {
        self.filter = filter
        self.library = library
    }

    var selectedBytes: Int64 {
        assets.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.byteSize }
    }

    var allSelected: Bool { !assets.isEmpty && selected.count == assets.count }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        switch filter {
        case .largeVideos:
            assets = await library.fetchLargeVideos(limit: videoLimit)
        case .screenshots:
            assets = await library.fetchScreenshots()
        }
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
