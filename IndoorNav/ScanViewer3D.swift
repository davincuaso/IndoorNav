import SwiftUI
import SceneKit

struct ScanViewer3D: UIViewRepresentable {
    let meshData: MeshExportData?
    let zone: MapZone
    var colorScheme: MeshColorScheme = .height
    var showDestinations: Bool = true
    var showWireframe: Bool = false

    func makeUIView(context: Context) -> SCNView {
        let sceneView = SCNView()
        sceneView.backgroundColor = UIColor.systemBackground
        sceneView.autoenablesDefaultLighting = true
        sceneView.allowsCameraControl = true
        sceneView.antialiasingMode = .multisampling4X

        let scene = SCNScene()
        sceneView.scene = scene

        // Add ambient light
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.intensity = 500
        ambientLight.light?.color = UIColor.white
        scene.rootNode.addChildNode(ambientLight)

        // Add directional light
        let directionalLight = SCNNode()
        directionalLight.light = SCNLight()
        directionalLight.light?.type = .directional
        directionalLight.light?.intensity = 800
        directionalLight.light?.castsShadow = true
        directionalLight.simdPosition = SIMD3<Float>(5, 10, 5)
        directionalLight.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(directionalLight)

        // Setup camera
        let camera = SCNCamera()
        camera.usesOrthographicProjection = false
        camera.fieldOfView = 60
        camera.zNear = 0.1
        camera.zFar = 100

        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.name = "camera"
        scene.rootNode.addChildNode(cameraNode)

        context.coordinator.sceneView = sceneView
        context.coordinator.cameraNode = cameraNode

        return sceneView
    }

    func updateUIView(_ sceneView: SCNView, context: Context) {
        guard let scene = sceneView.scene else { return }

        // Remove existing mesh
        scene.rootNode.childNodes.filter { $0.name == "meshContainer" }.forEach { $0.removeFromParentNode() }
        scene.rootNode.childNodes.filter { $0.name == "destinationMarkers" }.forEach { $0.removeFromParentNode() }
        scene.rootNode.childNodes.filter { $0.name == "floor" }.forEach { $0.removeFromParentNode() }

        if let meshData = meshData {
            // Add mesh
            let meshNode = MeshDataStore.shared.createSceneNode(from: meshData, colorScheme: colorScheme)
            meshNode.name = "meshContainer"

            if showWireframe {
                meshNode.enumerateChildNodes { node, _ in
                    node.geometry?.firstMaterial?.fillMode = .lines
                }
            }

            scene.rootNode.addChildNode(meshNode)

            // Position camera to view entire mesh
            let center = meshData.boundingBox.center
            let maxDim = meshData.boundingBox.maxDimension
            let cameraDistance = maxDim * 2.0

            if let cameraNode = context.coordinator.cameraNode {
                cameraNode.simdPosition = SIMD3<Float>(center.x, center.y + maxDim * 0.5, center.z + cameraDistance)
                cameraNode.look(at: SCNVector3(center.x, center.y, center.z))
            }

            // Add floor grid
            let floorNode = createFloorGrid(size: maxDim * 2, at: meshData.boundingBox.min.y - 0.01)
            floorNode.name = "floor"
            scene.rootNode.addChildNode(floorNode)

            // Add destination markers if available
            if showDestinations {
                let markersNode = createDestinationMarkers(for: zone, boundingBox: meshData.boundingBox)
                markersNode.name = "destinationMarkers"
                scene.rootNode.addChildNode(markersNode)
            }
        } else {
            // Show placeholder
            let placeholder = createPlaceholder()
            placeholder.name = "meshContainer"
            scene.rootNode.addChildNode(placeholder)

            if let cameraNode = context.coordinator.cameraNode {
                cameraNode.simdPosition = SIMD3<Float>(0, 2, 5)
                cameraNode.look(at: SCNVector3(0, 0, 0))
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var sceneView: SCNView?
        var cameraNode: SCNNode?
    }

    // MARK: - Helper Methods

    private func createFloorGrid(size: Float, at y: Float) -> SCNNode {
        let gridSize = Int(size / 0.5) + 1
        let containerNode = SCNNode()

        // Create grid lines
        for i in -gridSize...gridSize {
            let offset = Float(i) * 0.5

            // X-axis lines
            let xLine = SCNBox(width: CGFloat(size * 2), height: 0.002, length: 0.002, chamferRadius: 0)
            xLine.firstMaterial?.diffuse.contents = UIColor.systemGray4
            let xNode = SCNNode(geometry: xLine)
            xNode.simdPosition = SIMD3<Float>(0, y, offset)
            containerNode.addChildNode(xNode)

            // Z-axis lines
            let zLine = SCNBox(width: 0.002, height: 0.002, length: CGFloat(size * 2), chamferRadius: 0)
            zLine.firstMaterial?.diffuse.contents = UIColor.systemGray4
            let zNode = SCNNode(geometry: zLine)
            zNode.simdPosition = SIMD3<Float>(offset, y, 0)
            containerNode.addChildNode(zNode)
        }

        return containerNode
    }

    private func createDestinationMarkers(for zone: MapZone, boundingBox: BoundingBox) -> SCNNode {
        let containerNode = SCNNode()

        // Try to load destinations from the map
        guard let worldMap = try? MapStore.load(name: zone.mapFileName) else {
            return containerNode
        }

        let destinations = worldMap.anchors.compactMap { $0 as? NavigationAnchor }.filter(\.isDestination)

        for destination in destinations {
            let markerNode = createDestinationMarker(for: destination)
            containerNode.addChildNode(markerNode)
        }

        return containerNode
    }

    private func createDestinationMarker(for anchor: NavigationAnchor) -> SCNNode {
        let containerNode = SCNNode()
        containerNode.simdPosition = anchor.position

        // Pin base
        let sphere = SCNSphere(radius: 0.08)
        sphere.firstMaterial?.diffuse.contents = UIColor.systemBlue
        sphere.firstMaterial?.emission.contents = UIColor.systemBlue.withAlphaComponent(0.3)
        let sphereNode = SCNNode(geometry: sphere)
        containerNode.addChildNode(sphereNode)

        // Pin stem
        let cylinder = SCNCylinder(radius: 0.015, height: 0.3)
        cylinder.firstMaterial?.diffuse.contents = UIColor.systemBlue
        let cylinderNode = SCNNode(geometry: cylinder)
        cylinderNode.simdPosition = SIMD3<Float>(0, 0.15, 0)
        containerNode.addChildNode(cylinderNode)

        // Label
        let text = SCNText(string: anchor.destinationName, extrusionDepth: 0.5)
        text.font = UIFont.systemFont(ofSize: 3, weight: .semibold)
        text.firstMaterial?.diffuse.contents = UIColor.white
        text.flatness = 0.1

        let textNode = SCNNode(geometry: text)
        let (min, max) = textNode.boundingBox
        let textWidth = max.x - min.x
        textNode.position = SCNVector3(-textWidth * 0.01 / 2, 0.35, 0)
        textNode.scale = SCNVector3(0.01, 0.01, 0.01)

        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = [.X, .Y]
        textNode.constraints = [billboard]
        containerNode.addChildNode(textNode)

        // Pulse animation
        let pulse = SCNAction.sequence([
            .scale(to: 1.1, duration: 0.8),
            .scale(to: 1.0, duration: 0.8)
        ])
        sphereNode.runAction(.repeatForever(pulse))

        return containerNode
    }

    private func createPlaceholder() -> SCNNode {
        let containerNode = SCNNode()

        // Create a simple cube as placeholder
        let box = SCNBox(width: 1, height: 0.5, length: 1, chamferRadius: 0.05)
        box.firstMaterial?.diffuse.contents = UIColor.systemGray5
        box.firstMaterial?.transparency = 0.5

        let boxNode = SCNNode(geometry: box)
        boxNode.simdPosition = SIMD3<Float>(0, 0.25, 0)
        containerNode.addChildNode(boxNode)

        // Add text
        let text = SCNText(string: "No scan data", extrusionDepth: 0.5)
        text.font = UIFont.systemFont(ofSize: 4, weight: .medium)
        text.firstMaterial?.diffuse.contents = UIColor.secondaryLabel
        text.flatness = 0.1

        let textNode = SCNNode(geometry: text)
        let (min, max) = textNode.boundingBox
        let textWidth = max.x - min.x
        textNode.position = SCNVector3(-textWidth * 0.01 / 2, 0.7, 0)
        textNode.scale = SCNVector3(0.01, 0.01, 0.01)
        containerNode.addChildNode(textNode)

        return containerNode
    }
}

// MARK: - Preview

struct ScanViewer3D_Previews: PreviewProvider {
    static var previews: some View {
        ScanViewer3D(
            meshData: nil,
            zone: MapZone(name: "Test Zone")
        )
    }
}
