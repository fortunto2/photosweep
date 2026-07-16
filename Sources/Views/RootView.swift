import Photos
import SwiftUI

/// Gates the app on photo-library permission, then shows the tab bar.
struct RootView: View {
    let library: PhotoLibraryServiceProtocol
    let storage: StorageServiceProtocol

    @State private var status: PHAuthorizationStatus = .notDetermined

    var body: some View {
        Group {
            switch status {
            case .authorized, .limited:
                MainTabView(library: library, storage: storage)
            default:
                PermissionView(status: status) {
                    status = await library.requestAuthorization()
                }
            }
        }
        .task { status = library.authorizationStatus() }
    }
}

private struct MainTabView: View {
    let library: PhotoLibraryServiceProtocol
    let storage: StorageServiceProtocol

    var body: some View {
        TabView {
            DashboardView(library: library, storage: storage)
                .tabItem { Label("Storage", systemImage: "chart.pie.fill") }

            MediaListView(filter: .largeVideos, library: library)
                .tabItem { Label("Videos", systemImage: "video.fill") }

            MediaListView(filter: .screenshots, library: library)
                .tabItem { Label("Screens", systemImage: "camera.viewfinder") }

            AppGuideView()
                .tabItem { Label("Apps", systemImage: "app.badge") }
        }
    }
}
