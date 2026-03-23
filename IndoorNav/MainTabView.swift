import SwiftUI

struct MainTabView: View {
    @State private var selectedTab: AppTab = .ar
    @StateObject private var appState = AppState.shared

    var body: some View {
        TabView(selection: $selectedTab) {
            ARTabView()
                .tabItem {
                    Label {
                        Text(AppTab.ar.title)
                    } icon: {
                        Image(systemName: selectedTab == .ar ? AppTab.ar.selectedIcon : AppTab.ar.icon)
                    }
                }
                .tag(AppTab.ar)

            ScansTabView()
                .tabItem {
                    Label {
                        Text(AppTab.scans.title)
                    } icon: {
                        Image(systemName: selectedTab == .scans ? AppTab.scans.selectedIcon : AppTab.scans.icon)
                    }
                }
                .tag(AppTab.scans)
        }
        .tint(.appPrimary)
        .onChange(of: selectedTab) { newTab in
            HapticManager.shared.selectionChanged()
            appState.currentTab = newTab
        }
    }
}

// MARK: - App State

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()

    @Published var currentTab: AppTab = .ar
    @Published var isARSessionActive = false

    private init() {}
}

// MARK: - AR Tab View (Wrapper for ContentView)

struct ARTabView: View {
    @StateObject private var viewModel = NavigationViewModel()
    @State private var arManager: ARManager?
    @State private var anchorName = ""

    var body: some View {
        ZStack {
            if let arManager = arManager {
                ARViewContainer(
                    arManager: arManager,
                    showCoaching: true,
                    coachingGoal: .tracking
                )
                .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                topBar
                Spacer()

                if viewModel.appMode == .mapping {
                    mappingControls
                } else {
                    navigationControls
                }

                bottomBar
            }
        }
        .onAppear {
            setupARManager()
            AppState.shared.isARSessionActive = true
        }
        .onDisappear {
            arManager?.pauseSession()
            AppState.shared.isARSessionActive = false
        }
        .onChange(of: viewModel.appMode) { newMode in
            handleModeChange(newMode)
        }
        .onChange(of: viewModel.hasArrived) { arrived in
            if arrived {
                HapticManager.shared.arrived()
            }
        }
        .onChange(of: viewModel.isRelocalized) { relocalized in
            if relocalized {
                HapticManager.shared.relocalized()
            }
        }
        .alert(item: $viewModel.currentError) { error in
            Alert(
                title: Text(error.alertTitle),
                message: Text(error.errorDescription ?? "An error occurred."),
                primaryButton: errorPrimaryButton(for: error),
                secondaryButton: .cancel(Text("Dismiss")) {
                    viewModel.dismissError()
                }
            )
        }
        .sheet(isPresented: $viewModel.showZoneEditor) {
            ZoneEditorSheet(viewModel: viewModel)
        }
    }

    private func setupARManager() {
        let manager = ARManager(viewModel: viewModel)
        arManager = manager
        manager.startMappingSession()
        viewModel.prepareForMappingMode()
    }

    private func handleModeChange(_ newMode: AppMode) {
        HapticManager.shared.selectionChanged()
        switch newMode {
        case .mapping:
            viewModel.prepareForMappingMode()
            arManager?.startMappingSession()
        case .navigation:
            viewModel.prepareForNavigationMode()
        }
    }

    private func errorPrimaryButton(for error: AppError) -> Alert.Button {
        switch error {
        case .relocalizationTimeout:
            return .default(Text("Retry")) {
                viewModel.retryRelocalization()
            }
        case .noMapsAvailable:
            return .default(Text("Switch to Map Mode")) {
                viewModel.appMode = .mapping
            }
        case .mapLoadFailed, .mapCorrupted, .mapNotFound:
            return .default(Text("Choose Different Map")) {
                viewModel.showMapPicker = true
                viewModel.dismissError()
            }
        default:
            return .default(Text("OK")) {
                viewModel.dismissError()
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        Picker("Mode", selection: $viewModel.appMode) {
            ForEach(AppMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    // MARK: - Mapping Controls

    private var mappingControls: some View {
        VStack(spacing: 6) {
            // Compact row: waypoints + destination input
            HStack(spacing: 8) {
                Toggle("", isOn: $viewModel.isAutoWaypointEnabled)
                    .toggleStyle(.switch)
                    .tint(.waypoint)
                    .labelsHidden()
                    .scaleEffect(0.8)

                Text("Auto-WP")
                    .font(.appCaption2)

                if viewModel.waypointCount > 0 {
                    Text("(\(viewModel.waypointCount))")
                        .font(.appCaption2)
                        .foregroundColor(.waypoint)
                }

                Spacer()

                Button {
                    dropManualWaypoint()
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.bordered)
                .tint(.waypoint)
                .font(.caption)
            }

            // Destination input row
            HStack(spacing: 8) {
                TextField("Destination", text: $anchorName)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .font(.caption)

                Button {
                    dropDestination()
                } label: {
                    Image(systemName: "mappin.and.ellipse")
                }
                .buttonStyle(.borderedProminent)
                .tint(.destination)
                .disabled(anchorName.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            // Destinations list (compact)
            if !viewModel.destinations.isEmpty {
                compactDestinationList
            }

            Divider()

            // Zone Selection & Save (compact)
            if let zone = viewModel.selectedZone {
                HStack {
                    Text("Zone: \(zone.displayName)")
                        .font(.appCaption2.bold())
                    Spacer()
                    Button("Change") {
                        viewModel.selectedZone = nil
                    }
                    .font(.appCaption2)

                    Button {
                        saveMapToZone(zone)
                    } label: {
                        if viewModel.isSavingMap {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "square.and.arrow.down.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.arrived)
                    .disabled(!viewModel.canSaveMap || viewModel.isSavingMap)
                }
            } else {
                ZoneSelectorView(viewModel: viewModel, mode: .mapping) { zone in
                    viewModel.selectZoneForMapping(zone)
                }
                .frame(maxHeight: 120)
            }

            if let result = viewModel.mapSaveSuccess {
                Text(result)
                    .font(.appCaption2)
                    .foregroundColor(.arrived)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private var compactDestinationList: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(viewModel.destinations, id: \.identifier) { anchor in
                    HStack(spacing: 2) {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundColor(.destination)
                            .font(.caption2)
                        Text(anchor.destinationName)
                            .font(.caption2)
                        Button {
                            arManager?.removeAnchor(anchor)
                            viewModel.removeDestination(anchor)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .font(.caption2)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.destination.opacity(0.15))
                    .clipShape(Capsule())
                }
            }
        }
    }

    private func saveMapToZone(_ zone: MapZone) {
        viewModel.beginSavingMap()

        // Save mesh data along with the map (requires LiDAR)
        var meshSaved = false
        if let meshAnchors = arManager?.getMeshAnchors(), !meshAnchors.isEmpty {
            do {
                try MeshDataStore.shared.saveMeshData(from: meshAnchors, forZone: zone.id)
                meshSaved = true
                print("Saved \(meshAnchors.count) mesh anchors for zone \(zone.id)")
            } catch {
                print("Failed to save mesh data: \(error)")
            }
        } else {
            print("No mesh anchors available - device may not have LiDAR or scene reconstruction not ready")
        }

        arManager?.saveWorldMap(name: zone.mapFileName) { result in
            Task { @MainActor in
                switch result {
                case .success(let summary):
                    viewModel.handleMapSavedToZone(summary: summary)
                    HapticManager.shared.mapSaved()
                    if !meshSaved && viewModel.isSceneReconstructionSupported {
                        // Mesh should have been available but wasn't
                        print("Warning: LiDAR supported but no mesh data was saved")
                    }
                case .failure(let error):
                    viewModel.handleMapSaveError(error)
                    HapticManager.shared.error()
                }
            }
        }
    }

    private func dropManualWaypoint() {
        HapticManager.shared.waypointDropped()
        let wpCount = viewModel.waypointCount + 1
        let name = "WP-\(wpCount)"
        if let result = arManager?.dropWaypoint(named: name) {
            viewModel.addWaypoint(result.anchor, at: result.position)
        }
    }

    private func dropDestination() {
        let name = anchorName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        HapticManager.shared.destinationDropped()
        if let anchor = arManager?.dropDestination(named: name) {
            viewModel.addDestination(anchor)
            anchorName = ""
        }
    }

    // MARK: - Navigation Controls

    private var navigationControls: some View {
        VStack(spacing: 10) {
            if viewModel.showMapPicker {
                mapPickerView
            } else if viewModel.isLoadingMap {
                HStack {
                    ProgressView()
                    Text("Loading map...")
                        .font(.appSubheadline)
                }
            } else if !viewModel.isRelocalized {
                relocalizationView
            } else {
                destinationPicker
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    // MARK: - Zone Picker

    private var mapPickerView: some View {
        ZoneSelectorView(viewModel: viewModel, mode: .navigation) { zone in
            loadZone(zone)
        }
        .frame(maxHeight: 150)
    }

    private func loadZone(_ zone: MapZone) {
        viewModel.selectZoneForNavigation(zone)
        arManager?.startNavigationSession(mapName: zone.mapFileName)
    }

    // MARK: - Relocalization View

    private var relocalizationView: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                ProgressView()
                Text("Localizing...")
                    .font(.appCaption.bold())
            }

            Text("Point at a previously mapped area")
                .font(.appCaption2)
                .foregroundStyle(.secondary)

            Button("Different map") {
                viewModel.showMapPicker = true
            }
            .font(.appCaption2)
        }
    }

    // MARK: - Destination Picker

    private var destinationPicker: some View {
        VStack(spacing: 6) {
            // Status row
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.arrived)
                    .font(.caption)
                Text("Ready")
                    .font(.appCaption2.bold())
                    .foregroundColor(.arrived)

                Spacer()

                Button("Change Map") {
                    viewModel.showMapPicker = true
                    arManager?.clearPath()
                    viewModel.clearNavigation()
                }
                .font(.appCaption2)
            }

            // Destination buttons
            if !viewModel.loadedDestinations.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(viewModel.loadedDestinations, id: \.identifier) { dest in
                            destinationButton(for: dest)
                        }
                    }
                }
            }

            // Distance indicator
            if let dist = viewModel.distanceToDestination,
               let dest = viewModel.selectedDestination {
                HStack(spacing: 6) {
                    Image(systemName: viewModel.hasArrived ? "checkmark.seal.fill" : "location.fill")
                        .foregroundColor(viewModel.hasArrived ? .arrived : .path)
                    Text(viewModel.hasArrived ? "Arrived!" : String(format: "%@ - %.1fm", dest.destinationName, dist))
                        .font(.appCaption.bold())
                        .foregroundColor(viewModel.hasArrived ? .arrived : .primary)
                }
            }
        }
    }

    private func destinationButton(for dest: NavigationAnchor) -> some View {
        let isSelected = viewModel.selectedDestination?.identifier == dest.identifier

        return Button {
            HapticManager.shared.destinationSelected()
            if isSelected {
                arManager?.clearPath()
                viewModel.clearNavigation()
            } else {
                viewModel.selectDestination(dest)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isSelected ? "flag.fill" : "mappin.circle.fill")
                Text(dest.destinationName)
                    .font(.appCaption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.path.opacity(0.3) : Color.clear)
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.path : Color.secondary.opacity(0.4), lineWidth: 1)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 4) {
            HStack(spacing: 12) {
                StatusBadge(
                    status: trackingStatus,
                    text: viewModel.trackingStateText
                )

                StatusBadge(
                    status: mappingStatus,
                    text: viewModel.worldMappingStatusText
                )

                if viewModel.isSceneReconstructionSupported {
                    let meshCount = arManager?.getMeshAnchors().count ?? 0
                    HStack(spacing: 3) {
                        Image(systemName: "viewfinder")
                        Text("3D: \(meshCount)")
                    }
                    .font(.appCaption2)
                    .foregroundStyle(meshCount > 0 ? .green : .secondary)
                }
            }

            Text(viewModel.sessionInfoText)
                .font(.appCaption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    private var trackingStatus: StatusBadge.Status {
        switch viewModel.trackingState {
        case .normal:       return .active
        case .notAvailable: return .error
        case .limited:      return .warning
        }
    }

    private var mappingStatus: StatusBadge.Status {
        switch viewModel.worldMappingStatus {
        case .mapped:       return .active
        case .extending:    return .warning
        case .limited:      return .warning
        case .notAvailable: return .inactive
        @unknown default:   return .inactive
        }
    }
}

// MARK: - Preview

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
    }
}
