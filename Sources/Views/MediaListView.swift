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
        if vm.isLoading && vm.assets.isEmpty {
            ProgressView("Scanning…")
        } else if vm.assets.isEmpty {
            ContentUnavailableView(vm.filter.title, systemImage: vm.filter.systemImage, description: Text(vm.filter.emptyMessage))
        } else {
            ScrollView {
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

    @ViewBuilder
    private var deleteBar: some View {
        if !vm.selected.isEmpty {
            Button {
                Task { await vm.deleteSelected() }
            } label: {
                HStack {
                    if vm.isDeleting { ProgressView().tint(.white) }
                    Text("Delete \(vm.selected.count) · free \(Format.bytes(vm.selectedBytes))")
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
