import SceneKit
import simd

final class PathRenderer {

    enum Style {
        case dots
        case chevrons
        case dottedLine
    }

    private let containerNode = SCNNode()
    private let chevronSpacing: Float = 0.35
    private let dotSpacing: Float = 0.15

    var style: Style = .chevrons
    var rootNode: SCNNode { containerNode }
    var enableOcclusion: Bool = true

    // Occlusion configuration
    private func configureOcclusionMaterial(_ material: SCNMaterial) {
        guard enableOcclusion else { return }

        // Enable depth testing so path renders behind real-world objects
        material.readsFromDepthBuffer = true
        material.writesToDepthBuffer = true

        // Use blend mode for semi-transparent occlusion effect
        material.blendMode = .alpha
    }

    // Chevron geometry (arrow pointing forward)
    private func createChevronGeometry() -> SCNGeometry {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: -0.02, y: -0.015))
        path.addLine(to: CGPoint(x: 0, y: 0.015))
        path.addLine(to: CGPoint(x: 0.02, y: -0.015))
        path.addLine(to: CGPoint(x: 0.015, y: -0.015))
        path.addLine(to: CGPoint(x: 0, y: 0.005))
        path.addLine(to: CGPoint(x: -0.015, y: -0.015))
        path.close()

        let shape = SCNShape(path: path, extrusionDepth: 0.003)
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.systemCyan
        material.emission.contents = UIColor.systemCyan.withAlphaComponent(0.5)
        material.lightingModel = .constant
        material.isDoubleSided = true
        configureOcclusionMaterial(material)
        shape.materials = [material]
        return shape
    }

    private func createDotGeometry() -> SCNGeometry {
        let sphere = SCNSphere(radius: 0.012)
        sphere.segmentCount = 8
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.systemCyan
        material.emission.contents = UIColor.systemCyan.withAlphaComponent(0.3)
        material.lightingModel = .constant
        configureOcclusionMaterial(material)
        sphere.materials = [material]
        return sphere
    }

    private func createDestinationGeometry() -> SCNGeometry {
        let cylinder = SCNCylinder(radius: 0.06, height: 0.15)
        cylinder.radialSegmentCount = 16
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.systemGreen
        material.emission.contents = UIColor.systemGreen.withAlphaComponent(0.4)
        material.lightingModel = .constant
        material.transparency = 0.7
        configureOcclusionMaterial(material)
        cylinder.materials = [material]
        return cylinder
    }

    func clear() {
        containerNode.enumerateChildNodes { node, _ in
            node.removeAllActions()
            node.removeFromParentNode()
        }
    }

    func render(path positions: [SIMD3<Float>]) {
        clear()
        guard positions.count >= 2 else { return }

        switch style {
        case .dots:
            renderDots(path: positions)
        case .chevrons:
            renderChevrons(path: positions)
        case .dottedLine:
            renderDottedLine(path: positions)
        }
    }

    func pathDistance(for positions: [SIMD3<Float>]) -> Float {
        guard positions.count >= 2 else { return 0 }

        var total: Float = 0
        for i in 0..<(positions.count - 1) {
            total += simd_length(positions[i + 1] - positions[i])
        }
        return total
    }

    // MARK: - Chevron Rendering

    private func renderChevrons(path: [SIMD3<Float>]) {
        let pathData = interpolateWithDirection(along: path, spacing: chevronSpacing)
        let totalChevrons = pathData.count

        for (index, data) in pathData.enumerated() {
            let progress = totalChevrons > 1 ? Float(index) / Float(totalChevrons - 1) : 1.0
            let isLast = index == totalChevrons - 1

            let node: SCNNode
            if isLast {
                node = createDestinationNode()
            } else {
                node = createChevronNode(progress: progress, direction: data.direction)
            }

            node.simdWorldPosition = data.position
            addPulseAnimation(to: node, index: index, total: totalChevrons)
            containerNode.addChildNode(node)
        }
    }

    private func createChevronNode(progress: Float, direction: SIMD3<Float>) -> SCNNode {
        let geometry = createChevronGeometry()

        // Color gradient from cyan to blue as you approach destination
        let color = UIColor(
            red: CGFloat(progress * 0.2),
            green: CGFloat(0.8 - progress * 0.3),
            blue: CGFloat(0.8 + progress * 0.2),
            alpha: 0.9
        )
        geometry.firstMaterial?.diffuse.contents = color
        geometry.firstMaterial?.emission.contents = color.withAlphaComponent(0.4)

        let node = SCNNode(geometry: geometry)

        // Rotate chevron to face movement direction (on XZ plane)
        let angle = atan2(direction.x, direction.z)
        node.simdEulerAngles = SIMD3<Float>(-Float.pi / 2, angle, 0)

        return node
    }

    private func createDestinationNode() -> SCNNode {
        let geometry = createDestinationGeometry()
        let node = SCNNode(geometry: geometry)

        // Pulsing animation for destination
        let pulse = SCNAction.sequence([
            .scale(to: 1.3, duration: 0.6),
            .scale(to: 1.0, duration: 0.6)
        ])
        node.runAction(.repeatForever(pulse))

        return node
    }

    private func addPulseAnimation(to node: SCNNode, index: Int, total: Int) {
        // Staggered wave animation - chevrons "flow" towards destination
        let delay = Double(index) * 0.08
        let duration = 0.5

        let fadeOut = SCNAction.fadeOpacity(to: 0.3, duration: duration)
        let fadeIn = SCNAction.fadeOpacity(to: 1.0, duration: duration)
        let sequence = SCNAction.sequence([
            .wait(duration: delay.truncatingRemainder(dividingBy: 1.0)),
            fadeOut,
            fadeIn
        ])

        node.runAction(.repeatForever(sequence))
    }

    // MARK: - Dot Rendering

    private func renderDots(path: [SIMD3<Float>]) {
        let positions = interpolatePositions(along: path, spacing: dotSpacing)
        let totalDots = positions.count

        for (index, position) in positions.enumerated() {
            let progress = totalDots > 1 ? Float(index) / Float(totalDots - 1) : 1.0
            let isLast = index == totalDots - 1

            let node: SCNNode
            if isLast {
                node = createDestinationNode()
            } else {
                node = createDotNode(progress: progress)
            }

            node.simdWorldPosition = position
            containerNode.addChildNode(node)
        }
    }

    private func createDotNode(progress: Float) -> SCNNode {
        let geometry = createDotGeometry()

        let color = UIColor(
            red: 0,
            green: CGFloat(0.8 - progress * 0.3),
            blue: CGFloat(0.5 + progress * 0.5),
            alpha: 0.85
        )
        geometry.firstMaterial?.diffuse.contents = color

        return SCNNode(geometry: geometry)
    }

    // MARK: - Dotted Line Rendering

    private func renderDottedLine(path: [SIMD3<Float>]) {
        guard path.count >= 2 else { return }

        // Create a continuous tube along the path
        for i in 0..<(path.count - 1) {
            let start = path[i]
            let end = path[i + 1]
            let segment = createLineSegment(from: start, to: end, progress: Float(i) / Float(path.count - 1))
            containerNode.addChildNode(segment)
        }

        // Add destination marker
        let destNode = createDestinationNode()
        destNode.simdWorldPosition = path.last!
        containerNode.addChildNode(destNode)
    }

    private func createLineSegment(from start: SIMD3<Float>, to end: SIMD3<Float>, progress: Float) -> SCNNode {
        let direction = end - start
        let length = simd_length(direction)

        let tube = SCNCylinder(radius: 0.008, height: CGFloat(length))
        tube.radialSegmentCount = 8

        let color = UIColor(
            red: CGFloat(progress * 0.2),
            green: CGFloat(0.7 - progress * 0.2),
            blue: CGFloat(0.9),
            alpha: 0.8
        )
        tube.firstMaterial?.diffuse.contents = color
        tube.firstMaterial?.emission.contents = color.withAlphaComponent(0.3)
        tube.firstMaterial?.lightingModel = .constant

        let node = SCNNode(geometry: tube)
        node.simdPosition = (start + end) / 2

        // Orient cylinder along the direction
        let normalized = simd_normalize(direction)
        let up = SIMD3<Float>(0, 1, 0)
        let axis = simd_cross(up, normalized)
        let angle = acos(simd_dot(up, normalized))

        if simd_length(axis) > 0.001 {
            node.simdRotation = SIMD4<Float>(axis.x, axis.y, axis.z, angle)
        }

        return node
    }

    // MARK: - Path Interpolation

    private struct PathPoint {
        let position: SIMD3<Float>
        let direction: SIMD3<Float>
    }

    private func interpolateWithDirection(along path: [SIMD3<Float>], spacing: Float) -> [PathPoint] {
        var result: [PathPoint] = []
        var accumulated: Float = 0

        for i in 0..<(path.count - 1) {
            let segmentStart = path[i]
            let segmentEnd = path[i + 1]
            let direction = segmentEnd - segmentStart
            let length = simd_length(direction)

            guard length > 0.01 else { continue }

            let normalized = simd_normalize(direction)
            var offset = spacing - accumulated

            while offset <= length {
                let position = segmentStart + normalized * offset
                result.append(PathPoint(position: position, direction: normalized))
                offset += spacing
            }

            accumulated = length - (offset - spacing)
        }

        // Always add final destination point
        if let last = path.last, let secondLast = path.dropLast().last {
            let finalDir = simd_normalize(last - secondLast)
            result.append(PathPoint(position: last, direction: finalDir))
        }

        return result
    }

    private func interpolatePositions(along path: [SIMD3<Float>], spacing: Float) -> [SIMD3<Float>] {
        interpolateWithDirection(along: path, spacing: spacing).map(\.position)
    }
}
