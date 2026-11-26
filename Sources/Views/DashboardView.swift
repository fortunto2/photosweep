import SuperDuperAnalytics
import SwiftUI

struct DashboardView: View {
    @State private var vm: DashboardViewModel
    @State private var countsEnabled = Analytics.isEnabled

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
                    Section {
                        row("Videos", bytes: breakdown.videoBytes, count: breakdown.videoCount, symbol: "video.fill")
                        row("Screenshots", bytes: breakdown.screenshotBytes, count: breakdown.screenshotCount, symbol: "camera.viewfinder")
                        row("Other photos", bytes: breakdown.otherPhotoBytes, count: breakdown.otherPhotoCount, symbol: "photo.fill")
                    } header: {
                        Text("Your photo library")
                    } footer: {
                        if let text = vm.progressText {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.mini)
                                Text(text)
                            }
                        }
                    }
                    Section {
                        Text("PhotoSweep can only free space held by your photo library. “System Data” and other apps’ caches are managed by iOS and can’t be cleared by any app — see the Apps tab for how to clear those manually.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Section {
                        Toggle("Share anonymous usage counts", isOn: $countsEnabled)
                            .onChange(of: countsEnabled) { _, on in Analytics.isEnabled = on }
                    } footer: {
                        Text("Counts like “app opened” or “scan took 3 s”, with a random install ID. Never photos, names or file details.")
                    }
                    Section {
                        Label("After deleting, empty Photos → Recently Deleted to actually reclaim the space — items linger there ~30 days. See the Apps tab.", systemImage: "trash")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("PhotoSweep")
            .overlay {
                if vm.isLoading && vm.breakdown == nil {
                    ProgressView()
                }
            }
            .refreshable { await vm.load(force: true) }
            // Each visit asks the shared scan; a recent finished one is replayed, not re-run.
            .task { await vm.load() }
        }
    }

    private func row(_ title: String, bytes: Int64, count: Int, symbol: String) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            VStack(alignment: .trailing) {
                Text(Format.bytes(bytes))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(vm.sizesAreSettled ? .primary : .secondary)
                    .contentTransition(.numericText())
                Text("\(count.formatted()) items").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
