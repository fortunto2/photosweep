import SwiftUI

struct DashboardView: View {
    @State private var vm: DashboardViewModel

    init(library: PhotoLibraryServiceProtocol, storage: StorageServiceProtocol) {
        _vm = State(initialValue: DashboardViewModel(storage: storage, library: library))
    }

    var body: some View {
        NavigationStack {
            List {
                if let info = vm.storageInfo {
                    Section("Device storage") {
                        StorageBar(info: info)
                            .padding(.vertical, 4)
                    }
                }

                if let breakdown = vm.breakdown {
                    Section("Your photo library") {
                        row("Videos", bytes: breakdown.videoBytes, count: breakdown.videoCount, symbol: "video.fill")
                        row("Screenshots", bytes: breakdown.screenshotBytes, count: breakdown.screenshotCount, symbol: "camera.viewfinder")
                        row("Other photos", bytes: breakdown.otherPhotoBytes, count: breakdown.otherPhotoCount, symbol: "photo.fill")
                    }
                    Section {
                        Text("PhotoSweep can only free space held by your photo library. “System Data” and other apps’ caches are managed by iOS and can’t be cleared by any app — see the Apps tab for how to clear those manually.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("PhotoSweep")
            .overlay {
                if vm.isLoading && vm.breakdown == nil {
                    ProgressView("Scanning library…")
                }
            }
            .refreshable { await vm.load() }
            .task { await vm.load() }
        }
    }

    private func row(_ title: String, bytes: Int64, count: Int, symbol: String) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            VStack(alignment: .trailing) {
                Text(Format.bytes(bytes)).font(.body.weight(.semibold))
                Text("\(count) items").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
