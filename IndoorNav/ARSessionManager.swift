import Foundation
import ARKit
import SceneKit
import Combine

enum AppMode: String, CaseIterable, Identifiable {
    case mapping = "Map the Space"
    case navigation = "Navigate"

    var id: String { rawValue }
}

class ARSessionManager: NSObject, ObservableObject {

    // MARK: - Published State (shared)

    @Published var appMode: AppMode = .mapping
    @Published var worldMappingStatus: ARFrame.WorldMappingStatus = .notAvailable
    @Published var trackingState: ARCamera.TrackingState = .notAvailable
    @Published var sessionInfoText: String = "Initializing AR..."
    @Published var isSceneReconstructionSupported = false

    // MARK: - Published State (mapping)

    @Published var destinations: [NavigationAnchor] = []
    @Published var waypointCount: Int = 0
    @Published var isAutoWaypointEnabled = false
    @Published var isSavingMap = false
    @Published var mapSaveResult: String?

    // MARK: - Published State (navigation)

    @Published var isRelocalized = false
    @Published var loadedDestinations: [NavigationAnchor] = []
    @Published var selectedDestination: NavigationAnchor?
    @Published var isLoadingMap = false
    @Published var navigationError: String?
    @Published var distanceToDestination: Float?

    // MARK: - Published State (map management)

    @Published var savedMapNames: [String] = []
    @Published var selectedMapName: String?

    // MARK: - AR Objects

    let sceneView = ARSCNView()

    // MARK: - Path Rendering

    private let pathContainerNode = SCNNode()
    private var lastPathUpdateTime: TimeInterval = 0
    private let pathDotSpacing: Float = 0.25

    private lazy var pathDotGeometry: SCNSphere = {
        let s = SCNSphere(radius: 0.015)
        s.segmentCount = 8
        s.firstMaterial?.diffuse.contents = UIColor.systemCyan
        s.firstMaterial?.lightingModel = .constant
        return s
    }()

    private lazy var pathArrowGeometry: SCNCone = {
        let c = SCNCone(topRadius: 0, bottomRadius: 0.03, height: 0.06)
        c.radialSegmentCount = 8
        c.firstMaterial?.diffuse.contents = UIColor.systemCyan
        c.firstMaterial?.lightingModel = .constant
        return c
    }()

    // MARK: - Auto-Waypoint State

    private var lastAutoWaypointPosition: SIMD3<Float>?
    private let autoWaypointInterval: Float = 1.5
    private var allMappingAnchors: [NavigationAnchor] = []

    // MARK: - Navigation Path State

    private var allLoadedAnchors: [NavigationAnchor] = []
    private var currentPath: [SIMD3<Float>] = []

    // MARK: - Init

    override init() {
        super.init()
        sceneView.delegate = self
        sceneView.session.delegate = self
        sceneView.automaticallyUpdatesLighting = true
        sceneView.scene.rootNode.addChildNode(pathContainerNode)
        refreshSavedMaps()
    }

    // MARK: - Map Management

    func refreshSavedMaps() {
        savedMapNames = MapStore.list()
    }

    func deleteMap(named name: String) {
        try? MapStore.delete(name: name)
        refreshSavedMaps()
        if selectedMapName == name {
            selectedMapName = nil
        }
    }

    // MARK: - Session: Mapping

    func startMappingSession() {
        isRelocalized = false
        loadedDestinations = []
        selectedDestination = nil
        navigationError = nil
        distanceToDestination = nil
        currentPath = []
        clearPath()

        destinations = []
        allMappingAnchors = []
        waypointCount = 0
        mapSaveResult = nil
        lastAutoWaypointPosition = nil

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic

        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
            isSceneReconstructionSupported = true
        }

        sceneView.debugOptions = [.showFeaturePoints]
        sceneView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        sessionInfoText = "Mapping — walk the space slowly"
    }

    // MARK: - Session: Navigation

    func startNavigationSession(mapName: String) {
        isRelocalized = false
        loadedDestinations = []
        selectedDestination = nil
        navigationError = nil
        distanceToDestination = nil
        currentPath = []
        isLoadingMap = true
        clearPath()
        selectedMapName = mapName

        do {
            let worldMap = try MapStore.load(name: mapName)
            let navAnchors = worldMap.anchors.compactMap { $0 as? NavigationAnchor }
            allLoadedAnchors = navAnchors
            loadedDestinations = navAnchors.filter(\.isDestination)

            let config = ARWorldTrackingConfiguration()
            config.planeDetection = [.horizontal, .vertical]
            config.environmentTexturing = .automatic
            config.initialWorldMap = worldMap

            if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
                config.sceneReconstruction = .mesh
            }

            sceneView.debugOptions = [.showFeaturePoints]
            sceneView.session.run(config, options: [.resetTracking, .removeExistingAnchors])

            let summary = MapStore.anchorSummary(for: worldMap)
            sessionInfoText = "Look around to localize... (\(summary.destinations) dest, \(summary.waypoints) waypoints)"
            isLoadingMap = false
        } catch {
            navigationError = "Failed to load \"\(mapName)\": \(error.localizedDescription)"
            sessionInfoText = "Map load failed"
            isLoadingMap = false
        }
    }

    func pauseSession() {
        sceneView.session.pause()
    }

    // MARK: - Mapping: Destinations

    func dropDestination(named name: String) {
        guard let frame = sceneView.session.currentFrame else {
            sessionInfoText = "Cannot drop — no AR frame"
            return
        }
        let anchor = NavigationAnchor(destinationName: name, kind: .destination, transform: frame.camera.transform)
        sceneView.session.add(anchor: anchor)
        destinations.append(anchor)
        allMappingAnchors.append(anchor)
        sessionInfoText = "Dropped destination \"\(name)\""
    }

    func removeDestination(_ anchor: NavigationAnchor) {
        sceneView.session.remove(anchor: anchor)
        destinations.removeAll { $0.identifier == anchor.identifier }
        allMappingAnchors.removeAll { $0.identifier == anchor.identifier }
    }

    // MARK: - Mapping: Waypoints

    func dropWaypointAtCamera() {
        guard let frame = sceneView.session.currentFrame else { return }
        dropWaypoint(at: frame.camera.transform)
    }

    private func dropWaypoint(at transform: simd_float4x4) {
        waypointCount += 1
        let name = "WP-\(waypointCount)"
        let anchor = NavigationAnchor(destinationName: name, kind: .waypoint, transform: transform)
        sceneView.session.add(anchor: anchor)
        allMappingAnchors.append(anchor)

        let col = transform.columns.3
        lastAutoWaypointPosition = SIMD3<Float>(col.x, col.y, col.z)
    }

    // MARK: - Mapping: Save

    func saveWorldMap(name: String) {
        isSavingMap = true
        mapSaveResult = nil
        sessionInfoText = "Saving map..."

        sceneView.session.getCurrentWorldMap { [weak self] worldMap, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isSavingMap = false

                guard let worldMap else {
                    let msg = error?.localizedDescription ?? "Unknown error"
                    self.mapSaveResult = "Save failed: \(msg)"
                    self.sessionInfoText = "Save failed"
                    return
                }

                do {
                    try MapStore.save(worldMap, name: name)
                    let summary = MapStore.anchorSummary(for: worldMap)
                    self.mapSaveResult = "Saved \"\(name)\" (\(summary.destinations) dest, \(summary.waypoints) waypoints)"
                    self.sessionInfoText = "Map saved successfully"
                    self.refreshSavedMaps()
                } catch {
                    self.mapSaveResult = "Save failed: \(error.localizedDescription)"
                    self.sessionInfoText = "Save failed"
                }
            }
        }
    }

    var canSaveMap: Bool {
        worldMappingStatus == .mapped || worldMappingStatus == .extending
    }

    // MARK: - Navigation: Destination Selection

    func selectDestination(_ destination: NavigationAnchor) {
        selectedDestination = destination
        recomputePath()
        sessionInfoText = "Navigating to \"\(destination.destinationName)\""
    }

    func clearNavigation() {
        selectedDestination = nil
        distanceToDestination = nil
        currentPath = []
        clearPath()
        if isRelocalized {
            sessionInfoText = "Select a destination"
        }
    }

    private func recomputePath() {
        guard let dest = selectedDestination,
              let pov = sceneView.pointOfView else { return }
        let cameraPos = pov.simdWorldPosition
        currentPath = PathFinder.findPath(from: cameraPos, to: dest, through: allLoadedAnchors)
    }

    // MARK: - Path Rendering

    private func clearPath() {
        pathContainerNode.childNodes.forEach { $0.removeFromParentNode() }
    }

    private func renderPath(_ positions: [SIMD3<Float>]) {
        clearPath()
        guard positions.count >= 2 else { return }

        // Walk along each segment and place dots at regular intervals
        var accumulated: Float = 0
        var dotPositions: [SIMD3<Float>] = []

        for i in 0..<(positions.count - 1) {
            let segStart = positions[i]
            let segEnd = positions[i + 1]
            let segDir = segEnd - segStart
            let segLen = simd_length(segDir)
            guard segLen > 0.01 else { continue }
            let segNorm = simd_normalize(segDir)

            var offset = pathDotSpacing - accumulated
            while offset <= segLen {
                let pos = segStart + segNorm * offset
                dotPositions.append(pos)
                offset += pathDotSpacing
            }
            accumulated = segLen - (offset - pathDotSpacing)
        }

        let totalDots = dotPositions.count
        for (i, pos) in dotPositions.enumerated() {
            let t = totalDots > 1 ? Float(i) / Float(totalDots - 1) : 1.0
            let isLast = i == totalDots - 1

            let node: SCNNode
            if isLast {
                node = SCNNode(geometry: pathArrowGeometry.copy() as? SCNGeometry)
            } else {
                node = SCNNode(geometry: pathDotGeometry.copy() as? SCNGeometry)
            }

            node.geometry?.firstMaterial?.diffuse.contents = UIColor(
                red: 0,
                green: CGFloat(0.8 - t * 0.3),
                blue: CGFloat(0.5 + t * 0.5),
                alpha: 0.85
            )
            node.simdWorldPosition = pos
            pathContainerNode.addChildNode(node)
        }
    }

    // MARK: - Helpers

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
}

// MARK: - ARSCNViewDelegate

extension ARSessionManager: ARSCNViewDelegate {

    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        guard let navAnchor = anchor as? NavigationAnchor else { return nil }

        if navAnchor.isWaypoint {
            return waypointNode()
        } else {
            return destinationNode(for: navAnchor)
        }
    }

    private func waypointNode() -> SCNNode {
        let sphere = SCNSphere(radius: 0.025)
        sphere.segmentCount = 8
        sphere.firstMaterial?.diffuse.contents = UIColor.systemYellow.withAlphaComponent(0.5)
        sphere.firstMaterial?.lightingModel = .constant
        return SCNNode(geometry: sphere)
    }

    private func destinationNode(for anchor: NavigationAnchor) -> SCNNode {
        let isNavMode = appMode == .navigation
        let color: UIColor = isNavMode ? .systemGreen : .systemBlue

        let sphere = SCNSphere(radius: 0.05)
        sphere.firstMaterial?.diffuse.contents = color
        sphere.firstMaterial?.lightingModel = .physicallyBased
        let sphereNode = SCNNode(geometry: sphere)

        let text = SCNText(string: anchor.destinationName, extrusionDepth: 0.5)
        text.font = UIFont.systemFont(ofSize: 4, weight: .bold)
        text.firstMaterial?.diffuse.contents = UIColor.white
        text.flatness = 0.1

        let textNode = SCNNode(geometry: text)
        let (min, max) = textNode.boundingBox
        let dx = (max.x - min.x) / 2
        textNode.position = SCNVector3(-dx, 0.06, 0)
        textNode.scale = SCNVector3(0.01, 0.01, 0.01)

        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .Y
        textNode.constraints = [billboard]

        let container = SCNNode()
        container.addChildNode(sphereNode)
        container.addChildNode(textNode)

        if isNavMode {
            let pulse = SCNAction.sequence([
                .scale(to: 1.2, duration: 0.5),
                .scale(to: 1.0, duration: 0.5)
            ])
            sphereNode.runAction(.repeatForever(pulse))
        }

        return container
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard appMode == .navigation,
              isRelocalized,
              selectedDestination != nil,
              let pov = sceneView.pointOfView else {
            if !pathContainerNode.childNodes.isEmpty {
                clearPath()
                DispatchQueue.main.async { [weak self] in
                    self?.distanceToDestination = nil
                }
            }
            return
        }

        guard time - lastPathUpdateTime > 0.15 else { return }
        lastPathUpdateTime = time

        let cameraPos = pov.simdWorldPosition

        // Recompute path from current position
        if let dest = selectedDestination {
            currentPath = PathFinder.findPath(from: cameraPos, to: dest, through: allLoadedAnchors)
        }

        // Compute walking distance along path segments
        var totalDist: Float = 0
        if currentPath.count >= 2 {
            for i in 0..<(currentPath.count - 1) {
                totalDist += simd_length(currentPath[i + 1] - currentPath[i])
            }
        }

        renderPath(currentPath)

        DispatchQueue.main.async { [weak self] in
            self?.distanceToDestination = totalDist
        }
    }
}

// MARK: - ARSessionDelegate

extension ARSessionManager: ARSessionDelegate {

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let mapping = frame.worldMappingStatus
        let tracking = frame.camera.trackingState

        // Auto-waypoint: drop a waypoint every ~1.5m while mapping
        if appMode == .mapping && isAutoWaypointEnabled {
            let col = frame.camera.transform.columns.3
            let cameraPos = SIMD3<Float>(col.x, col.y, col.z)

            if let lastPos = lastAutoWaypointPosition {
                if simd_length(cameraPos - lastPos) >= autoWaypointInterval {
                    DispatchQueue.main.async { [weak self] in
                        self?.dropWaypoint(at: frame.camera.transform)
                    }
                }
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.lastAutoWaypointPosition = cameraPos
                }
            }
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.worldMappingStatus = mapping
            self.trackingState = tracking

            if self.appMode == .navigation && !self.isRelocalized {
                if case .normal = tracking {
                    self.isRelocalized = true
                }
            }

            self.updateSessionInfo()
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.sessionInfoText = "Session error: \(error.localizedDescription)"
        }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        DispatchQueue.main.async { [weak self] in
            self?.sessionInfoText = "Session interrupted"
        }
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        DispatchQueue.main.async { [weak self] in
            self?.sessionInfoText = "Session resumed"
        }
    }

    // MARK: - Private

    private func updateSessionInfo() {
        if isSavingMap { return }

        switch trackingState {
        case .notAvailable:
            sessionInfoText = "AR not available on this device"
        case .limited(let reason):
            switch reason {
            case .initializing:
                sessionInfoText = appMode == .navigation
                    ? "Look around slowly to localize..."
                    : "Initializing — move the device slowly"
            case .excessiveMotion:
                sessionInfoText = "Too much motion — slow down"
            case .insufficientFeatures:
                sessionInfoText = "Not enough detail — point at a textured surface"
            case .relocalizing:
                sessionInfoText = "Relocalizing — revisit a previously mapped area"
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
                        sessionInfoText = String(format: "→ \"%@\" — %.1f m", dest.destinationName, dist)
                    } else {
                        sessionInfoText = "Navigating to \"\(dest.destinationName)\""
                    }
                } else {
                    sessionInfoText = "Localized — select a destination"
                }
            }
        }
    }
}
