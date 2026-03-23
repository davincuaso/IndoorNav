import Foundation
import ARKit
import SceneKit
import Combine

final class ARManager: NSObject {

    // MARK: - Properties

    private let sceneView: ARSCNView
    private weak var viewModel: NavigationViewModel?
    private let pathRenderer = PathRenderer()
    private let obstaclePathfinder = ObstacleAwarePathfinder()

    private var lastPathUpdateTime: TimeInterval = 0
    private let pathUpdateInterval: TimeInterval = 0.15

    private var meshAnchors: [ARMeshAnchor] = []
    private var lastMeshUpdateTime: TimeInterval = 0
    private let meshUpdateInterval: TimeInterval = 1.0  // Update obstacles every second

    var arView: ARSCNView { sceneView }
    var hasObstacleGraph: Bool { obstaclePathfinder.hasGraph }
    var obstacleCount: Int { obstaclePathfinder.obstacleCount }

    // MARK: - Public Accessors

    func getMeshAnchors() -> [ARMeshAnchor] {
        return meshAnchors
    }

    // MARK: - Initialization

    init(viewModel: NavigationViewModel) {
        self.sceneView = ARSCNView()
        self.viewModel = viewModel
        super.init()

        sceneView.delegate = self
        sceneView.session.delegate = self
        sceneView.automaticallyUpdatesLighting = true
        sceneView.scene.rootNode.addChildNode(pathRenderer.rootNode)

        // Enable AR occlusion for realistic rendering
        configureOcclusion()
    }

    private func configureOcclusion() {
        // Enable person occlusion if available
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
            // Will be configured in session config
        }

        // Set rendering order for path to appear behind real objects
        pathRenderer.rootNode.renderingOrder = -1
    }

    func cleanup() {
        sceneView.session.pause()
        sceneView.delegate = nil
        sceneView.session.delegate = nil
        pathRenderer.clear()
    }

    // MARK: - Session Management: Mapping

    func startMappingSession() {
        pathRenderer.clear()
        meshAnchors.removeAll()

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic

        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .meshWithClassification
            Task { @MainActor [weak self] in
                self?.viewModel?.isSceneReconstructionSupported = true
            }
        }

        // Enable occlusion using scene depth
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }

        // Enable person segmentation for occlusion
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
            config.frameSemantics.insert(.personSegmentationWithDepth)
        }

        sceneView.debugOptions = [.showFeaturePoints]
        sceneView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    // MARK: - Session Management: Navigation

    func startNavigationSession(mapName: String) {
        pathRenderer.clear()

        do {
            guard MapStore.exists(name: mapName) else {
                Task { @MainActor [weak self] in
                    self?.viewModel?.currentError = .mapNotFound(name: mapName)
                }
                return
            }

            let worldMap = try MapStore.load(name: mapName)
            let navAnchors = worldMap.anchors.compactMap { $0 as? NavigationAnchor }
            let summary = MapStore.anchorSummary(for: worldMap)

            Task { @MainActor [weak self] in
                self?.viewModel?.handleMapLoaded(anchors: navAnchors, summary: summary)
            }

            let config = ARWorldTrackingConfiguration()
            config.planeDetection = [.horizontal, .vertical]
            config.environmentTexturing = .automatic
            config.initialWorldMap = worldMap

            if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
                config.sceneReconstruction = .meshWithClassification
            }

            // Enable occlusion using scene depth
            if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                config.frameSemantics.insert(.sceneDepth)
            }

            // Enable person segmentation for occlusion
            if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
                config.frameSemantics.insert(.personSegmentationWithDepth)
            }

            sceneView.debugOptions = [.showFeaturePoints]
            sceneView.session.run(config, options: [.resetTracking, .removeExistingAnchors])

        } catch {
            Task { @MainActor [weak self] in
                self?.viewModel?.handleMapLoadError(error, mapName: mapName)
            }
        }
    }

    func pauseSession() {
        sceneView.session.pause()
    }

    // MARK: - Anchor Management

    func dropDestination(named name: String) -> NavigationAnchor? {
        guard let frame = sceneView.session.currentFrame else {
            Task { @MainActor [weak self] in
                self?.viewModel?.currentError = .noARFrame
            }
            return nil
        }

        let anchor = NavigationAnchor(destinationName: name, kind: .destination, transform: frame.camera.transform)
        sceneView.session.add(anchor: anchor)
        return anchor
    }

    func dropWaypoint(named name: String) -> (anchor: NavigationAnchor, position: SIMD3<Float>)? {
        guard let frame = sceneView.session.currentFrame else { return nil }

        let anchor = NavigationAnchor(destinationName: name, kind: .waypoint, transform: frame.camera.transform)
        sceneView.session.add(anchor: anchor)

        let col = frame.camera.transform.columns.3
        let position = SIMD3<Float>(col.x, col.y, col.z)

        return (anchor, position)
    }

    func removeAnchor(_ anchor: NavigationAnchor) {
        sceneView.session.remove(anchor: anchor)
    }

    func getCurrentCameraPosition() -> SIMD3<Float>? {
        guard let pov = sceneView.pointOfView else { return nil }
        return pov.simdWorldPosition
    }

    // MARK: - Map Saving

    func saveWorldMap(name: String, completion: @escaping (Result<(destinations: Int, waypoints: Int), Error>) -> Void) {
        sceneView.session.getCurrentWorldMap { worldMap, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let worldMap = worldMap else {
                completion(.failure(AppError.mapSaveFailed(underlying: nil)))
                return
            }

            do {
                try MapStore.save(worldMap, name: name)
                let summary = MapStore.anchorSummary(for: worldMap)
                completion(.success(summary))
            } catch {
                completion(.failure(error))
            }
        }
    }

    // MARK: - Path Rendering

    func updatePathIfNeeded(
        to destination: NavigationAnchor,
        through anchors: [NavigationAnchor],
        currentTime: TimeInterval
    ) -> Float? {
        guard currentTime - lastPathUpdateTime > pathUpdateInterval else { return nil }
        lastPathUpdateTime = currentTime

        guard let cameraPos = getCurrentCameraPosition() else { return nil }

        // Use obstacle-aware pathfinding if mesh data is available
        let path: [SIMD3<Float>]
        if obstaclePathfinder.hasGraph {
            path = obstaclePathfinder.findPath(from: cameraPos, to: destination, through: anchors)
        } else {
            path = PathFinder.findPath(from: cameraPos, to: destination, through: anchors)
        }

        pathRenderer.render(path: path)
        return pathRenderer.pathDistance(for: path)
    }

    func clearPath() {
        pathRenderer.clear()
    }

    // MARK: - Mesh Processing

    func buildObstacleGraph(withWaypoints waypoints: [NavigationAnchor]) {
        guard !meshAnchors.isEmpty else { return }
        obstaclePathfinder.buildGraph(from: meshAnchors, withWaypoints: waypoints)
    }

    private func updateMeshAnchorsIfNeeded(currentTime: TimeInterval) {
        guard currentTime - lastMeshUpdateTime > meshUpdateInterval else { return }
        lastMeshUpdateTime = currentTime

        if obstaclePathfinder.hasGraph && !meshAnchors.isEmpty {
            obstaclePathfinder.updateObstacles(from: meshAnchors)
        }
    }
}

// MARK: - ARSCNViewDelegate

extension ARManager: ARSCNViewDelegate {

    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        guard let navAnchor = anchor as? NavigationAnchor else { return nil }

        if navAnchor.isWaypoint {
            return createWaypointNode()
        } else {
            // Default to mapping mode appearance; will be updated if needed
            return createDestinationNode(for: navAnchor, isNavMode: false)
        }
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        Task { @MainActor [weak self] in
            guard let self = self,
                  let viewModel = self.viewModel else { return }

            guard viewModel.appMode == .navigation,
                  viewModel.isRelocalized,
                  let destination = viewModel.selectedDestination else {
                if !self.pathRenderer.rootNode.childNodes.isEmpty {
                    self.clearPath()
                    viewModel.distanceToDestination = nil
                }
                return
            }

            if let distance = self.updatePathIfNeeded(
                to: destination,
                through: viewModel.allLoadedAnchors,
                currentTime: time
            ) {
                viewModel.updateDistance(distance)
            }
        }
    }

    // MARK: - Node Creation

    private func createWaypointNode() -> SCNNode {
        let sphere = SCNSphere(radius: 0.025)
        sphere.segmentCount = 8
        sphere.firstMaterial?.diffuse.contents = UIColor.systemYellow.withAlphaComponent(0.5)
        sphere.firstMaterial?.lightingModel = .constant
        return SCNNode(geometry: sphere)
    }

    private func createDestinationNode(for anchor: NavigationAnchor, isNavMode: Bool) -> SCNNode {
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
}

// MARK: - ARSessionDelegate

extension ARManager: ARSessionDelegate {

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let mapping = frame.worldMappingStatus
        let tracking = frame.camera.trackingState
        let col = frame.camera.transform.columns.3
        let cameraPos = SIMD3<Float>(col.x, col.y, col.z)

        Task { @MainActor [weak self] in
            guard let self = self,
                  let viewModel = self.viewModel else { return }

            // Auto-waypoint logic
            if viewModel.appMode == .mapping && viewModel.isAutoWaypointEnabled {
                if let lastPos = viewModel.lastAutoWaypointPosition {
                    if simd_length(cameraPos - lastPos) >= viewModel.autoWaypointInterval {
                        let wpCount = viewModel.waypointCount + 1
                        let name = "WP-\(wpCount)"
                        if let result = self.dropWaypoint(named: name) {
                            viewModel.addWaypoint(result.anchor, at: result.position)
                        }
                    }
                } else {
                    viewModel.lastAutoWaypointPosition = cameraPos
                }
            }

            viewModel.updateTrackingState(tracking, mappingStatus: mapping)
        }
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors {
            if let meshAnchor = anchor as? ARMeshAnchor {
                meshAnchors.append(meshAnchor)
            }
        }

        // Build obstacle graph once we have enough mesh data
        let meshCount = meshAnchors.count
        let hasGraph = obstaclePathfinder.hasGraph

        Task { @MainActor [weak self] in
            guard let self = self,
                  let viewModel = self.viewModel else { return }

            if viewModel.appMode == .navigation,
               viewModel.isRelocalized,
               !hasGraph,
               meshCount >= 3 {
                self.buildObstacleGraph(withWaypoints: viewModel.allLoadedAnchors)
            }
        }
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        for anchor in anchors {
            if let meshAnchor = anchor as? ARMeshAnchor {
                if let index = meshAnchors.firstIndex(where: { $0.identifier == meshAnchor.identifier }) {
                    meshAnchors[index] = meshAnchor
                }
            }
        }
    }

    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        for anchor in anchors {
            if let meshAnchor = anchor as? ARMeshAnchor {
                meshAnchors.removeAll { $0.identifier == meshAnchor.identifier }
            }
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.viewModel?.handleSessionError(error)
        }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        Task { @MainActor [weak self] in
            self?.viewModel?.handleSessionInterrupted()
        }
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        Task { @MainActor [weak self] in
            self?.viewModel?.handleSessionResumed()
        }
    }
}
