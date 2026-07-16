import Foundation

/// A Sendable value snapshot of a single photo-library item.
///
/// AI-NOTE: We deliberately do NOT expose `PHAsset` outside the actor — `PHAsset`
/// is not `Sendable`. The UI works only with these snapshots; deletion re-fetches
/// the live `PHAsset` by `id` inside `PhotoLibraryService`.
struct MediaAsset: Identifiable, Sendable, Hashable {
    /// `PHAsset.localIdentifier` — stable handle used to re-fetch and delete.
    let id: String
    let kind: MediaKind
    /// Physical bytes on device (sum of all `PHAssetResource` sizes).
    let byteSize: Int64
    let creationDate: Date?
    /// Seconds; `0` for stills.
    let duration: TimeInterval
    let pixelWidth: Int
    let pixelHeight: Int
    /// Is the full-resolution original physically on this device?
    ///
    /// With iCloud "Optimize Storage" a big video's original lives in the cloud and
    /// only a small proxy is local — so deleting it frees space in iCloud, not much
    /// here. `false` ⇒ show the ☁️ badge. `byteSize` is always the *original* size.
    let isLocal: Bool
}

enum MediaKind: String, Sendable {
    case photo
    case video
    case screenshot
}
