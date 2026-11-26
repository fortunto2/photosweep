import Foundation

/// Duplicate / similar-photo detection, abstracted so the ViewModel runs on a fake.
protocol SimilarPhotoFinderProtocol: Sendable {
    /// Streams growing results while photos are analyzed; the last element has
    /// `isFinished == true`. Cancelling the consumer cancels the scan.
    func scan(scope: SimilarScope) async -> AsyncStream<SimilarScanProgress>
}
