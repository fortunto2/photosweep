import Foundation

/// What we know about one asset without asking PhotoKit again.
struct IndexEntry: Sendable, Equatable {
    /// `PHAsset.modificationDate` (epoch seconds) when the size was read; a changed
    /// date means an edit and invalidates the entry.
    var mod: Double
    var bytes: Int64
    var isLocal: Bool
    var kind: MediaKind
    var created: Double
    var duration: Double
    var width: Int
    var height: Int
    /// `PhotoFormat.rawValue` for photos; "" for videos and for entries from a v1 index.
    var format: String = ""

    func asset(id: String) -> MediaAsset {
        MediaAsset(
            id: id,
            kind: kind,
            byteSize: bytes,
            creationDate: created > 0 ? Date(timeIntervalSince1970: created) : nil,
            duration: duration,
            pixelWidth: width,
            pixelHeight: height,
            isLocal: isLocal
        )
    }
}

/// Persistent `localIdentifier → size` index, so only new or edited assets cost a
/// `PHAssetResource` read on later launches.
///
/// AI-NOTE: plain tab-separated text, not JSON/plist: 100k rows parse in ~0.1 s, and a
/// corrupt or old-format file is simply discarded (it is a cache). Thread-safe via a lock
/// because the scanner fills it from several GCD workers at once.
final class SizeIndex: @unchecked Sendable {
    private static let header = "photosweep-size-index v2"
    private static let headerV1 = "photosweep-size-index v1" // no format column; still read
    private let url: URL?
    private let lock = NSLock()
    private var entries: [String: IndexEntry] = [:]
    private var dirty = false

    /// `url == nil` → in-memory only (tests).
    init(url: URL?) {
        self.url = url
    }

    static var defaultURL: URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("size-index.tsv")
    }

    var count: Int { lock.withLock { entries.count } }

    func entry(_ id: String) -> IndexEntry? { lock.withLock { entries[id] } }

    func set(_ batch: [(String, IndexEntry)]) {
        guard !batch.isEmpty else { return }
        lock.withLock {
            for (id, entry) in batch { entries[id] = entry }
            dirty = true
        }
    }

    func remove(_ ids: some Sequence<String>) {
        lock.withLock {
            for id in ids where entries.removeValue(forKey: id) != nil { dirty = true }
        }
    }

    /// Drops entries for assets that no longer exist in the library.
    func retain(only ids: Set<String>) {
        lock.withLock {
            let before = entries.count
            entries = entries.filter { ids.contains($0.key) }
            if entries.count != before { dirty = true }
        }
    }

    func assets(format: PhotoFormat) -> [MediaAsset] {
        lock.withLock {
            entries.compactMap { $0.value.format == format.rawValue ? $0.value.asset(id: $0.key) : nil }
        }
    }

    /// Photos (not screenshots, not videos) by format, from what the index holds.
    func formatMix() -> FormatMix {
        lock.withLock {
            var mix = FormatMix()
            for e in entries.values where e.kind == .photo {
                guard let f = PhotoFormat(rawValue: e.format) else { continue }
                mix.add(f, bytes: e.bytes)
            }
            return mix
        }
    }

    func storageSplit() -> StorageSplit {
        lock.withLock {
            var split = StorageSplit()
            for e in entries.values {
                if e.isLocal {
                    split.onPhone.count += 1; split.onPhone.bytes += e.bytes
                } else {
                    split.cloudOnly.count += 1; split.cloudOnly.bytes += e.bytes
                }
            }
            return split
        }
    }

    func assets(of kind: MediaKind) -> [MediaAsset] {
        lock.withLock { entries.compactMap { $0.value.kind == kind ? $0.value.asset(id: $0.key) : nil } }
    }

    /// Byte and item totals per bucket, from whatever the index holds.
    func breakdown() -> LibraryBreakdown {
        lock.withLock {
            var result = LibraryBreakdown()
            for entry in entries.values { result.add(entry.kind, bytes: entry.bytes) }
            return result
        }
    }

    // MARK: - Disk

    func load() {
        guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true)[...]
        guard let first = lines.first.map(String.init), first == Self.header || first == Self.headerV1
        else { return }
        lines = lines.dropFirst()
        var loaded: [String: IndexEntry] = [:]
        loaded.reserveCapacity(lines.count)
        for line in lines {
            let f = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard f.count == 9 || f.count == 10,
                  let mod = Double(f[1]), let bytes = Int64(f[2]),
                  let kind = MediaKind(rawValue: String(f[4])),
                  let created = Double(f[5]), let duration = Double(f[6]),
                  let w = Int(f[7]), let h = Int(f[8]) else { continue }
            loaded[String(f[0])] = IndexEntry(
                mod: mod, bytes: bytes, isLocal: f[3] == "1", kind: kind,
                created: created, duration: duration, width: w, height: h,
                format: f.count == 10 ? String(f[9]) : ""
            )
        }
        lock.withLock {
            // Entries written by a scan that started before load finished win.
            entries.merge(loaded) { current, _ in current }
        }
    }

    func saveIfNeeded() {
        guard let url else { return }
        let snapshot: [String: IndexEntry]? = lock.withLock {
            guard dirty else { return nil }
            dirty = false
            return entries
        }
        guard let snapshot else { return }
        var out = Self.header + "\n"
        out.reserveCapacity(snapshot.count * 96)
        for (id, e) in snapshot {
            out += "\(id)\t\(e.mod)\t\(e.bytes)\t\(e.isLocal ? 1 : 0)\t\(e.kind.rawValue)\t"
            out += "\(e.created)\t\(e.duration)\t\(e.width)\t\(e.height)\t\(e.format)\n"
        }
        try? out.write(to: url, atomically: true, encoding: .utf8)
    }
}
