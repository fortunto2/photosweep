import Foundation
import Photos

/// Exports photo-library assets to temp files so they can be handed to the iOS
/// share sheet (AirDrop, Save to Files, YouTube, …). `@MainActor` keeps the
/// non-Sendable PhotoKit managers on one actor; the writes are async.
///
/// AI-NOTE: exporting copies the full original to a temp file — needs free space
/// equal to the file size. On a nearly-full device a huge video export can fail;
/// the caller surfaces that. We wipe the temp dir before each batch so copies
/// don't accumulate.
@MainActor
enum AssetExporter {
    private static var exportDir: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("PhotoSweepExport", isDirectory: true)
    }

    /// Writes each asset's original to a temp file; returns the file URLs (skips any
    /// that fail). iCloud-offloaded originals are downloaded first.
    static func export(ids: [String]) async -> [URL] {
        try? FileManager.default.removeItem(at: exportDir)
        var urls: [URL] = []
        for id in ids {
            if let url = await export(id: id) { urls.append(url) }
        }
        return urls
    }

    static func export(id: String) async -> URL? {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        guard let asset = fetch.firstObject else { return nil }
        let resources = PHAssetResource.assetResources(for: asset)
        let resource = resources.first { $0.type == .video || $0.type == .photo } ?? resources.first
        guard let resource else { return nil }

        // Per-asset subfolder avoids collisions when two originals share a filename.
        let safeID = id.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
        let dir = exportDir.appendingPathComponent(safeID, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(resource.originalFilename)
        try? FileManager.default.removeItem(at: dest)

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true

        return await withCheckedContinuation { continuation in
            PHAssetResourceManager.default().writeData(for: resource, toFile: dest, options: options) { error in
                continuation.resume(returning: error == nil ? dest : nil)
            }
        }
    }
}
