import Foundation

/// On-disk cache of Vision feature prints + blur, keyed by asset id and modification
/// date, so a second duplicate scan only analyzes photos added or edited since.
///
/// AI-NOTE: vectors are stored as Float16 (768 dims → 1.5 KB/photo, ~12 MB per year of
/// shooting). Binary, versioned by a magic header; anything unreadable is dropped — it
/// is a cache. Next use: "similar to this photo" and cross-year duplicates.
final class FeatureStore: @unchecked Sendable {
    struct Record: Sendable {
        var mod: Double
        var blur: Float
        var vector: [Float]
        /// Vision keeper score (`SimilarPhotoFinder.quality`); nil until a group needed it.
        var quality: Float?
        /// EXIF camera model; "" = the file names none; nil = not read yet.
        var camera: String?
        /// The phone's shot counter from `IMG_1234.HEIC`; -1 = no counter, -2 = not read yet.
        var counter: Int = -2
    }

    private static let magicV2: UInt32 = 0x5053_4632 // "PSF2" (no counter), still readable
    private static let magic: UInt32 = 0x5053_4633 // "PSF3"
    private let url: URL?
    private let lock = NSLock()
    private var records: [String: Record] = [:]
    private var loaded = false
    private var dirty = false

    init(url: URL?) { self.url = url }

    static var defaultURL: URL? {
        SizeIndex.defaultURL?.deletingLastPathComponent().appendingPathComponent("features.bin")
    }

    func record(_ id: String, mod: Double) -> Record? {
        lock.withLock {
            guard let r = records[id], r.mod == mod else { return nil }
            return r
        }
    }

    func set(_ id: String, _ record: Record) {
        lock.withLock {
            records[id] = record
            dirty = true
        }
    }

    /// Updates fields of an existing record (quality / camera found later).
    func update(_ id: String, _ change: (inout Record) -> Void) {
        lock.withLock {
            guard var r = records[id] else { return }
            change(&r)
            records[id] = r
            dirty = true
        }
    }

    func loadIfNeeded() {
        let shouldLoad: Bool = lock.withLock {
            defer { loaded = true }
            return !loaded
        }
        guard shouldLoad, let url, let data = try? Data(contentsOf: url) else { return }
        var reader = Reader(data: data)
        let version = reader.read(UInt32.self)
        guard version == Self.magic || version == Self.magicV2, let n = reader.read(UInt32.self) else { return }
        let hasCounter = version == Self.magic
        var out: [String: Record] = [:]
        out.reserveCapacity(Int(n))
        for _ in 0..<n {
            guard let idLen = reader.read(UInt16.self), let id = reader.string(Int(idLen)),
                  let mod = reader.read(Double.self), let blur = reader.read(Float.self),
                  let dims = reader.read(UInt16.self), let vec = reader.halfs(Int(dims)),
                  let quality = reader.read(Float.self), let camLen = reader.read(Int16.self) else { break }
            var camera: String?
            if camLen >= 0 {
                guard let name = reader.string(Int(camLen)) else { break }
                camera = name
            }
            var counter = -2
            if hasCounter {
                guard let c = reader.read(Int32.self) else { break }
                counter = Int(c)
            }
            out[id] = Record(mod: mod, blur: blur, vector: vec, quality: quality.isNaN ? nil : quality,
                             camera: camera, counter: counter)
        }
        lock.withLock { records.merge(out) { current, _ in current } }
    }

    func saveIfNeeded() {
        guard let url else { return }
        let snapshot: [String: Record]? = lock.withLock {
            guard dirty else { return nil }
            dirty = false
            return records
        }
        guard let snapshot else { return }
        var data = Data()
        data.reserveCapacity(snapshot.count * 1_600)
        func put<T>(_ value: T) { withUnsafeBytes(of: value) { data.append(contentsOf: $0) } }
        put(Self.magic)
        put(UInt32(snapshot.count))
        for (id, r) in snapshot {
            let idBytes = Array(id.utf8)
            put(UInt16(idBytes.count))
            data.append(contentsOf: idBytes)
            put(r.mod)
            put(r.blur)
            put(UInt16(r.vector.count))
            for v in r.vector { put(Float16(v)) }
            put(r.quality ?? .nan)
            if let camera = r.camera {
                let bytes = Array(camera.utf8.prefix(200))
                put(Int16(bytes.count))
                data.append(contentsOf: bytes)
            } else {
                put(Int16(-1))
            }
            put(Int32(r.counter))
        }
        try? data.write(to: url, options: .atomic)
    }

    private struct Reader {
        let data: Data
        var offset = 0

        mutating func read<T>(_: T.Type) -> T? {
            let size = MemoryLayout<T>.size
            guard offset + size <= data.count else { return nil }
            defer { offset += size }
            return data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: T.self) }
        }

        mutating func string(_ length: Int) -> String? {
            guard offset + length <= data.count else { return nil }
            defer { offset += length }
            return String(decoding: data[data.startIndex + offset ..< data.startIndex + offset + length], as: UTF8.self)
        }

        mutating func halfs(_ count: Int) -> [Float]? {
            var out = [Float](repeating: 0, count: count)
            for i in 0..<count {
                guard let h = read(Float16.self) else { return nil }
                out[i] = Float(h)
            }
            return out
        }
    }
}
