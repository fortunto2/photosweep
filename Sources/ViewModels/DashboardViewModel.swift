import Foundation

@Observable
@MainActor
final class DashboardViewModel {
    private let storage: StorageServiceProtocol
    private let library: PhotoLibraryServiceProtocol

    var storageInfo: StorageInfo?
    var breakdown: LibraryBreakdown?
    var isLoading = false

    init(storage: StorageServiceProtocol, library: PhotoLibraryServiceProtocol) {
        self.storage = storage
        self.library = library
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        storageInfo = try? storage.currentStorage()
        breakdown = await library.libraryBreakdown()
    }
}
