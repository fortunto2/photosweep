import Foundation

enum Format {
    /// Human byte count, e.g. "1.2 GB".
    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    /// Video duration "m:ss", or "" for stills.
    static func duration(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// "17 Jul 2026 at 14:32", localized. "Unknown date" if missing.
    static func date(_ value: Date?) -> String {
        guard let value else { return "Unknown date" }
        return value.formatted(date: .abbreviated, time: .shortened)
    }
}
