import Foundation
import ImageIO
import Network
import Photos

/// Reads the camera model (EXIF TIFF Model) of a photo from the head of its file.
///
/// Ported from life2film `CameraBook.photoModel` (25 Nov 2026): PhotoKit cannot tell the
/// Personal and Shared halves of a library apart, but every photo names the phone that took
/// it, and two people's phones are two cameras. Local files are read with the network off;
/// a photo only in iCloud gives its model from its first 64 KB (~1 s, measured there), and
/// only on an unmetered network.
enum CameraReader {
    /// "" when the file names no camera; nil when it could not be read.
    static func model(of asset: PHAsset, network: Bool) async -> String? {
        guard let resource = PHAssetResource.assetResources(for: asset)
            .first(where: { $0.type == .photo || $0.type == .fullSizePhoto }) else { return nil }
        if let local = await head(resource, network: false, bytes: 256 * 1024) { return local }
        guard network else { return nil }
        return await head(resource, network: true, bytes: 64 * 1024)
    }

    private static func head(_ resource: PHAssetResource, network: Bool, bytes: Int) async -> String? {
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = network
        let collector = HeadCollector(limit: bytes)
        let manager = PHAssetResourceManager.default()
        let ok = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let once = Once(continuation)
            let id = manager.requestData(for: resource, options: options) { chunk in
                if collector.append(chunk) { once.resume(true) }
            } completionHandler: { error in
                once.resume(error == nil || collector.size > 0)
            }
            collector.request = id
            // A photo that has not answered in 15 s stays unknown (life2film's deadline).
            DispatchQueue.global().asyncAfter(deadline: .now() + 15) { once.resume(false) }
        }
        if let id = collector.request { manager.cancelDataRequest(id) }
        guard ok, collector.size > 0 else { return nil }
        guard let source = CGImageSourceCreateWithData(collector.data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] else { return "" }
        return tiff[kCGImagePropertyTIFFModel] as? String ?? ""
    }

    static func onUnmeteredNetwork() async -> Bool {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let once = Once(continuation)
            monitor.pathUpdateHandler = { path in
                monitor.cancel()
                once.resume(path.status == .satisfied && !path.isExpensive && !path.isConstrained)
            }
            monitor.start(queue: DispatchQueue(label: "photosweep.camera-reader.network"))
        }
    }

    /// Resumes a continuation exactly once, whichever side (data, completion, deadline) wins.
    private final class Once<T: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<T, Never>?
        init(_ continuation: CheckedContinuation<T, Never>) { self.continuation = continuation }
        func resume(_ value: T) {
            let c: CheckedContinuation<T, Never>? = lock.withLock {
                defer { continuation = nil }
                return continuation
            }
            c?.resume(returning: value)
        }
    }

    private final class HeadCollector: @unchecked Sendable {
        private let lock = NSLock()
        let limit: Int
        private var buffer = Data()
        var request: PHAssetResourceDataRequestID?
        init(limit: Int) { self.limit = limit }
        var size: Int { lock.withLock { buffer.count } }
        var data: Data { lock.withLock { buffer } }
        func append(_ chunk: Data) -> Bool {
            lock.withLock {
                buffer.append(chunk)
                return buffer.count >= limit
            }
        }
    }
}
