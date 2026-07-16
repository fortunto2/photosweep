import SwiftUI

/// Horizontal used/free capacity bar.
struct StorageBar: View {
    let info: StorageInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(.tint)
                        .frame(width: max(4, geo.size.width * info.usedFraction))
                }
            }
            .frame(height: 14)

            HStack {
                Text("\(Format.bytes(info.usedCapacity)) used")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Format.bytes(info.availableCapacity)) free")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
