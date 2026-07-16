import AVKit
import Photos
import SwiftUI

/// Full-screen preview so you can see what a clip/screenshot actually is before
/// deleting it. Videos play inline (streamed from iCloud if offloaded) — there is
/// no public API to open a specific asset in the Photos app, so we play it here.
struct MediaPreviewView: View {
    let asset: MediaAsset
    /// Deletes this asset (supplied by the list); preview dismisses afterwards.
    var onDelete: (() async -> Void)?
    @Environment(\.dismiss) private var dismiss

    @State private var player: AVPlayer?
    @State private var image: UIImage?
    @State private var loading = true
    @State private var sharePayload: SharePayload?
    @State private var preparingShare = false
    @State private var deleting = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                media
                metadata
                actions
            }
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $sharePayload) { ShareSheet(items: $0.urls) }
        }
        .task { await load() }
        .onDisappear { player?.pause() }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button {
                preparingShare = true
                Task {
                    let urls = await AssetExporter.export(ids: [asset.id])
                    preparingShare = false
                    if !urls.isEmpty { sharePayload = SharePayload(urls: urls) }
                }
            } label: {
                Label(preparingShare ? "Preparing…" : "Share", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(preparingShare || deleting)

            if onDelete != nil {
                Button(role: .destructive) {
                    deleting = true
                    Task {
                        await onDelete?()
                        dismiss()      // ← fixes preview lingering after delete
                    }
                } label: {
                    Label(deleting ? "Deleting…" : "Delete", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(deleting || preparingShare)
            }
        }
        .padding()
        .background(.bar)
    }

    @ViewBuilder
    private var media: some View {
        ZStack {
            Color.black
            if asset.kind == .video, let player {
                VideoPlayer(player: player)
                    .onAppear { player.play() }
            } else if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else if loading {
                ProgressView(asset.isLocal ? "Loading…" : "Streaming from iCloud…")
                    .tint(.white)
                    .foregroundStyle(.white)
            } else {
                ContentUnavailableView("Can’t preview", systemImage: "exclamationmark.triangle")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(Format.date(asset.creationDate), systemImage: "calendar")
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 16) {
                meta(asset.isLocal ? "iphone" : "icloud", asset.isLocal ? "On device" : "In iCloud")
                meta("externaldrive", Format.bytes(asset.byteSize))
                if asset.kind == .video, !Format.duration(asset.duration).isEmpty {
                    meta("clock", Format.duration(asset.duration))
                }
                if asset.pixelWidth > 0 {
                    meta("aspectratio", "\(asset.pixelWidth)×\(asset.pixelHeight)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.bar)
    }

    private func meta(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol).labelStyle(.titleAndIcon)
    }

    private func load() async {
        loading = true
        defer { loading = false }
        if asset.kind == .video {
            player = await MediaPreviewLoader.playerItem(for: asset.id).map(AVPlayer.init(playerItem:))
        } else {
            image = await ThumbnailProvider.shared.image(
                for: asset.id,
                size: CGSize(width: 1400, height: 1400)
            )
        }
    }
}

/// Builds an `AVPlayerItem` straight from a `PHAsset` — no temp-file export.
/// `@MainActor` so the non-Sendable `AVPlayerItem` never crosses an actor boundary.
@MainActor
enum MediaPreviewLoader {
    static func playerItem(for id: String) async -> AVPlayerItem? {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        guard let asset = fetch.firstObject else { return nil }
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true   // stream offloaded originals from iCloud
        options.deliveryMode = .automatic
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
                continuation.resume(returning: item)
            }
        }
    }
}
