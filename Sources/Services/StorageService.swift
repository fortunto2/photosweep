import Foundation

struct StorageService: StorageServiceProtocol {
    func currentStorage() throws -> StorageInfo {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let values = try url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ])
        let total = Int64(values.volumeTotalCapacity ?? 0)
        // `volumeAvailableCapacityForImportantUsage` is already Int64 (bytes).
        let available = values.volumeAvailableCapacityForImportantUsage ?? 0
        return StorageInfo(totalCapacity: total, availableCapacity: available)
    }
}
