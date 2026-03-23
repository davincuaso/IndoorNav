import Foundation
import ARKit
import Combine

enum AppMode: String, CaseIterable, Identifiable {
    case mapping = "Map the Space"
    case navigation = "Navigate"

    var id: String { rawValue }
}

@MainActor
final class NavigationViewModel: ObservableObject {

    // MARK: - Published State: General

    @Published var appMode: AppMode = .mapping
    @Published var worldMappingStatus: ARFrame.WorldMappingStatus = .notAvailable
    @Published var trackingState: ARCamera.TrackingState = .notAvailable
    @Published var sessionInfoText: String = "Initializing AR..."
    @Published var isSceneReconstructionSupported = false
    @Published var currentError: AppError?

    // MARK: - Published State: Mapping

    @Published var destinations: [NavigationAnchor] = []
    @Published var waypointCount: Int = 0
    @Published var isAutoWaypointEnabled = false
    @Published var isSavingMap = false
    @Published var mapSaveSuccess: String?

    // MARK: - Published State: Navigation

    @Published var isRelocalized = false
    @Published var loadedDestinations: [NavigationAnchor] = []
    @Published var selectedDestination: NavigationAnchor?
    @Published var isLoadingMap = false
    @Published var distanceToDestination: Float?
    @Published var hasArrived = false

    // MARK: - Published State: Map/Zone Management

    @Published var savedMapNames: [String] = []
    @Published var selectedMapName: String?
    @Published var showMapPicker = false
    @Published var selectedZone: MapZone?
    @Published var showZoneEditor = false
    @Published var editingZoneName = ""
    @Published var editingZoneDescription = ""

    // MARK: - Zone Store

    private let zoneStore = ZoneStore.shared
    var zones: [MapZone] { zoneStore.sortedZones() }

    // MARK: - Internal State

    var allMappingAnchors: [NavigationAnchor] = []
    var allLoadedAnchors: [NavigationAnchor] = []
    var lastAutoWaypointPosition: SIMD3<Float>?
    let autoWaypointInterval: Float = 1.5

    // MARK: - Relocalization Timeout

    private var relocalizationTimer: Timer?
    private let relocalizationTimeout: TimeInterval = 30.0

    // MARK: - Computed Properties

    var canSaveMap: Bool {
        worldMappingStatus == .mapped || worldMappingStatus == .extending
    }

    var worldMappingStatusText: String {
        switch worldMappingStatus {
        case .notAvailable: return "Not Available"
        case .limited:      return "Limited"
        case .extending:    return "Extending"
        case .mapped:       return "Mapped"
        @unknown default:   return "Unknown"
        }
    }

    var trackingStateText: String {
        switch trackingState {
        case .notAvailable:
            return "Not Available"
        case .limited(let reason):
            switch reason {
            case .initializing:         return "Initializing"
            case .excessiveMotion:      return "Slow Down"
            case .insufficientFeatures: return "Low Detail"
            case .relocalizing:         return "Relocalizing"
            @unknown default:           return "Limited"
            }
        case .normal:
            return "Normal"
        }
    }

    // MARK: - Initialization

    init() {
        refreshSavedMaps()
    }

    deinit {
        relocalizationTimer?.invalidate()
    }

    // MARK: - Map Management

    func refreshSavedMaps() {
        savedMapNames = MapStore.list()
    }

    func deleteMap(named name: String) {
        do {
            try MapStore.delete(name: name)
            refreshSavedMaps()
            if selectedMapName == name {
                selectedMapName = nil
            }
        } catch {
            currentError = .mapDeleteFailed(name: name, underlying: error)
        }
    }

    // MARK: - Mode Transitions

    func prepareForMappingMode() {
        cancelRelocalizationTimer()
        isRelocalized = false
        loadedDestinations = []
        selectedDestination = nil
        distanceToDestination = nil
        hasArrived = false

        destinations = []
        allMappingAnchors = []
        waypointCount = 0
        mapSaveSuccess = nil
        lastAutoWaypointPosition = nil
        showMapPicker = false
    }

    func prepareForNavigationMode() {
        refreshSavedMaps()
        if savedMapNames.isEmpty {
            currentError = .noMapsAvailable
            sessionInfoText = "No maps available"
        } else {
            showMapPicker = true
        }
    }

    func prepareForMapLoad(mapName: String) {
        cancelRelocalizationTimer()
        isRelocalized = false
        loadedDestinations = []
        selectedDestination = nil
        distanceToDestination = nil
        hasArrived = false
        isLoadingMap = true
        selectedMapName = mapName
        showMapPicker = false
    }

    func handleMapLoaded(anchors: [NavigationAnchor], summary: (destinations: Int, waypoints: Int)) {
        allLoadedAnchors = anchors
        loadedDestinations = anchors.filter(\.isDestination)
        isLoadingMap = false
        sessionInfoText = "Look around to localize... (\(summary.destinations) dest, \(summary.waypoints) waypoints)"
        startRelocalizationTimer()
    }

    func handleMapLoadError(_ error: Error, mapName: String) {
        currentError = .mapLoadFailed(name: mapName, underlying: error)
        sessionInfoText = "Map load failed"
        isLoadingMap = false
    }

    // MARK: - Destination Management (Mapping)

    func addDestination(_ anchor: NavigationAnchor) {
        destinations.append(anchor)
        allMappingAnchors.append(anchor)
        sessionInfoText = "Dropped destination \"\(anchor.destinationName)\""
    }

    func removeDestination(_ anchor: NavigationAnchor) {
        destinations.removeAll { $0.identifier == anchor.identifier }
        allMappingAnchors.removeAll { $0.identifier == anchor.identifier }
    }

    func addWaypoint(_ anchor: NavigationAnchor, at position: SIMD3<Float>) {
        waypointCount += 1
        allMappingAnchors.append(anchor)
        lastAutoWaypointPosition = position
    }

    // MARK: - Map Saving

    func beginSavingMap() {
        isSavingMap = true
        mapSaveSuccess = nil
        sessionInfoText = "Saving map..."
    }

    func handleMapSaved(name: String, summary: (destinations: Int, waypoints: Int)) {
        isSavingMap = false
        mapSaveSuccess = "Saved \"\(name)\" (\(summary.destinations) dest, \(summary.waypoints) waypoints)"
        sessionInfoText = "Map saved successfully"
        refreshSavedMaps()
    }

    func handleMapSaveError(_ error: Error?) {
        isSavingMap = false
        currentError = .mapSaveFailed(underlying: error)
        sessionInfoText = "Save failed"
    }

    // MARK: - Navigation

    func selectDestination(_ destination: NavigationAnchor) {
        selectedDestination = destination
        hasArrived = false
        sessionInfoText = "Navigating to \"\(destination.destinationName)\""
    }

    func clearNavigation() {
        selectedDestination = nil
        distanceToDestination = nil
        hasArrived = false
        if isRelocalized {
            sessionInfoText = "Select a destination"
        }
    }

    func updateDistance(_ distance: Float) {
        distanceToDestination = distance
        let wasArrived = hasArrived
        hasArrived = distance < 0.5

        if hasArrived && !wasArrived {
            // Will trigger haptic in view
        }
    }

    // MARK: - Relocalization

    func handleRelocalized() {
        guard !isRelocalized else { return }
        isRelocalized = true
        cancelRelocalizationTimer()
        sessionInfoText = "Localized - select a destination"
    }

    private func startRelocalizationTimer() {
        cancelRelocalizationTimer()
        relocalizationTimer = Timer.scheduledTimer(withTimeInterval: relocalizationTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleRelocalizationTimeout()
            }
        }
    }

    private func cancelRelocalizationTimer() {
        relocalizationTimer?.invalidate()
        relocalizationTimer = nil
    }

    private func handleRelocalizationTimeout() {
        guard !isRelocalized else { return }
        currentError = .relocalizationTimeout
    }

    func retryRelocalization() {
        currentError = nil
        startRelocalizationTimer()
        sessionInfoText = "Look around to localize..."
    }

    // MARK: - Session Updates

    func updateTrackingState(_ state: ARCamera.TrackingState, mappingStatus: ARFrame.WorldMappingStatus) {
        trackingState = state
        worldMappingStatus = mappingStatus

        if appMode == .navigation && !isRelocalized {
            if case .normal = state {
                handleRelocalized()
            }
        }

        updateSessionInfo()
    }

    func handleSessionError(_ error: Error) {
        currentError = .sessionFailed(underlying: error)
        sessionInfoText = "Session error"
    }

    func handleSessionInterrupted() {
        currentError = .sessionInterrupted
        sessionInfoText = "Session interrupted"
    }

    func handleSessionResumed() {
        currentError = nil
        sessionInfoText = "Session resumed"
    }

    private func updateSessionInfo() {
        guard !isSavingMap else { return }

        switch trackingState {
        case .notAvailable:
            sessionInfoText = "AR not available on this device"
        case .limited(let reason):
            switch reason {
            case .initializing:
                sessionInfoText = appMode == .navigation
                    ? "Look around slowly to localize..."
                    : "Initializing - move the device slowly"
            case .excessiveMotion:
                sessionInfoText = "Too much motion - slow down"
            case .insufficientFeatures:
                sessionInfoText = "Not enough detail - point at a textured surface"
            case .relocalizing:
                sessionInfoText = "Relocalizing - revisit a previously mapped area"
            @unknown default:
                sessionInfoText = "Limited tracking"
            }
        case .normal:
            switch appMode {
            case .mapping:
                let wpInfo = isAutoWaypointEnabled ? " | \(waypointCount) waypoints" : ""
                sessionInfoText = "Tracking: \(worldMappingStatusText)\(wpInfo)"
            case .navigation:
                if let dest = selectedDestination {
                    if let dist = distanceToDestination {
                        sessionInfoText = String(format: "-> \"%@\" - %.1f m", dest.destinationName, dist)
                    } else {
                        sessionInfoText = "Navigating to \"\(dest.destinationName)\""
                    }
                } else {
                    sessionInfoText = "Localized - select a destination"
                }
            }
        }
    }

    func dismissError() {
        currentError = nil
    }

    // MARK: - Zone Management

    func createNewZone() {
        editingZoneName = ""
        editingZoneDescription = ""
        selectedZone = nil
        showZoneEditor = true
    }

    func editZone(_ zone: MapZone) {
        editingZoneName = zone.name
        editingZoneDescription = zone.description
        selectedZone = zone
        showZoneEditor = true
    }

    func saveZone() {
        let name = editingZoneName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        if var zone = selectedZone {
            // Update existing zone
            zone.name = name
            zone.description = editingZoneDescription.trimmingCharacters(in: .whitespaces)
            zoneStore.updateZone(zone)
        } else {
            // Create new zone
            let zone = zoneStore.createZone(
                name: name,
                description: editingZoneDescription.trimmingCharacters(in: .whitespaces)
            )
            selectedZone = zone
        }

        showZoneEditor = false
        objectWillChange.send()
    }

    func deleteZone(_ zone: MapZone) {
        zoneStore.deleteZone(zone)
        if selectedZone?.id == zone.id {
            selectedZone = nil
        }
        objectWillChange.send()
    }

    func selectZoneForMapping(_ zone: MapZone) {
        selectedZone = zone
        selectedMapName = zone.mapFileName
        prepareForMappingMode()
    }

    func selectZoneForNavigation(_ zone: MapZone) {
        selectedZone = zone
        prepareForMapLoad(mapName: zone.mapFileName)
    }

    func handleMapSavedToZone(summary: (destinations: Int, waypoints: Int)) {
        guard let zone = selectedZone else {
            handleMapSaved(name: selectedMapName ?? "Unknown", summary: summary)
            return
        }

        zoneStore.associateMap(zone: zone, destinationCount: summary.destinations, waypointCount: summary.waypoints)
        isSavingMap = false
        mapSaveSuccess = "Saved \"\(zone.name)\" (\(summary.destinations) dest, \(summary.waypoints) waypoints)"
        sessionInfoText = "Map saved successfully"
        objectWillChange.send()
    }

    func cancelZoneEditor() {
        showZoneEditor = false
        editingZoneName = ""
        editingZoneDescription = ""
    }
}
