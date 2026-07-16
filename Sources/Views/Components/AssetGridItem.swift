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

            // Size / duration badge.
            HStack(spacing: 4) {
                if asset.kind == .video, !Format.duration(asset.duration).isEmpty {
                    Image(systemName: "play.fill").font(.system(size: 8))
                }
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
