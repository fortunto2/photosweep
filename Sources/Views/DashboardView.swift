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
                        Text("Only the photo library can be cleaned by an app. Other apps and System Data: see Apps.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Section {
                        Toggle("Share anonymous usage counts", isOn: $countsEnabled)
                            .onChange(of: countsEnabled) { _, on in Analytics.isEnabled = on }
                    } footer: {
                        Text("Counts only, random ID. Never photos.")
                    }
                    Section {
                        Label("Deleted items wait 30 days in Recently Deleted. Empty it to free space.", systemImage: "trash")
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
