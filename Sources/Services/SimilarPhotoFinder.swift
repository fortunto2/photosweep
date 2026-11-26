import CoreGraphics
import Foundation
import Photos
import UIKit
@preconcurrency import Vision

/// Finds duplicate and near-identical photos on-device: Vision feature prints for
/// similarity, Crete-Roffet for blur, `PhotoGrouper` for the groups. Nothing leaves the phone.
///
/// Ported from PhotoSift (ImageAnalyzer + ScanLibraryUseCase), changed where a 70k-photo
/// library made the original too slow:
/// - pass 1 runs only the feature print + blur on a 320 px local thumbnail
///   (PhotoSift batched five Vision requests per photo);
/// - pass 2 (aesthetics, face quality) runs only for photos that ended up in a group;
/// - results are cached on disk (`FeatureStore`), so a rescan analyzes only new photos.
final class SimilarPhotoFinder: SimilarPhotoFinderProtocol, Sendable {
    typealias Track = PhotoLibraryService.Track

    private let store: FeatureStore
    private let sizes: SizeIndex
    private let track: Track
    private let grouper = PhotoGrouper()
    /// Concurrent thumbnail+Vision jobs; Vision runs on the Neural Engine, PhotoKit decode on CPU.
    private let width = 4
    /// Regroup and publish after this many newly analyzed photos.
    private let publishEvery = 400
    /// Pass 2 is ~30 ms a photo; cap it so a huge first scan still finishes promptly.
    private let qualityCap = 1_500

    init(
        store: FeatureStore = FeatureStore(url: FeatureStore.defaultURL),
        sizes: SizeIndex,
        track: @escaping Track = { _, _, _ in }
    ) {
        self.store = store
        self.sizes = sizes
        self.track = track
    }

    func scan(scope: SimilarScope) async -> AsyncStream<SimilarScanProgress> {
        let (stream, continuation) = AsyncStream<SimilarScanProgress>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let task = Task.detached(priority: .userInitiated) { [self] in
            await run(scope: scope, continuation: continuation)
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    private struct Candidate: @unchecked Sendable {
        let asset: PHAsset
        let id: String
        let mod: Double
    }

    private func run(scope: SimilarScope, continuation: AsyncStream<SimilarScanProgress>.Continuation) async {
        let started = Date()
        store.loadIfNeeded()
        let candidates = fetchCandidates(since: scope.since())
        let total = candidates.count
        track("similar_scan_started", ["scope": scope.rawValue], ["photos": Double(total)])
        continuation.yield(SimilarScanProgress(analyzed: 0, total: total, groups: [], blurry: [], isFinished: false, seconds: 0))

        var features: [PhotoFeatures] = []
        features.reserveCapacity(total)
        var analyzed = 0
        var fresh = 0
        var sincePublish = 0
        var cursor = 0

        await withTaskGroup(of: Analyzed?.self) { group in
            func addNext() {
                guard cursor < candidates.count else { return }
                let c = candidates[cursor]
                cursor += 1
                group.addTask { [self] in
                    if Task.isCancelled { return nil }
                    return await analyze(c)
                }
            }
            for _ in 0..<width { addNext() }
            while let result = await group.next() {
                analyzed += 1
                if let result {
                    features.append(result.features)
                    if result.isFreshlyAnalyzed { fresh += 1; sincePublish += 1 }
                }
                if sincePublish >= publishEvery {
                    sincePublish = 0
                    store.saveIfNeeded()
                    let out = grouper.group(features)
                    continuation.yield(SimilarScanProgress(
                        analyzed: analyzed, total: total, groups: out.groups, blurry: out.blurry,
                        isFinished: false, seconds: Date().timeIntervalSince(started)
                    ))
                    if ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue {
                        try? await Task.sleep(for: .seconds(2)) // back off on a hot phone
                    }
                }
                if !Task.isCancelled { addNext() }
            }
        }
        store.saveIfNeeded()
        guard !Task.isCancelled else { return }

        // Pass 2: Vision quality only for photos that need a "best" decided.
        let plain = features
        let first = grouper.group(plain)
        let similarGroups: [SimilarGroup] = first.groups.filter { $0.kind == SimilarGroup.Kind.similar }
        let memberIDs: [String] = similarGroups.flatMap { $0.items.map { $0.id } }
        let quality = await qualityScores(Array(memberIDs.prefix(qualityCap)))
        let final = quality.isEmpty ? first : grouper.group(plain, quality: quality)

        let seconds = Date().timeIntervalSince(started)
        let reclaimable: Int64 = final.groups.reduce(0) { $0 + $1.reclaimableBytes }
        var metrics: [String: Double] = [:]
        metrics["photos"] = Double(total)
        metrics["analyzed"] = Double(fresh)
        metrics["seconds"] = (seconds * 10).rounded() / 10
        metrics["groups"] = Double(final.groups.count)
        metrics["blurry"] = Double(final.blurry.count)
        metrics["reclaimable_mb"] = Double(reclaimable) / 1e6
        track("similar_scan_finished", ["scope": scope.rawValue], metrics)
        print("[similar] scope=\(scope.rawValue) \(metrics.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))")
        fflush(stdout)
        continuation.yield(SimilarScanProgress(
            analyzed: total, total: total, groups: final.groups, blurry: final.blurry,
            isFinished: true, seconds: seconds
        ))
    }

    private func fetchCandidates(since: Date?) -> [Candidate] {
        let options = PHFetchOptions()
        var predicates = [NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)]
        if let since { predicates.append(NSPredicate(format: "creationDate > %@", since as NSDate)) }
        options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: options)
        var out: [Candidate] = []
        out.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            // Screenshots have their own tab; they are not "photos of the same moment".
            guard !asset.mediaSubtypes.contains(.photoScreenshot) else { return }
            out.append(Candidate(asset: asset, id: asset.localIdentifier, mod: asset.modificationDate?.timeIntervalSince1970 ?? 0))
        }
        return out
    }

    private struct Analyzed: Sendable {
        let features: PhotoFeatures
        let isFreshlyAnalyzed: Bool
    }

    private func analyze(_ c: Candidate) async -> Analyzed? {
        let entry = sizes.entry(c.id) ?? LibraryScanner.measure(c.asset, id: c.id, mod: c.mod, isScreenshot: false)
        let asset = entry.asset(id: c.id)
        if let cached = store.record(c.id, mod: c.mod) {
            return Analyzed(features: PhotoFeatures(asset: asset, vector: cached.vector, blur: cached.blur,
                                                    isFavorite: c.asset.isFavorite), isFreshlyAnalyzed: false)
        }
        guard let image = await thumbnail(c.asset) else { return nil }
        guard let vector = Self.featurePrint(image) else { return nil }
        let blur = Self.blur(image)
        store.set(c.id, FeatureStore.Record(mod: c.mod, blur: blur, vector: vector))
        return Analyzed(features: PhotoFeatures(asset: asset, vector: vector, blur: blur, isFavorite: c.asset.isFavorite),
                        isFreshlyAnalyzed: true)
    }

    // MARK: - PhotoKit

    /// Local-only, fast-format 320 px image: never starts an iCloud download.
    private func thumbnail(_ asset: PHAsset) async -> CGImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        options.isSynchronous = false
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset, targetSize: CGSize(width: 320, height: 320), contentMode: .aspectFit, options: options
            ) { image, _ in
                continuation.resume(returning: image?.cgImage)
            }
        }
    }

    // MARK: - Vision

    static func featurePrint(_ image: CGImage) -> [Float]? {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil, let obs = request.results?.first else { return nil }
        let data = obs.data
        switch obs.elementType {
        case .float:
            return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self).prefix(obs.elementCount)) }
        case .double:
            return data.withUnsafeBytes { $0.bindMemory(to: Double.self).prefix(obs.elementCount).map(Float.init) }
        default:
            return nil
        }
    }

    /// Grey 0…1 at ≤ 320 px, then Crete-Roffet.
    static func blur(_ image: CGImage) -> Float {
        let scale = min(1, 320 / Double(max(image.width, image.height)))
        let w = max(2, Int(Double(image.width) * scale)), h = max(2, Int(Double(image.height) * scale))
        var pixels = [UInt8](repeating: 0, count: w * h)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return 0 }
        return BlurMetric.creteRoffet(pixels.map { Float($0) / 255 }, width: w, height: h)
    }

    /// Aesthetics (iOS 18+) and best face capture quality, for choosing the keeper.
    private func qualityScores(_ ids: [String]) async -> [String: Float] {
        guard !ids.isEmpty else { return [:] }
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var assets: [Candidate] = []
        fetch.enumerateObjects { a, _, _ in assets.append(Candidate(asset: a, id: a.localIdentifier, mod: 0)) }
        var scores: [String: Float] = [:]
        for chunk in stride(from: 0, to: assets.count, by: width).map({ Array(assets[$0..<min($0 + width, assets.count)]) }) {
            if Task.isCancelled { break }
            await withTaskGroup(of: (String, Float)?.self) { group in
                for c in chunk {
                    group.addTask { [self] in
                        guard let image = await thumbnail(c.asset) else { return nil }
                        return (c.id, Self.quality(image))
                    }
                }
                for await case let (id, score)? in group { scores[id] = score }
            }
        }
        return scores
    }

    static func quality(_ image: CGImage) -> Float {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let faces = VNDetectFaceCaptureQualityRequest()
        var requests: [VNRequest] = [faces]
        var aesthetic: VNRequest?
        if #available(iOS 18.0, *) {
            let request = VNCalculateImageAestheticsScoresRequest()
            aesthetic = request
            requests.append(request)
        }
        guard (try? handler.perform(requests)) != nil else { return 0 }
        var score: Float = 0
        if let face = faces.results?.compactMap(\.faceCaptureQuality).max() { score += face * 1.5 }
        if #available(iOS 18.0, *), let obs = aesthetic?.results?.first as? VNImageAestheticsScoresObservation {
            // overallScore is −1…1; utility images (documents, receipts) are poor keepers.
            score += obs.overallScore + (obs.isUtility ? -1 : 0)
        }
        return score
    }
}
