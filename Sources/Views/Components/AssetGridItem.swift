import SwiftUI

/// One selectable thumbnail cell with a size badge.
struct AssetGridItem: View {
    let asset: MediaAsset
    let isSelected: Bool

    @State private var thumbnail: UIImage?

    private let side: CGFloat = 110

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle().fill(.quaternary)
                        .overlay { ProgressView() }
                }
            }
            .frame(width: side, height: side)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Duration badge (video, top-left).
            if asset.kind == .video, case let dur = Format.duration(asset.duration), !dur.isEmpty {
                HStack(spacing: 3) {
                    Image(systemName: "play.fill").font(.system(size: 7))
                    Text(dur)
                }
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(.black.opacity(0.55), in: Capsule())
                .foregroundStyle(.white)
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            // Size + local/cloud badge (bottom-left).
            HStack(spacing: 4) {
                Image(systemName: asset.isLocal ? "iphone" : "icloud")
                    .font(.system(size: 9))
                    .foregroundStyle(asset.isLocal ? .white : Color.cyan)
                Text(Format.bytes(asset.byteSize))
            }
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(.black.opacity(0.55), in: Capsule())
            .foregroundStyle(.white)
            .padding(6)

            // Selection check.
            if isSelected {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.tint, lineWidth: 3)
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white, .tint)
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .frame(width: side, height: side)
        .task(id: asset.id) {
            thumbnail = await ThumbnailProvider.shared.image(
                for: asset.id,
                size: CGSize(width: side * 2, height: side * 2)
            )
        }
    }
}
