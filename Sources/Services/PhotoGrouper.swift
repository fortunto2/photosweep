import Accelerate
import Foundation

/// Pure grouping logic — no PhotoKit, no Vision — so it is unit-tested with synthetic
/// vectors. Ported from PhotoSift's PhotoGrouper (the O(n²) fix: time-window buckets +
/// union-find), with Sendable float vectors instead of VNFeaturePrintObservation.
struct PhotoGrouper: Sendable {
    /// Euclidean distance between feature prints under which two shots count as the same
    /// scene. VNFeaturePrint revision 2 (iOS 17+): retakes measure ~0.2–0.45, different
    /// scenes from the same minute ~0.6+.
    // AI-NOTE: PhotoSift used 0.6 without saying which revision it tuned on; 0.45 is the
    // conservative side — a missed retake costs a few MB, a wrong group costs trust.
    var similarityThreshold: Float = 0.45
    /// Only photos taken this close together are compared (retakes, bursts).
    var windowSeconds: Double = 300
    /// Crete-Roffet blur at or above which a photo is out of focus (life2film va-features
    /// garbage.rs `OUT_OF_FOCUS`, swept on labelled frames at ~320 px).
    var blurThreshold: Float = 0.55

    struct Output: Sendable, Equatable {
        var groups: [SimilarGroup]
        var blurry: [MediaAsset]
    }

    func group(_ photos: [PhotoFeatures], quality: [String: Float] = [:]) -> Output {
        var groups = exactDuplicates(photos)
        let taken = Set(groups.flatMap { $0.items.map(\.id) })
        groups += similar(photos.filter { !taken.contains($0.asset.id) }, quality: quality)

        let grouped = Set(groups.flatMap { $0.items.map(\.id) })
        let blurry = photos
            .filter { !grouped.contains($0.asset.id) && !$0.isFavorite && $0.blur >= blurThreshold }
            .sorted { $0.blur > $1.blur }
            .map(\.asset)
        groups.sort { $0.reclaimableBytes > $1.reclaimableBytes }
        return Output(groups: groups, blurry: blurry)
    }

    // MARK: - Exact duplicates: same pixels + same bytes, any date

    private func exactDuplicates(_ photos: [PhotoFeatures]) -> [SimilarGroup] {
        var buckets: [String: [PhotoFeatures]] = [:]
        for p in photos where p.asset.byteSize > 0 {
            buckets["\(p.asset.pixelWidth)x\(p.asset.pixelHeight)/\(p.asset.byteSize)", default: []].append(p)
        }
        return buckets.values.compactMap { items in
            // Same size can still be two different photos; require the picture to agree too.
            let close = items.filter { distance($0.vector, items[0].vector) < 0.1 }
            guard close.count > 1 else { return nil }
            // Keep a favorite if there is one, else the oldest (the original).
            let best = close.first(where: \.isFavorite)
                ?? close.min { ($0.asset.creationDate ?? .distantFuture) < ($1.asset.creationDate ?? .distantFuture) }
            return makeGroup(.duplicate, close, bestID: best!.asset.id)
        }
    }

    // MARK: - Similar: time buckets + union-find

    private func similar(_ photos: [PhotoFeatures], quality: [String: Float]) -> [SimilarGroup] {
        guard photos.count > 1 else { return [] }
        var uf = UnionFind(count: photos.count)
        var buckets: [Int: [Int]] = [:]
        for (i, p) in photos.enumerated() {
            guard let t = p.asset.creationDate?.timeIntervalSince1970 else { continue }
            buckets[Int(t / windowSeconds), default: []].append(i)
        }
        for (bucket, members) in buckets {
            // Compare within the bucket and with the next one (a retake across a boundary).
            let candidates = members + (buckets[bucket + 1] ?? [])
            for a in 0..<members.count {
                let i = candidates[a]
                for b in (a + 1)..<candidates.count {
                    let j = candidates[b]
                    let dt = abs((photos[i].asset.creationDate?.timeIntervalSince1970 ?? 0)
                        - (photos[j].asset.creationDate?.timeIntervalSince1970 ?? 0))
                    guard dt <= windowSeconds else { continue }
                    if distance(photos[i].vector, photos[j].vector) < similarityThreshold { uf.union(i, j) }
                }
            }
        }
        var components: [Int: [Int]] = [:]
        for i in photos.indices { components[uf.find(i), default: []].append(i) }
        return components.values.compactMap { indices in
            guard indices.count > 1 else { return nil }
            let items = indices.map { photos[$0] }
                .sorted { ($0.asset.creationDate ?? .distantPast) < ($1.asset.creationDate ?? .distantPast) }
            let best = items.first(where: \.isFavorite) ?? items.max { score($0, quality) < score($1, quality) }!
            return makeGroup(.similar, items, bestID: best.asset.id)
        }
    }

    /// Higher = better keeper. Sharpness dominates (1 − blur); Vision quality (aesthetics,
    /// face capture) when the finder computed it for group members; resolution breaks ties.
    private func score(_ p: PhotoFeatures, _ quality: [String: Float]) -> Float {
        let sharp = 1 - min(1, p.blur)
        let pixels = Float(p.asset.pixelWidth * p.asset.pixelHeight) / 50_000_000
        return sharp * 2 + (quality[p.asset.id] ?? 0) + pixels
    }

    private func makeGroup(_ kind: SimilarGroup.Kind, _ items: [PhotoFeatures], bestID: String) -> SimilarGroup {
        SimilarGroup(
            kind: kind, items: items.map(\.asset), bestID: bestID,
            favoriteIDs: Set(items.filter(\.isFavorite).map(\.asset.id))
        )
    }

    func distance(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return .infinity }
        return sqrt(vDSP.distanceSquared(a, b))
    }
}

/// Disjoint set with path compression and union by rank (from PhotoSift).
struct UnionFind {
    private var parent: [Int]
    private var rank: [Int]

    init(count: Int) {
        parent = Array(0..<count)
        rank = Array(repeating: 0, count: count)
    }

    mutating func find(_ x: Int) -> Int {
        var root = x
        while parent[root] != root { root = parent[root] }
        var node = x
        while parent[node] != root { (node, parent[node]) = (parent[node], root) }
        return root
    }

    mutating func union(_ x: Int, _ y: Int) {
        let rx = find(x), ry = find(y)
        guard rx != ry else { return }
        if rank[rx] < rank[ry] { parent[rx] = ry } else if rank[rx] > rank[ry] { parent[ry] = rx } else {
            parent[ry] = rx
            rank[rx] += 1
        }
    }
}

/// Crete-Roffet no-reference blur, ported from life2film `va-features/src/blur.rs`:
/// 0 = sharp, 1 = flat. A ratio, so a busy street and a plain wall are comparable.
/// Expects a row-major grey image in 0…1 at roughly 320 px (where its thresholds were swept).
enum BlurMetric {
    static let taps = 9

    static func creteRoffet(_ gray: [Float], width w: Int, height h: Int) -> Float {
        guard w >= 2, h >= 2, gray.count >= w * h else { return 0 }
        let horizontal = directional(gray, step: 1, stride: w, len: w, lines: h)
        let vertical = directional(gray, step: w, stride: 1, len: h, lines: w)
        return max(horizontal, vertical) // motion blur has a direction
    }

    private static func directional(_ gray: [Float], step: Int, stride: Int, len: Int, lines: Int) -> Float {
        let half = taps / 2
        // Mirror at the edges ("d c b a | a b c d"), as the scipy measurement did.
        func reflect(_ j: Int) -> Int {
            let k = j < 0 ? -j - 1 : (j >= len ? 2 * len - j - 1 : j)
            return min(max(k, 0), len - 1)
        }
        var line = [Float](repeating: 0, count: len)
        var blurred = [Float](repeating: 0, count: len)
        var sumF = 0.0, sumV = 0.0
        for l in 0..<lines {
            let base = l * stride
            for i in 0..<len { line[i] = gray[base + i * step] }
            // Running box sum: O(len) per line instead of O(len × taps).
            var acc: Float = 0
            for k in -half...half { acc += line[reflect(k)] }
            for i in 0..<len {
                blurred[i] = acc / Float(taps)
                acc += line[reflect(i + half + 1)] - line[reflect(i - half)]
            }
            for i in 1..<len {
                let dF = Double(abs(line[i] - line[i - 1]))
                let dB = Double(abs(blurred[i] - blurred[i - 1]))
                sumF += dF
                sumV += max(0, dF - dB)
            }
        }
        guard sumF > .ulpOfOne else { return 1 } // flat frame: nothing left to lose
        return Float((sumF - sumV) / sumF)
    }
}
