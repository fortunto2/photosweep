import Foundation

/// Photos the person chose to keep after we suggested deleting them. Remembered across
/// launches so a "no" is said once: those photos are never suggested again and their
/// group shows greyed until the person undoes it.
///
/// AI-NOTE: plain text, one asset id per line. A cache of decisions, not of data: losing
/// it only means suggestions come back, never that anything is deleted.
final class KeepStore: @unchecked Sendable {
    static let shared = KeepStore(url: SizeIndex.defaultURL?
        .deletingLastPathComponent().appendingPathComponent("kept.txt"))

    private let url: URL?
    private let lock = NSLock()
    private var ids: Set<String>

    init(url: URL?) {
        self.url = url
        let text = url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        ids = Set(text.split(separator: "\n").map(String.init))
    }

    func contains(_ id: String) -> Bool { lock.withLock { ids.contains(id) } }

    func keep(_ keep: some Sequence<String>) { change { $0.formUnion(keep) } }
    func forget(_ forget: some Sequence<String>) { change { $0.subtract(forget) } }

    private func change(_ edit: (inout Set<String>) -> Void) {
        let snapshot: Set<String> = lock.withLock {
            edit(&ids)
            return ids
        }
        guard let url else { return }
        try? snapshot.sorted().joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
