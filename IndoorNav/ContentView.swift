import SwiftUI
import ARKit

struct ContentView: View {
    @StateObject private var sessionManager = ARSessionManager()
    @State private var anchorName = ""
    @State private var mapName = ""
    @State private var showMapPicker = false

    var body: some View {
        ZStack {
            ARViewContainer(sessionManager: sessionManager)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer()

                if sessionManager.appMode == .mapping {
                    mappingControls
                } else {
                    navigationControls
                }

                bottomBar
            }
        }
        .onAppear {
            sessionManager.startMappingSession()
        }
        .onChange(of: sessionManager.appMode) { newMode in
            if newMode == .mapping {
                sessionManager.startMappingSession()
                showMapPicker = false
            } else {
                sessionManager.refreshSavedMaps()
                if sessionManager.savedMapNames.isEmpty {
                    sessionManager.navigationError = "No saved maps. Map the space first."
                    sessionManager.sessionInfoText = "No maps available"
                } else {
                    showMapPicker = true
                }
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        VStack(spacing: 8) {
            Picker("Mode", selection: $sessionManager.appMode) {
                ForEach(AppMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    // MARK: - Mapping Controls

    private var mappingControls: some View {
        VStack(spacing: 10) {

            // Auto-waypoint toggle + manual waypoint button
            HStack {
                Toggle(isOn: $sessionManager.isAutoWaypointEnabled) {
                    HStack(spacing: 4) {
                        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                            .foregroundStyle(.yellow)
                        Text("Auto-Waypoints")
                            .font(.caption)
                    }
                }
                .toggleStyle(.switch)
                .tint(.yellow)

                Spacer()

                Button {
                    sessionManager.dropWaypointAtCamera()
                } label: {
                    Image(systemName: "plus.circle")
                    Text("WP")
                }
                .buttonStyle(.bordered)
                .tint(.yellow)
                .font(.caption)
            }

            if sessionManager.waypointCount > 0 {
                Text("\(sessionManager.waypointCount) waypoint\(sessionManager.waypointCount == 1 ? "" : "s") placed")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            // Destinations
            if !sessionManager.destinations.isEmpty {
                destinationList
            }

            HStack(spacing: 10) {
                TextField("Destination name", text: $anchorName)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()

                Button {
                    let name = anchorName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    sessionManager.dropDestination(named: name)
                    anchorName = ""
                } label: {
                    Image(systemName: "mappin.and.ellipse")
                    Text("Drop")
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(anchorName.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Divider()

            // Save
            HStack(spacing: 10) {
                TextField("Map name", text: $mapName)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()

                Button {
                    let name = mapName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    sessionManager.saveWorldMap(name: name)
                } label: {
                    HStack {
                        if sessionManager.isSavingMap {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "square.and.arrow.down")
                        }
                        Text("Save")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(
                    !sessionManager.canSaveMap
                    || sessionManager.isSavingMap
                    || mapName.trimmingCharacters(in: .whitespaces).isEmpty
                )
            }

            if let result = sessionManager.mapSaveResult {
                Text(result)
                    .font(.caption)
                    .foregroundStyle(result.hasPrefix("Saved") ? .green : .red)
            }

            if !sessionManager.canSaveMap {
                Text("Walk around to build map quality before saving")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    // MARK: - Destination List (Mapping)

    private var destinationList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Destinations (\(sessionManager.destinations.count))")
                .font(.caption.bold())

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(sessionManager.destinations, id: \.identifier) { anchor in
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundStyle(.blue)
                            Text(anchor.destinationName)
                                .font(.caption)
                            Button {
                                sessionManager.removeDestination(anchor)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                    }
                }
            }
        }
    }

    // MARK: - Navigation Controls

    private var navigationControls: some View {
        VStack(spacing: 10) {
            if showMapPicker {
                mapPickerView
            } else if sessionManager.isLoadingMap {
                HStack {
                    ProgressView()
                    Text("Loading map...")
                        .font(.subheadline)
                }
            } else if let error = sessionManager.navigationError {
                VStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .font(.title2)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            } else if !sessionManager.isRelocalized {
                relocalizationView
            } else {
                destinationPicker
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    // MARK: - Map Picker

    private var mapPickerView: some View {
        VStack(spacing: 8) {
            Text("Select a saved map:")
                .font(.subheadline.bold())

            if sessionManager.savedMapNames.isEmpty {
                Text("No maps saved yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(sessionManager.savedMapNames, id: \.self) { name in
                            HStack {
                                Button {
                                    showMapPicker = false
                                    sessionManager.startNavigationSession(mapName: name)
                                } label: {
                                    HStack {
                                        Image(systemName: "map.fill")
                                        Text(name)
                                            .font(.subheadline)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.blue.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)

                                Button(role: .destructive) {
                                    sessionManager.deleteMap(named: name)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .tint(.red)
                            }
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
        }
    }

    // MARK: - Relocalization View

    private var relocalizationView: some View {
        VStack(spacing: 8) {
            ProgressView()
                .scaleEffect(1.2)

            Text("Look around to localize...")
                .font(.subheadline.bold())

            Text("Point your device at the area you previously mapped. Move slowly and revisit recognizable features.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let mapName = sessionManager.selectedMapName {
                Text("Map: \"\(mapName)\" — \(sessionManager.loadedDestinations.count) destination\(sessionManager.loadedDestinations.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Button("Choose different map") {
                showMapPicker = true
            }
            .font(.caption)
        }
    }

    // MARK: - Destination Picker

    private var destinationPicker: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Localized")
                    .font(.caption.bold())
                    .foregroundStyle(.green)
                if let name = sessionManager.selectedMapName {
                    Text("(\(name))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if sessionManager.selectedDestination != nil {
                    Button("Clear") {
                        sessionManager.clearNavigation()
                    }
                    .font(.caption)
                }
            }

            if sessionManager.loadedDestinations.isEmpty {
                Text("No destinations in this map.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Where do you want to go?")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(sessionManager.loadedDestinations, id: \.identifier) { dest in
                            destinationButton(for: dest)
                        }
                    }
                }
            }

            if let dist = sessionManager.distanceToDestination,
               let dest = sessionManager.selectedDestination {
                HStack(spacing: 6) {
                    Image(systemName: "location.fill")
                        .foregroundStyle(.cyan)
                    Text(String(format: "\"%@\" — %.1f m", dest.destinationName, dist))
                        .font(.caption.bold())
                }
                .padding(.top, 2)

                if dist < 0.5 {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Text("You have arrived!")
                            .font(.caption.bold())
                            .foregroundStyle(.green)
                    }
                }
            }

            Button("Choose different map") {
                showMapPicker = true
                sessionManager.clearNavigation()
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private func destinationButton(for dest: NavigationAnchor) -> some View {
        let isSelected = sessionManager.selectedDestination?.identifier == dest.identifier

        return Button {
            if isSelected {
                sessionManager.clearNavigation()
            } else {
                sessionManager.selectDestination(dest)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isSelected ? "flag.fill" : "mappin.circle.fill")
                Text(dest.destinationName)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.cyan.opacity(0.3) : Color.clear)
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.cyan : Color.secondary.opacity(0.4), lineWidth: 1)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(trackingColor)
                    .frame(width: 8, height: 8)
                Text("Tracking: \(sessionManager.trackingStateText)")
                    .font(.caption)
                    .foregroundStyle(.primary)
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(mappingColor)
                    .frame(width: 8, height: 8)
                Text("World Map: \(sessionManager.worldMappingStatusText)")
                    .font(.caption)
                    .foregroundStyle(.primary)
            }

            if sessionManager.isSceneReconstructionSupported {
                HStack(spacing: 6) {
                    Image(systemName: "viewfinder")
                        .font(.caption2)
                    Text("LiDAR Active")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Text(sessionManager.sessionInfoText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    // MARK: - Status Colors

    private var trackingColor: Color {
        switch sessionManager.trackingState {
        case .normal:       return .green
        case .notAvailable: return .red
        case .limited:      return .yellow
        }
    }

    private var mappingColor: Color {
        switch sessionManager.worldMappingStatus {
        case .mapped:       return .green
        case .extending:    return .yellow
        case .limited:      return .orange
        case .notAvailable: return .red
        @unknown default:   return .gray
        }
    }
}
