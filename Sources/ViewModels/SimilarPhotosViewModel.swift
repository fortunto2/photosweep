import Foundation

@Observable
@MainActor
final class SimilarPhotosViewModel {
    private let finder: SimilarPhotoFinderProtocol
    private let library: PhotoLibraryServiceProtocol
    private let track: PhotoLibraryService.Track

    var scope: SimilarScope = .year
    /// Starts at the safest level: bulk deletion should earn trust before it takes everything.
    var cleanLevel: CleanLevel = .safest {
        didSet { applyLevel() }
    }
    var groups: [SimilarGroup] = []
    var blurry: [MediaAsset] = []
    var analyzed = 0
    var total = 0
    var isScanning = false
    var stage: SimilarScanProgress.Stage = .comparing
    var hasScanned = false
    var isDeleting = false
    var errorMessage: String?
    /// Per group: ids the person chose to delete. Starts as the suggestion (all but the best,
    /// never a favorite); tapping a photo flips it.
    var marked: [String: Set<String>] = [:]
    /// Freed by deletions in this session (shown after Quick Clean).
    var freedBytes: Int64 = 0
    private var reviewed: Set<String> = []

    init(finder: SimilarPhotoFinderProtocol, library: PhotoLibraryServiceProtocol,
         track: @escaping PhotoLibraryService.Track = { _, _, _ in }) {
        self.finder = finder
        self.library = library
        self.track = track
    }

    var fraction: Double {
        if case let .checkingCameras(done, of) = stage, of > 0 { return Double(done) / Double(of) }
        return total > 0 ? Double(analyzed) / Double(total) : 0
    }

    /// Quick Clean deletes across hundreds of groups; it waits until every grouped photo's
    /// camera is known, so a Shared Library partner's shot is never swept up in bulk.
    var quickCleanReady: Bool {
        if case .checkingCameras = stage, isScanning { return false }
        return true
    }

    var progressText: String {
        switch stage {
        case let .checkingCameras(done, of): "Checking which phone took each photo… \(done.formatted()) of \(of.formatted())"
        case .choosingBest: "Choosing the best shot of each group…"
        case .comparing: total == 0 ? "Finding photos…" : "Comparing \(analyzed.formatted()) of \(total.formatted()) photos"
        }
    }

    /// Everything Quick Clean would delete right now.
    var quickCleanIDs: [String] { groups.flatMap { Array(marked[$0.id] ?? []) } }

    var quickCleanBytes: Int64 { quickCleanAssets.reduce(0) { $0 + $1.byteSize } }

    /// What deleting frees on this iPhone; iCloud-only originals free iCloud, not the phone.
    var quickCleanLocalBytes: Int64 { quickCleanAssets.filter(\.isLocal).reduce(0) { $0 + $1.byteSize } }

    private var quickCleanAssets: [MediaAsset] {
        let ids = Set(quickCleanIDs)
        return groups.flatMap(\.items).filter { ids.contains($0.id) }
    }

    func isMarked(_ id: String, in group: SimilarGroup) -> Bool { marked[group.id]?.contains(id) ?? false }

    func toggle(_ id: String, in group: SimilarGroup) {
        var set = marked[group.id] ?? []
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
        // Never let a whole group go by accident: if everything is marked, keep the best.
        if set.count == group.items.count { set.remove(group.bestID) }
        marked[group.id] = set
        if reviewed.insert(group.id).inserted {
            track("group_reviewed", ["kind": group.kind.rawValue], ["items": Double(group.items.count)])
        }
    }

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        analyzed = 0
        total = 0
        for await step in await finder.scan(scope: scope) {
            analyzed = step.analyzed
            total = step.total
            stage = step.stage
            apply(step.groups)
            blurry = step.blurry
            if step.isFinished { hasScanned = true }
        }
    }

    /// Keeps the person's own marks for groups that survive a regroup.
    private func apply(_ fresh: [SimilarGroup]) {
        var next: [String: Set<String>] = [:]
        for group in fresh {
            let ids = Set(group.items.map(\.id))
            if let mine = marked[group.id], reviewed.contains(group.id) {
                next[group.id] = mine.intersection(ids)
            }
        }
        groups = fresh
        marked = next
        applyLevel()
    }

    /// Marks, in every group the person has not touched, the most certain `cleanLevel`
    /// share of all suggestions, ranked across the whole library.
    private func applyLevel() {
        let pool = groups.filter { !reviewed.contains($0.id) }
            .flatMap { g in g.suggestedForDeletion.map { (g.id, $0.id, g.confidence[$0.id] ?? 0) } }
            .sorted { $0.2 > $1.2 }
        let take = Int((Double(pool.count) * cleanLevel.rawValue).rounded(.up))
        var next = marked.filter { reviewed.contains($0.key) }
        for g in groups where !reviewed.contains(g.id) { next[g.id] = [] }
        for (groupID, id, _) in pool.prefix(take) { next[groupID, default: []].insert(id) }
        marked = next
    }

    /// Keep the best of every group, delete the rest (iOS asks for confirmation).
    func quickClean() async {
        await delete(quickCleanIDs, source: "quick_clean")
    }

    func deleteMarked(in group: SimilarGroup) async {
        await delete(Array(marked[group.id] ?? []), source: "group")
    }

    func deleteBlurry(_ ids: [String]) async {
        await delete(ids, source: "blurry")
    }

    private func delete(_ ids: [String], source: String) async {
        guard !ids.isEmpty else { return }
        isDeleting = true
        defer { isDeleting = false }
        let drop = Set(ids)
        let all = groups.flatMap(\.items) + blurry
        let bytes = all.filter { drop.contains($0.id) }.reduce(Int64(0)) { $0 + $1.byteSize }
        do {
            try await library.delete(assetIDs: ids)
            freedBytes += bytes
            track("photos_deleted", ["source": source], ["count": Double(ids.count), "mb": Double(bytes) / 1e6])
            blurry.removeAll { drop.contains($0.id) }
            var kept: [SimilarGroup] = []
            for group in groups {
                let rest = group.items.filter { !drop.contains($0.id) }
                guard rest.count > 1 else { continue } // one left: nothing to choose any more
                let best = rest.contains { $0.id == group.bestID } ? group.bestID : rest[0].id
                var survivor = SimilarGroup(kind: group.kind, items: rest, bestID: best,
                                            favoriteIDs: group.favoriteIDs.intersection(rest.map(\.id)))
                survivor.confidence = group.confidence
                kept.append(survivor)
            }
            groups = kept
            marked = marked.compactMapValues { $0.subtracting(drop) }
                .filter { key, _ in kept.contains { $0.id == key } }
            applyLevel()
        } catch {
            errorMessage = "Couldn't delete: \(error.localizedDescription)"
        }
    }
}
