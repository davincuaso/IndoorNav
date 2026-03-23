import SwiftUI

struct ZoneSelectorView: View {
    @ObservedObject var viewModel: NavigationViewModel
    let mode: SelectionMode
    let onSelect: (MapZone) -> Void

    enum SelectionMode {
        case mapping
        case navigation
    }

    var body: some View {
        VStack(spacing: 12) {
            header

            if viewModel.zones.isEmpty {
                emptyState
            } else {
                zoneList
            }
        }
    }

    private var header: some View {
        HStack {
            Text(mode == .mapping ? "Select Zone to Map" : "Select Zone to Navigate")
                .font(.subheadline.bold())

            Spacer()

            if mode == .mapping {
                Button {
                    viewModel.createNewZone()
                } label: {
                    Image(systemName: "plus.circle.fill")
                    Text("New")
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .tint(.blue)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: mode == .mapping ? "map" : "map.fill")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text(mode == .mapping
                 ? "No zones created yet.\nCreate a new zone to start mapping."
                 : "No mapped zones available.\nMap a space first in Map mode.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical)
    }

    private var zoneList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 8) {
                ForEach(viewModel.zones) { zone in
                    ZoneRowView(
                        zone: zone,
                        mode: mode,
                        isSelected: viewModel.selectedZone?.id == zone.id,
                        onSelect: { onSelect(zone) },
                        onEdit: { viewModel.editZone(zone) },
                        onDelete: { viewModel.deleteZone(zone) }
                    )
                }
            }
        }
        .frame(maxHeight: 200)
    }
}

struct ZoneRowView: View {
    let zone: MapZone
    let mode: ZoneSelectorView.SelectionMode
    let isSelected: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var showDeleteConfirm = false

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onSelect) {
                HStack {
                    zoneIcon
                    zoneInfo
                    Spacer()
                    chevron
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(isSelected ? Color.blue.opacity(0.15) : Color.blue.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            if mode == .mapping {
                Menu {
                    Button(action: onEdit) {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .confirmationDialog(
            "Delete \"\(zone.name)\"?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the zone and its map data.")
        }
    }

    private var zoneIcon: some View {
        ZStack {
            Circle()
                .fill(zone.destinationCount > 0 ? Color.green.opacity(0.2) : Color.gray.opacity(0.2))
                .frame(width: 36, height: 36)

            Image(systemName: zone.destinationCount > 0 ? "map.fill" : "map")
                .font(.system(size: 16))
                .foregroundStyle(zone.destinationCount > 0 ? .green : .secondary)
        }
    }

    private var zoneInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(zone.displayName)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)

            HStack(spacing: 6) {
                Text(zone.summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if !zone.description.isEmpty {
                    Text("*")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(zone.description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Text(zone.formattedDate)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.caption)
            .foregroundStyle(.tertiary)
    }
}

struct ZoneEditorSheet: View {
    @ObservedObject var viewModel: NavigationViewModel

    var body: some View {
        NavigationView {
            Form {
                Section("Zone Details") {
                    TextField("Zone Name", text: $viewModel.editingZoneName)
                        .textInputAutocapitalization(.words)

                    TextField("Description (optional)", text: $viewModel.editingZoneDescription)
                        .textInputAutocapitalization(.sentences)
                }

                Section {
                    Text("Examples: \"Lobby\", \"Floor 2\", \"Building A - West Wing\"")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(viewModel.selectedZone == nil ? "New Zone" : "Edit Zone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.cancelZoneEditor()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        viewModel.saveZone()
                    }
                    .disabled(viewModel.editingZoneName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
