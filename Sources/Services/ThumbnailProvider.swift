import Photos
import UIKit

/// Loads thumbnails for grid cells. `@MainActor` because it feeds SwiftUI and
/// wraps `PHCachingImageManager`, which is not an actor.
@MainActor
final class ThumbnailProvider {
    static let shared = ThumbnailProvider()
    private let manager = PHCachingImageManager()

    func image(for id: String, size: CGSize) async -> UIImage? {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        guard let asset = fetch.firstObject else { return nil }

        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true      // may pull an iCloud-optimized original
        options.deliveryMode = .highQualityFormat   // single callback → safe with a continuation
        options.resizeMode = .fast

        return await withCheckedContinuation { continuation in
            manager.requestImage(
                for: asset,
                targetSize: size,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}
