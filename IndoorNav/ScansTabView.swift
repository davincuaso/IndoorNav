import SwiftUI

struct ScansTabView: View {
    @StateObject private var viewModel = ScansViewModel()
    @State private var selectedZone: MapZone?
    @State private var showingViewer = false
    @State private var colorScheme: MeshColorScheme = .height
    @State private var showWireframe = false
    @State private var showDestinations = true

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.zones.isEmpty {
                    emptyState
                } else {
                    scansList
                }
            }
            .navigationTitle("My Scans")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Section("Color Scheme") {
                            Button {
                                colorScheme = .height
                            } label: {
                                Label("Height Gradient", systemImage: colorScheme == .height ? "checkmark" : "")
                            }
                            Button {
                                colorScheme = .solid(.systemCyan)
                            } label: {
                                Label("Solid Cyan", systemImage: "circle.fill")
                            }
                            Button {
                                colorScheme = .wireframe
                            } label: {
                                Label("Wireframe", systemImage: "square.grid.3x3")
                            }
                        }

                        Section("Display Options") {
                            Toggle("Show Destinations", isOn: $showDestinations)
                            Toggle("Wireframe Mode", isOn: $showWireframe)
                        }
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                }
            }
            .sheet(item: $selectedZone) { zone in
                ScanDetailView(
                    zone: zone,
                    colorScheme: colorScheme,
                    showWireframe: showWireframe,
                    showDestinations: showDestinations
                )
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                Text("No Scans Yet")
                    .font(.headline)

                Text("Scans you create in Map mode will appear here. You can view them in 3D and see your mapped destinations.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Text("Go to the AR tab and start mapping")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private var scansList: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16)
            ], spacing: 16) {
                ForEach(viewModel.zones) { zone in
                    ScanCardView(zone: zone, hasMesh: viewModel.hasMesh(for: zone))
                        .onTapGesture {
                            HapticManager.shared.selectionChanged()
                            selectedZone = zone
                        }
                }
            }
            .padding()
        }
        .refreshable {
            viewModel.refresh()
        }
    }
}

// MARK: - Scan Card View

struct ScanCardView: View {
    let zone: MapZone
    let hasMesh: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Preview area
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
                    .aspectRatio(1.2, contentMode: .fit)

                if hasMesh {
                    Image(systemName: "cube.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.blue.gradient)
                } else {
                    VStack(spacing: 4) {
                        Image(systemName: "cube.transparent")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        Text("No 3D data")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            // Zone info
            VStack(alignment: .leading, spacing: 2) {
                Text(zone.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if zone.destinationCount > 0 {
                        Label("\(zone.destinationCount)", systemImage: "mappin")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                    if zone.waypointCount > 0 {
                        Label("\(zone.waypointCount)", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                    Spacer()
                }

                Text(zone.formattedDate)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 4)
        }
        .padding(8)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Scan Detail View

struct ScanDetailView: View {
    let zone: MapZone
    var colorScheme: MeshColorScheme
    var showWireframe: Bool
    var showDestinations: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var meshData: MeshExportData?
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                ScanViewer3D(
                    meshData: meshData,
                    zone: zone,
                    colorScheme: colorScheme,
                    showDestinations: showDestinations,
                    showWireframe: showWireframe
                )
                .ignoresSafeArea(edges: .bottom)

                if isLoading {
                    ProgressView("Loading scan...")
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                if let error = loadError {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundStyle(.orange)

                        Text("Unable to Load")
                            .font(.headline)

                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }

                // Info overlay
                VStack {
                    Spacer()
                    scanInfoBar
                }
            }
            .navigationTitle(zone.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            // Export functionality placeholder
                        } label: {
                            Label("Export Mesh", systemImage: "square.and.arrow.up")
                        }

                        Button(role: .destructive) {
                            deleteMesh()
                        } label: {
                            Label("Delete Scan", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .task {
                await loadMeshData()
            }
        }
    }

    private var scanInfoBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                if let mesh = meshData {
                    Text("Vertices: \(mesh.chunks.reduce(0) { $0 + $1.vertices.count })")
                        .font(.caption2)
                    Text("Size: \(String(format: "%.1fm x %.1fm x %.1fm", mesh.boundingBox.size.x, mesh.boundingBox.size.y, mesh.boundingBox.size.z))")
                        .font(.caption2)
                }
            }
            .foregroundStyle(.secondary)

            Spacer()

            HStack(spacing: 12) {
                Label("\(zone.destinationCount)", systemImage: "mappin.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.blue)

                Label("\(zone.waypointCount)", systemImage: "point.topleft.down.to.point.bottomright.curvepath.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    private func loadMeshData() async {
        isLoading = true
        loadError = nil

        do {
            if MeshDataStore.shared.meshExists(forZone: zone.id) {
                meshData = try MeshDataStore.shared.loadMeshData(forZone: zone.id)
            } else {
                loadError = "No 3D scan data available for this zone."
            }
        } catch {
            loadError = "Failed to load mesh: \(error.localizedDescription)"
        }

        isLoading = false
    }

    private func deleteMesh() {
        MeshDataStore.shared.deleteMesh(forZone: zone.id)
        dismiss()
    }
}

// MARK: - View Model

@MainActor
class ScansViewModel: ObservableObject {
    @Published var zones: [MapZone] = []

    private let zoneStore = ZoneStore.shared

    init() {
        refresh()
    }

    func refresh() {
        zones = zoneStore.sortedZones()
    }

    func hasMesh(for zone: MapZone) -> Bool {
        MeshDataStore.shared.meshExists(forZone: zone.id)
    }
}

// MARK: - Preview

struct ScansTabView_Previews: PreviewProvider {
    static var previews: some View {
        ScansTabView()
    }
}
