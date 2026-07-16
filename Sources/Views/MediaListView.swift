import SwiftUI

struct MediaListView: View {
    @State private var vm: MediaCleanupViewModel

    init(filter: MediaFilter, library: PhotoLibraryServiceProtocol) {
        _vm = State(initialValue: MediaCleanupViewModel(filter: filter, library: library))
    }

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 8)]

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(vm.filter.title)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        if !vm.assets.isEmpty {
                            Menu {
                                Picker("Sort", selection: $vm.sortMode) {
                                    ForEach(SortMode.allCases, id: \.self) { mode in
                                        Text(mode.rawValue).tag(mode)
                                    }
                                }
                            } label: {
                                Label("Sort: \(vm.sortMode.rawValue)", systemImage: "arrow.up.arrow.down")
                            }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        if !vm.assets.isEmpty {
                            Button(vm.allSelected ? "Deselect All" : "Select All") {
                                vm.allSelected ? vm.clearSelection() : vm.selectAll()
                            }
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) { deleteBar }
                .task { await vm.load() }
                .refreshable { await vm.load() }
                .alert("Error", isPresented: Binding(
                    get: { vm.errorMessage != nil },
                    set: { if !$0 { vm.errorMessage = nil } }
                )) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(vm.errorMessage ?? "")
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && !vm.hasAnyAssets {
            ProgressView("Scanning…")
        } else if !vm.hasAnyAssets {
            ContentUnavailableView(vm.filter.title, systemImage: vm.filter.systemImage, description: Text(vm.filter.emptyMessage))
        } else {
            ScrollView {
                if vm.filter == .largeVideos {
                    Picker("Show", selection: $vm.availability) {
                        Text("All").tag(AvailabilityFilter.all)
                        Text("📱 On device (\(vm.localCount))").tag(AvailabilityFilter.local)
                        Text("☁️ iCloud (\(vm.cloudCount))").tag(AvailabilityFilter.cloud)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 8).padding(.top, 8)

                    Label("📱 frees space on this device · ☁️ original is in iCloud (deleting frees iCloud, ~nothing here).", systemImage: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12).padding(.top, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if vm.assets.isEmpty {
                    ContentUnavailableView(
                        "Nothing here",
                        systemImage: vm.availability.systemImage,
                        description: Text("No “\(vm.availability.rawValue)” items in this list.")
                    )
                    .padding(.top, 40)
                } else {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(vm.assets) { asset in
                            AssetGridItem(asset: asset, isSelected: vm.selected.contains(asset.id))
                                .onTapGesture { vm.toggle(asset.id) }
                        }
                    }
                    .padding(8)
                }
            }
        }
    }

    @ViewBuilder
    private var deleteBar: some View {
        if !vm.selected.isEmpty {
            Button {
                Task { await vm.deleteSelected() }
            } label: {
                HStack {
                    if vm.isDeleting { ProgressView().tint(.white) }
                    Text("Delete \(vm.selected.count) · frees \(Format.bytes(vm.selectedLocalBytes)) here")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(vm.isDeleting)
            .padding()
            .background(.ultraThinMaterial)
        }
    }
}
