import Foundation

/// Device volume capacity snapshot.
///
/// AI-NOTE: `availableCapacity` uses `volumeAvailableCapacityForImportantUsageKey`,
/// which is the number iOS is willing to free for us (matches the Settings figure
/// far better than the raw free-blocks count). This is the ONLY storage number a
/// sandboxed app can read — per-app / "System Data" breakdown is not available.
struct StorageInfo: Sendable, Equatable {
    let totalCapacity: Int64
    let availableCapacity: Int64

    var usedCapacity: Int64 { max(0, totalCapacity - availableCapacity) }

    var usedFraction: Double {
        guard totalCapacity > 0 else { return 0 }
        return Double(usedCapacity) / Double(totalCapacity)
    }
}

/// How much of the photo library falls into each cleanable bucket.
struct LibraryBreakdown: Sendable, Equatable {
    var videoBytes: Int64 = 0
    var videoCount: Int = 0
    var screenshotBytes: Int64 = 0
    var screenshotCount: Int = 0
    var otherPhotoBytes: Int64 = 0
    var otherPhotoCount: Int = 0

    var totalBytes: Int64 { videoBytes + screenshotBytes + otherPhotoBytes }
}
