import SwiftUI

@main
struct PhotoSweepApp: App {
    // Shared, Sendable backends created once for the app lifetime.
    private let library = PhotoLibraryService()
    private let storage = StorageService()

    var body: some Scene {
        WindowGroup {
            RootView(library: library, storage: storage)
        }
    }
}
