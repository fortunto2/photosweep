import SwiftUI
import SuperDuperAnalytics

@main
struct PhotoSweepApp: App {
    // Shared, Sendable backends created once for the app lifetime.
    private static let track: PhotoLibraryService.Track = { name, props, metrics in
        Analytics.track(name, props: props, metrics: metrics)
    }
    /// One size index shared by the storage scan and the duplicate finder.
    private static let sizes = SizeIndex(url: SizeIndex.defaultURL)
    private let library = PhotoLibraryService(index: Self.sizes, track: Self.track)
    private let finder = SimilarPhotoFinder(sizes: Self.sizes, track: Self.track)
    private let storage = StorageService()

    @Environment(\.scenePhase) private var scenePhase

    /// App Store Connect counts the download; nothing there counts the second launch.
    /// UI test runs are excluded — a screenshot pass launches the app dozens of times.
    init() {
        LaunchClock.mark("app_init")
        guard !ProcessInfo.processInfo.arguments.contains("-uiTesting") else { return }
        #if DEBUG
        // Debug/dev installs ride as `auto` so ingest files them as machines, not people.
        Analytics.configure(source: "photosweep", automated: true)
        #else
        Analytics.configure(source: "photosweep")
        #endif
        Analytics.track("app_launched")
    }

    var body: some Scene {
        WindowGroup {
            RootView(library: library, storage: storage, finder: finder, track: Self.track)
        }
        // The buffer dies with the process, and a cleaner is opened, used and closed in one go.
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { Analytics.flush() }
        }
    }
}
