import Foundation

/// One step of the background size scan, broadcast to every screen that listens.
///
/// Counts in `breakdown` are exact from the first update (they come from
/// `PHFetchResult.count`, which costs nothing). Bytes are what has been measured so
/// far, or the totals from the last finished scan while `phase == .cached`.
struct LibraryScanProgress: Sendable, Equatable {
    enum Phase: Sendable, Equatable {
        /// Counts are exact; bytes come from the previous launch's index (may be 0 on first run).
        case cached
        /// Sizes are being measured; `scanned` of `total` assets done.
        case measuring
        case finished
    }

    var phase: Phase
    var breakdown: LibraryBreakdown
    var scanned: Int
    var total: Int
    /// True when the bytes in `breakdown` came from a previous scan (index on disk).
    var hasCachedSizes: Bool
    /// Wall time since this scan started.
    var seconds: Double
    /// Assets whose size had to be read from PhotoKit (index misses) in this scan.
    var measuredFresh: Int

    var fraction: Double { total > 0 ? Double(scanned) / Double(total) : 1 }
    var isFinished: Bool { phase == .finished }
}
