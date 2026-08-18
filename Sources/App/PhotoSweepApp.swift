import SwiftUI
import SuperDuperAnalytics

@main
struct PhotoSweepApp: App {
    // Shared, Sendable backends created once for the app lifetime.
    private let library = PhotoLibraryService()
    private let storage = StorageService()

    @Environment(\.scenePhase) private var scenePhase

    /// App Store Connect counts the download; nothing there counts the second launch.
    /// UI test runs are excluded — a screenshot pass launches the app dozens of times.
    init() {
        guard !ProcessInfo.processInfo.arguments.contains("-uiTesting") else { return }
        Analytics.configure(source: "photosweep")
        Analytics.track("app_launched")
    }

    var body: some Scene {
        WindowGroup {
            RootView(library: library, storage: storage)
        }
        // The buffer dies with the process, and a cleaner is opened, used and closed in one go.
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { Analytics.flush() }
        }
    }
}
