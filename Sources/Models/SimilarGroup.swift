import Foundation

/// What the duplicate finder knows about one photo after analysis. Sendable: the Vision
/// feature print is copied out as plain floats, so nothing non-Sendable crosses actors.
struct PhotoFeatures: Sendable, Equatable {
    let asset: MediaAsset
    /// `VNFeaturePrintObservation` data (Euclidean distance = Vision's own `computeDistance`).
    let vector: [Float]
    /// Crete-Roffet blur, 0 = sharp … 1 = flat (`BlurMetric`, from life2film va-features).
    let blur: Float
    let isFavorite: Bool
    /// EXIF camera model when known. Two phones are two people: in an iCloud Shared
    /// Library this is the only way to keep one person's shots apart from the other's.
    var camera: String?
    /// Shot counter from the file name (`IMG_1234` → 1234); nil when the name has none.
    /// One phone numbers its shots in sequence, so far-apart counters mean two phones.
    var counter: Int?
}

/// A set of photos where keeping one is enough.
struct SimilarGroup: Identifiable, Sendable, Equatable {
    enum Kind: String, Sendable {
        /// Same pixels and same bytes: a true copy (re-saved, received twice).
        case duplicate
        /// Shot within minutes and visually near-identical (bursts, retakes).
        case similar
    }

    let kind: Kind
    let items: [MediaAsset]
    /// The one Quick Clean keeps.
    var bestID: String
    /// Favorites are never suggested for deletion.
    let favoriteIDs: Set<String>
    /// How sure we are each non-kept photo is redundant, 0…1: near-identical to the kept one
    /// (and no sharper) → 1. Quick Clean's "safest 20%" takes only the top of this.
    var confidence: [String: Float] = [:]

    var id: String { items.first?.id ?? UUID().uuidString }

    /// Everything except the best and any favorite.
    var suggestedForDeletion: [MediaAsset] {
        items.filter { $0.id != bestID && !favoriteIDs.contains($0.id) }
    }

    var reclaimableBytes: Int64 { suggestedForDeletion.reduce(0) { $0 + $1.byteSize } }
}

/// Which photos the finder looks at. Vision costs ~10 ms a photo, so "everything" on a
/// 70k library is minutes; recent ones are where the retakes are.
/// How much of the suggestion Quick Clean takes, most certain first.
enum CleanLevel: Double, CaseIterable, Sendable {
    case safest = 0.2
    case half = 0.5
    case all = 1.0

    var label: String {
        switch self {
        case .safest: "Safest 20%"
        case .half: "50%"
        case .all: "All"
        }
    }
}

enum SimilarScope: String, CaseIterable, Sendable {
    case month = "30 days"
    case year = "12 months"
    case all = "All"

    func since(now: Date = Date()) -> Date? {
        switch self {
        case .month: Calendar.current.date(byAdding: .day, value: -30, to: now)
        case .year: Calendar.current.date(byAdding: .year, value: -1, to: now)
        case .all: nil
        }
    }
}

struct SimilarScanProgress: Sendable, Equatable {
    enum Stage: Sendable, Equatable { case comparing, choosingBest, checkingCameras(done: Int, of: Int) }
    var stage: Stage = .comparing
    var analyzed: Int
    var total: Int
    var groups: [SimilarGroup]
    /// Sharpness below the blur threshold, not already in a group; blurriest first.
    var blurry: [MediaAsset]
    var isFinished: Bool
    var seconds: Double

    var fraction: Double { total > 0 ? Double(analyzed) / Double(total) : 1 }
}
