import SuperDuperAnalytics
import SwiftUI

struct DashboardView: View {
    @State private var vm: DashboardViewModel
    @State private var countsEnabled = Analytics.isEnabled
    private let library: PhotoLibraryServiceProtocol

    init(library: PhotoLibraryServiceProtocol, storage: StorageServiceProtocol) {
        self.library = library
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

                if let recent = vm.recent, let heavy = recent.heavySetting {
                    cameraBanner(recent, heavy)
                } else if let recent = vm.recent, recent.liveIsHeavy {
                    liveBanner(recent)
                }

                if let breakdown = vm.breakdown {
                    Section {
                        link(.largeVideos) {
                            row("Videos", bytes: breakdown.videoBytes, count: breakdown.videoCount, symbol: "video.fill")
                        }
                        link(.screenshots) {
                            row("Screenshots", bytes: breakdown.screenshotBytes, count: breakdown.screenshotCount,
                                symbol: "camera.viewfinder")
                        }
                        link(.photos) {
                            row("Other photos", bytes: breakdown.otherPhotoBytes, count: breakdown.otherPhotoCount,
                                symbol: "photo.fill")
                        }
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
                    if let split = vm.split, split.onPhone.count + split.cloudOnly.count > 0 { iCloudSection(split) }
                    if let formats = vm.formats, formats.total > 0 { formatSection(formats) }
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

    /// The camera is set to a heavy format right now: say what it costs and where to switch.
    private func cameraBanner(_ recent: FormatMix, _ heavy: PhotoFormat) -> some View {
        let n = recent.buckets[heavy]?.count ?? 0
        let avg = Format.bytes(recent.averageBytes(heavy))
        let path = heavy == .raw
            ? "Settings → Camera → Formats → Apple ProRAW: off"
            : "Settings → Camera → Formats → Resolution Control: 12 or 24 MP"
        return Section {
            VStack(alignment: .leading, spacing: 6) {
                Label(heavy == .raw ? "Your camera shoots RAW" : "Your camera shoots 48 MP",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.headline).foregroundStyle(.orange)
                Text("\(n) of your last \(recent.total) photos, ~\(avg) each. HEIF is ~3 MB.")
                    .font(.subheadline)
                Text(path).font(.footnote.monospaced()).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            if heavy == .raw {
                NavigationLink {
                    MediaListView(filter: .format(.raw), library: library, ownsStack: false)
                } label: {
                    Label("Review RAW photos", systemImage: "camera.aperture")
                }
            }
        }
    }

    private func liveBanner(_ recent: FormatMix) -> some View {
        let all = recent.buckets.values.reduce(Int64(0)) { $0 + $1.bytes }
        let perLive = Format.bytes(recent.live.bytes / Int64(max(1, recent.live.count)))
        let share = all > 0 ? Int(Double(recent.live.bytes) / Double(all) * 100) : 0
        return Section {
            VStack(alignment: .leading, spacing: 6) {
                Label("Live Photos add \(perLive) per shot", systemImage: "livephoto")
                    .font(.headline).foregroundStyle(.orange)
                Text("\(recent.live.count) of your last \(recent.total) photos are Live: \(share)% of their size is the video.")
                    .font(.subheadline)
                Text("Camera: tap ◎ to turn Live off. Keep it off: Settings → Camera → Preserve Settings → Live Photo.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private func iCloudSection(_ split: StorageSplit) -> some View {
        Section {
            link(.everything(.local)) { HStack {
                Label("Originals on iPhone", systemImage: "iphone")
                Spacer()
                VStack(alignment: .trailing) {
                    Text(Format.bytes(split.onPhone.bytes)).font(.body.weight(.semibold))
                    Text("\(split.onPhone.count.formatted()) items").font(.caption).foregroundStyle(.secondary)
                }
            } }
            link(.everything(.cloud)) { HStack {
                Label("Only in iCloud", systemImage: "icloud")
                Spacer()
                VStack(alignment: .trailing) {
                    Text(Format.bytes(split.cloudOnly.bytes)).font(.body.weight(.semibold))
                    Text("\(split.cloudOnly.count.formatted()) items · uploaded").font(.caption).foregroundStyle(.secondary)
                }
            } }
        } header: {
            Text("iPhone vs iCloud")
        } footer: {
            Text("If Photos says everything is synced, the originals on iPhone are also in iCloud. "
                 + "With Settings → Photos → Optimize iPhone Storage, iOS keeps them while space is free "
                 + "and swaps them for small copies by itself when it runs low. Deleting them here deletes them from iCloud too.")
        }
    }

    private func formatSection(_ mix: FormatMix) -> some View {
        Section {
            ForEach(PhotoFormat.allCases.filter { (mix.buckets[$0]?.count ?? 0) > 0 }, id: \.self) { f in
                let b = mix.buckets[f] ?? FormatMix.Bucket()
                let line = HStack {
                    Text(f.title)
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text(Format.bytes(b.bytes)).font(.body.weight(.semibold))
                        Text("\(b.count.formatted()) · ~\(Format.bytes(mix.averageBytes(f))) each")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                link(.format(f)) { line }
            }
        } header: {
            Text("Photo formats")
        } footer: {
            if !vm.sizesAreSettled || vm.progressText != nil { Text("Still reading formats…") }
        }
    }

    /// Every number on this screen opens the list behind it, biggest first.
    private func link(_ filter: MediaFilter, @ViewBuilder label: () -> some View) -> some View {
        NavigationLink { MediaListView(filter: filter, library: library, ownsStack: false) } label: { label() }
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
