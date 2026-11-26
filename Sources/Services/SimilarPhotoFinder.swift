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
        let pass1 = Date().timeIntervalSince(started)
        var cameraReads = 0

        // Pass 3 (before choosing the best, since it changes the groups): which phone took
        // each grouped photo. Cached; iCloud heads only on Wi-Fi.
        let byID = Dictionary(candidates.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var plain = features
        var current = grouper.group(plain)
        // Counters already keep two phones apart unless they happen to be close; only groups
        // whose counters fall into more than one run need EXIF.
        let featureByID = Dictionary(plain.map { ($0.asset.id, $0) }, uniquingKeysWith: { a, _ in a })
        let suspect = current.groups.filter { g in
            PhotoGrouper.needsCameraCheck(g.items.compactMap { featureByID[$0.id] })
        }
        let unknown = suspect.flatMap { $0.items.map(\.id) }.filter { featureByID[$0]?.camera == nil }
        cameraReads = unknown.count
        let pass3Start = Date()
        if !unknown.isEmpty {
            let network = await CameraReader.onUnmeteredNetwork()
            var found: [String: String] = [:]
            var done = 0
            continuation.yield(SimilarScanProgress(
                stage: .checkingCameras(done: 0, of: unknown.count), analyzed: total, total: total,
                groups: current.groups, blurry: current.blurry, isFinished: false, seconds: Date().timeIntervalSince(started)
            ))
            await withTaskGroup(of: (String, String?).self) { group in
                var next = 0
                func add() {
                    guard next < unknown.count, let c = byID[unknown[next]] else { next += 1; return }
                    next += 1
                    group.addTask { (c.id, await CameraReader.model(of: c.asset, network: network)) }
                }
                for _ in 0..<6 { add() }
                while let (id, model) = await group.next() {
                    done += 1
                    if let model, let c = byID[id] {
                        found[id] = model
                        store.update(c.id) { $0.camera = model }
                    }
                    if done % 200 == 0 || done == unknown.count {
                        plain = plain.map { f in
                            guard let m = found[f.asset.id] else { return f }
                            var f = f
                            f.camera = m
                            return f
                        }
                        found.removeAll()
                        current = grouper.group(plain)
                        store.saveIfNeeded()
                        continuation.yield(SimilarScanProgress(
                            stage: .checkingCameras(done: done, of: unknown.count), analyzed: total, total: total,
                            groups: current.groups, blurry: current.blurry, isFinished: false,
                            seconds: Date().timeIntervalSince(started)
                        ))
                    }
                    if !Task.isCancelled { add() }
                }
            }
            store.saveIfNeeded()
        }
        guard !Task.isCancelled else { return }

        let pass3 = Date().timeIntervalSince(pass3Start)
        let pass2Start = Date()
        // Pass 2: Vision quality only for photos that need a "best" decided (cached).
        let memberIDs: [String] = current.groups.filter { $0.kind == SimilarGroup.Kind.similar }
            .flatMap { $0.items.map { $0.id } }
        let quality = await qualityScores(memberIDs, byID: byID)
        let final = quality.isEmpty ? current : grouper.group(plain, quality: quality)

        let seconds = Date().timeIntervalSince(started)
        let reclaimable: Int64 = final.groups.reduce(0) { $0 + $1.reclaimableBytes }
        var metrics: [String: Double] = [:]
        metrics["photos"] = Double(total)
        metrics["analyzed"] = Double(fresh)
        metrics["seconds"] = (seconds * 10).rounded() / 10
        metrics["groups"] = Double(final.groups.count)
        metrics["blurry"] = Double(final.blurry.count)
        metrics["reclaimable_mb"] = Double(reclaimable) / 1e6
        metrics["camera_reads"] = Double(cameraReads)
        metrics["s_compare"] = (pass1 * 10).rounded() / 10
        metrics["s_cameras"] = (pass3 * 10).rounded() / 10
        metrics["s_quality"] = (Date().timeIntervalSince(pass2Start) * 10).rounded() / 10
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
        if var cached = store.record(c.id, mod: c.mod) {
            if cached.counter == -2 {
                cached.counter = Self.counter(of: c.asset)
                let value = cached.counter
                store.update(c.id) { $0.counter = value }
            }
            return Analyzed(features: PhotoFeatures(asset: asset, vector: cached.vector, blur: cached.blur,
                                                    isFavorite: c.asset.isFavorite, camera: cached.camera,
                                                    counter: cached.counter >= 0 ? cached.counter : nil),
                            isFreshlyAnalyzed: false)
        }
        guard let image = await thumbnail(c.asset) else { return nil }
        guard let vector = Self.featurePrint(image) else { return nil }
        let blur = Self.blur(image)
        let counter = Self.counter(of: c.asset)
        store.set(c.id, FeatureStore.Record(mod: c.mod, blur: blur, vector: vector, counter: counter))
        return Analyzed(features: PhotoFeatures(asset: asset, vector: vector, blur: blur, isFavorite: c.asset.isFavorite,
                                                counter: counter >= 0 ? counter : nil),
                        isFreshlyAnalyzed: true)
    }

    // MARK: - PhotoKit

    /// Shot counter from the original file name: a local database read, no file access.
    private static func counter(of asset: PHAsset) -> Int {
        let name = PHAssetResource.assetResources(for: asset).first?.originalFilename ?? ""
        return PhotoGrouper.counter(of: name) ?? -1
    }

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
    /// Cached per photo; at most `qualityCap` fresh reads per scan.
    private func qualityScores(_ ids: [String], byID: [String: Candidate]) async -> [String: Float] {
        var scores: [String: Float] = [:]
        var missing: [Candidate] = []
        for id in ids {
            guard let c = byID[id] else { continue }
            if let q = store.record(c.id, mod: c.mod)?.quality { scores[id] = q } else { missing.append(c) }
        }
        missing = Array(missing.prefix(qualityCap))
        for start in stride(from: 0, to: missing.count, by: width) {
            if Task.isCancelled { break }
            let chunk = missing[start..<min(start + width, missing.count)]
            await withTaskGroup(of: (String, Float)?.self) { group in
                for c in chunk {
                    group.addTask { [self] in
                        guard let image = await thumbnail(c.asset) else { return nil }
                        return (c.id, Self.quality(image))
                    }
                }
                for await case let (id, score)? in group {
                    scores[id] = score
                    store.update(id) { $0.quality = score }
                }
            }
        }
        store.saveIfNeeded()
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
