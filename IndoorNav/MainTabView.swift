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
        VStack(spacing: 8) {
            Picker("Mode", selection: $viewModel.appMode) {
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
                Toggle(isOn: $viewModel.isAutoWaypointEnabled) {
                    HStack(spacing: 4) {
                        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                            .foregroundColor(.waypoint)
                        Text("Auto-Waypoints")
                            .font(.appCaption)
                    }
                }
                .toggleStyle(.switch)
                .tint(.waypoint)

                Spacer()

                Button {
                    dropManualWaypoint()
                } label: {
                    Image(systemName: "plus.circle")
                    Text("WP")
                }
                .buttonStyle(.bordered)
                .tint(.waypoint)
                .font(.appCaption)
            }

            if viewModel.waypointCount > 0 {
                Text("\(viewModel.waypointCount) waypoint\(viewModel.waypointCount == 1 ? "" : "s") placed")
                    .font(.appCaption2)
                    .foregroundStyle(.waypoint)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            // Destinations
            if !viewModel.destinations.isEmpty {
                destinationList
            }

            HStack(spacing: 10) {
                TextField("Destination name", text: $anchorName)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()

                Button {
                    dropDestination()
                } label: {
                    Image(systemName: "mappin.and.ellipse")
                    Text("Drop")
                }
                .buttonStyle(.borderedProminent)
                .tint(.destination)
                .disabled(anchorName.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Divider()

            // Zone Selection & Save
            if let zone = viewModel.selectedZone {
                HStack {
                    Image(systemName: "map.fill")
                        .foregroundStyle(.destination)
                    Text("Zone: \(zone.displayName)")
                        .font(.appCaption.bold())
                    Spacer()
                    Button("Change") {
                        viewModel.selectedZone = nil
                    }
                    .font(.appCaption)
                }

                Button {
                    saveMapToZone(zone)
                } label: {
                    HStack {
                        if viewModel.isSavingMap {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "square.and.arrow.down")
                        }
                        Text("Save to \"\(zone.displayName)\"")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.arrived)
                .disabled(!viewModel.canSaveMap || viewModel.isSavingMap)
            } else {
                ZoneSelectorView(viewModel: viewModel, mode: .mapping) { zone in
                    viewModel.selectZoneForMapping(zone)
                }
            }

            if let result = viewModel.mapSaveSuccess {
                Text(result)
                    .font(.appCaption)
                    .foregroundStyle(.arrived)
            }

            if !viewModel.canSaveMap && viewModel.selectedZone != nil {
                Text("Walk around to build map quality before saving")
                    .font(.appCaption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    private func saveMapToZone(_ zone: MapZone) {
        viewModel.beginSavingMap()

        // Save mesh data along with the map
        if let meshAnchors = arManager?.getMeshAnchors(), !meshAnchors.isEmpty {
            try? MeshDataStore.shared.saveMeshData(from: meshAnchors, forZone: zone.id)
        }

        arManager?.saveWorldMap(name: zone.mapFileName) { result in
            Task { @MainActor in
                switch result {
                case .success(let summary):
                    viewModel.handleMapSavedToZone(summary: summary)
                    HapticManager.shared.mapSaved()
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

    // MARK: - Destination List (Mapping)

    private var destinationList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Destinations (\(viewModel.destinations.count))")
                .font(.appCaption.bold())

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.destinations, id: \.identifier) { anchor in
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundColor(.destination)
                            Text(anchor.destinationName)
                                .font(.appCaption)
                            Button {
                                arManager?.removeAnchor(anchor)
                                viewModel.removeDestination(anchor)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                                    .font(.appCaption)
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
        .padding()
        .background(.ultraThinMaterial)
    }

    // MARK: - Zone Picker

    private var mapPickerView: some View {
        ZoneSelectorView(viewModel: viewModel, mode: .navigation) { zone in
            loadZone(zone)
        }
    }

    private func loadZone(_ zone: MapZone) {
        viewModel.selectZoneForNavigation(zone)
        arManager?.startNavigationSession(mapName: zone.mapFileName)
    }

    // MARK: - Relocalization View

    private var relocalizationView: some View {
        VStack(spacing: 8) {
            ProgressView()
                .scaleEffect(1.2)

            Text("Look around to localize...")
                .font(.appSubheadline.bold())

            Text("Point your device at the area you previously mapped. Move slowly and revisit recognizable features.")
                .font(.appCaption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let mapName = viewModel.selectedMapName {
                Text("Map: \"\(mapName)\" - \(viewModel.loadedDestinations.count) destination\(viewModel.loadedDestinations.count == 1 ? "" : "s")")
                    .font(.appCaption2)
                    .foregroundStyle(.secondary)
            }

            Button("Choose different map") {
                viewModel.showMapPicker = true
            }
            .font(.appCaption)
        }
    }

    // MARK: - Destination Picker

    private var destinationPicker: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.arrived)
                Text("Localized")
                    .font(.appCaption.bold())
                    .foregroundColor(.arrived)
                if let name = viewModel.selectedMapName {
                    Text("(\(name))")
                        .font(.appCaption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if viewModel.selectedDestination != nil {
                    Button("Clear") {
                        arManager?.clearPath()
                        viewModel.clearNavigation()
                    }
                    .font(.appCaption)
                }
            }

            if viewModel.loadedDestinations.isEmpty {
                Text("No destinations in this map.")
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Where do you want to go?")
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.loadedDestinations, id: \.identifier) { dest in
                            destinationButton(for: dest)
                        }
                    }
                }
            }

            if let dist = viewModel.distanceToDestination,
               let dest = viewModel.selectedDestination {
                HStack(spacing: 6) {
                    Image(systemName: "location.fill")
                        .foregroundStyle(.path)
                    Text(String(format: "\"%@\" - %.1f m", dest.destinationName, dist))
                        .font(.appCaption.bold())
                }
                .padding(.top, 2)

                if viewModel.hasArrived {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.arrived)
                        Text("You have arrived!")
                            .font(.appCaption.bold())
                            .foregroundStyle(.arrived)
                    }
                }
            }

            Button("Choose different map") {
                viewModel.showMapPicker = true
                arManager?.clearPath()
                viewModel.clearNavigation()
            }
            .font(.appCaption2)
            .foregroundStyle(.secondary)
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
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                StatusBadge(
                    status: trackingStatus,
                    text: "Tracking: \(viewModel.trackingStateText)"
                )
            }

            HStack(spacing: 6) {
                StatusBadge(
                    status: mappingStatus,
                    text: "World Map: \(viewModel.worldMappingStatusText)"
                )
            }

            if viewModel.isSceneReconstructionSupported {
                HStack(spacing: 6) {
                    Image(systemName: "viewfinder")
                        .font(.appCaption2)
                    Text("LiDAR Active")
                        .font(.appCaption2)
                        .foregroundStyle(.secondary)
                }
            }

            Text(viewModel.sessionInfoText)
                .font(.appCaption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
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
