import Foundation

/// How a photo was stored by the camera — the reason one shot is 3 MB and another 80 MB.
enum PhotoFormat: String, CaseIterable, Sendable {
    case raw          // Apple ProRAW / DNG, ~25–80 MB
    case max48        // HEIF/JPEG at 48 MP ("Resolution Control"), ~10–20 MB
    case heif         // the default, ~2–4 MB
    case jpeg         // "Most Compatible"
    case other        // PNG, edits, imports

    var title: String {
        switch self {
        case .raw: "RAW (ProRAW)"
        case .max48: "48 MP"
        case .heif: "HEIF"
        case .jpeg: "JPEG"
        case .other: "Other"
        }
    }

    /// From the primary photo resource's UTI and the pixel size.
    static func classify(uti: String, width: Int, height: Int) -> PhotoFormat {
        let u = uti.lowercased()
        if u.contains("raw-image") || u.contains("dng") { return .raw }
        if u.isEmpty { return .other }
        let isHEIF = u.contains("heic") || u.contains("heif")
        let isJPEG = u.contains("jpeg") || u.contains("jpg")
        guard isHEIF || isJPEG else { return .other }
        if width * height >= 40_000_000 { return .max48 }
        return isHEIF ? .heif : .jpeg
    }
}

/// Counts and bytes per format, for the latest shots and for the whole library.
struct FormatMix: Sendable, Equatable {
    struct Bucket: Sendable, Equatable {
        var count = 0
        var bytes: Int64 = 0
    }

    var buckets: [PhotoFormat: Bucket] = [:]
    /// Live Photos among these, and the bytes of their video halves.
    var live = Bucket()
    /// Edited photos, and the bytes of the rendered copy kept next to the original.
    var edited = Bucket()
    var total: Int { buckets.values.reduce(0) { $0 + $1.count } }

    mutating func add(_ format: PhotoFormat, bytes: Int64) {
        buckets[format, default: Bucket()].count += 1
        buckets[format, default: Bucket()].bytes += bytes
    }

    func share(_ format: PhotoFormat) -> Double {
        total > 0 ? Double(buckets[format]?.count ?? 0) / Double(total) : 0
    }

    func averageBytes(_ format: PhotoFormat) -> Int64 {
        guard let b = buckets[format], b.count > 0 else { return 0 }
        return b.bytes / Int64(b.count)
    }

    /// Live Photos are the heavy setting when most recent shots are Live and the video half
    /// is a real share of the bytes.
    var liveIsHeavy: Bool {
        total > 0 && Double(live.count) / Double(total) >= 0.5 && live.count > 0
            && live.bytes / Int64(live.count) >= 1_500_000
    }

    /// The camera setting the latest shots point at, if it costs space: RAW first, then 48 MP.
    /// Needs at least a fifth of recent photos in that format, so one RAW test shot is not a nag.
    var heavySetting: PhotoFormat? {
        for f in [PhotoFormat.raw, .max48] where share(f) >= 0.2 { return f }
        return nil
    }
}
