import SwiftUI

struct ZoneEditorSheet: View {
    @ObservedObject var viewModel: NavigationViewModel
    @FocusState private var isNameFocused: Bool

    var isEditing: Bool {
        viewModel.selectedZone != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Zone Name", text: $viewModel.editingZoneName)
                        .focused($isNameFocused)
                        .autocorrectionDisabled()

                    TextField("Description (optional)", text: $viewModel.editingZoneDescription, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("Zone Details")
                } footer: {
                    Text("Give this zone a descriptive name to help you find it later.")
                }

                if isEditing, let zone = viewModel.selectedZone {
                    Section("Info") {
                        InfoRow(
                            icon: "mappin.circle.fill",
                            title: "Destinations",
                            value: "\(zone.destinationCount)",
                            iconColor: .destination
                        )

                        InfoRow(
                            icon: "point.topleft.down.to.point.bottomright.curvepath.fill",
                            title: "Waypoints",
                            value: "\(zone.waypointCount)",
                            iconColor: .waypoint
                        )

                        InfoRow(
                            icon: "calendar",
                            title: "Created",
                            value: zone.createdAt.formatted(date: .abbreviated, time: .shortened)
                        )

                        InfoRow(
                            icon: "clock",
                            title: "Last Updated",
                            value: zone.formattedDate
                        )
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Zone" : "New Zone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.cancelZoneEditor()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Create") {
                        viewModel.saveZone()
                    }
                    .disabled(viewModel.editingZoneName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                isNameFocused = true
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
