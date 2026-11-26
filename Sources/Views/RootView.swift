import Photos
import SwiftUI

/// Gates the app on photo-library permission, then shows the tab bar.
struct RootView: View {
    let library: PhotoLibraryServiceProtocol
    let storage: StorageServiceProtocol
    let finder: SimilarPhotoFinderProtocol
    let track: PhotoLibraryService.Track

    @State private var status: PHAuthorizationStatus = .notDetermined

    var body: some View {
        Group {
            switch status {
            case .authorized, .limited:
                MainTabView(library: library, storage: storage, finder: finder, track: track)
            default:
                PermissionView(status: status) {
                    status = await library.requestAuthorization()
                }
            }
        }
        .task {
            status = library.authorizationStatus()
            LaunchClock.mark("auth_status_\(status.rawValue)")
        }
    }
}

private struct MainTabView: View {
    let library: PhotoLibraryServiceProtocol
    let storage: StorageServiceProtocol
    let finder: SimilarPhotoFinderProtocol
    let track: PhotoLibraryService.Track

    var body: some View {
        TabView {
            DashboardView(library: library, storage: storage)
                .tabItem { Label("Storage", systemImage: "chart.pie.fill") }

            SimilarPhotosView(finder: finder, library: library, track: track)
                .tabItem { Label("Similar", systemImage: "square.on.square") }

            MediaListView(filter: .largeVideos, library: library)
                .tabItem { Label("Videos", systemImage: "video.fill") }

            MediaListView(filter: .screenshots, library: library)
                .tabItem { Label("Screens", systemImage: "camera.viewfinder") }

            AppGuideView()
                .tabItem { Label("Apps", systemImage: "app.badge") }
        }
    }
}
