import Foundation

protocol StorageServiceProtocol: Sendable {
    /// Current device volume capacity. Throws if the volume keys are unavailable.
    func currentStorage() throws -> StorageInfo
}
