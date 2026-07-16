import Foundation
import Photos

extension Notification.Name {
    /// Posted (on main) whenever the photo library changes — deletions, edits, adds.
    static let photoLibraryChanged = Notification.Name("photoLibraryChanged")
}

/// Bridges PhotoKit's change callbacks to a plain Notification so views can refresh
/// without any VM importing PhotoKit. Register once via `LibraryChangeObserver.start()`
/// after authorization; it lives for the app's lifetime.
final class LibraryChangeObserver: NSObject, PHPhotoLibraryChangeObserver, @unchecked Sendable {
    static let shared = LibraryChangeObserver()

    private var registered = false

    /// Idempotent — safe to call from every view's `.task`.
    func start() {
        guard !registered else { return }
        registered = true
        PHPhotoLibrary.shared().register(self)
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        // Callback arrives on a background queue; hop to main for the notification.
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .photoLibraryChanged, object: nil)
        }
    }
}
