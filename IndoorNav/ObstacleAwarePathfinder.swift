import GameplayKit
import ARKit
import simd

final class ObstacleAwarePathfinder {

    private var obstacleGraph: GKObstacleGraph<GKGraphNode2D>?
    private var obstacles: [GKPolygonObstacle] = []
    private var waypointNodes: [UUID: GKGraphNode2D] = [:]
    private let meshExtractor = MeshObstacleExtractor()

    private var floorHeight: Float = 0
    private let pathSmoothing: Float = 0.3  // Catmull-Rom tension

    // MARK: - Graph Building

    func buildGraph(
        from meshAnchors: [ARMeshAnchor],
        withWaypoints waypoints: [NavigationAnchor]
    ) {
        // Estimate floor height from mesh
        floorHeight = meshExtractor.estimateFloorHeight(from: meshAnchors)

        // Extract obstacles from LiDAR mesh
        obstacles = meshExtractor.processAnchors(meshAnchors, relativeTo: floorHeight)

        // Create obstacle graph with buffer radius for character width
        let bufferRadius: Float = 0.4  // 40cm buffer for human width
        obstacleGraph = GKObstacleGraph(
            obstacles: obstacles,
            bufferRadius: bufferRadius
        )

        // Add waypoint nodes to graph
        waypointNodes.removeAll()
        for waypoint in waypoints {
            let pos2D = vector_float2(waypoint.position.x, waypoint.position.z)
            let node = GKGraphNode2D(point: pos2D)
            waypointNodes[waypoint.identifier] = node
            obstacleGraph?.connectUsingObstacles(node: node)
        }
    }

    func updateObstacles(from meshAnchors: [ARMeshAnchor]) {
        guard obstacleGraph != nil else { return }

        // Re-extract obstacles with updated mesh
        let newObstacles = meshExtractor.processAnchors(meshAnchors, relativeTo: floorHeight)

        // Only update if obstacles changed significantly
        if newObstacles.count != obstacles.count {
            obstacles = newObstacles

            // Rebuild graph with new obstacles
            let waypointList = Array(waypointNodes.values)
            obstacleGraph = GKObstacleGraph(
                obstacles: obstacles,
                bufferRadius: 0.4
            )

            // Re-add waypoint nodes
            for node in waypointList {
                obstacleGraph?.connectUsingObstacles(node: node)
            }
        }
    }

    // MARK: - Pathfinding

    func findPath(
        from start: SIMD3<Float>,
        to destination: NavigationAnchor,
        through waypoints: [NavigationAnchor]
    ) -> [SIMD3<Float>] {
        // Fallback to basic pathfinding if no mesh data
        guard let graph = obstacleGraph else {
            return PathFinder.findPath(from: start, to: destination, through: waypoints)
        }

        let startPos2D = vector_float2(start.x, start.z)
        let endPos2D = vector_float2(destination.position.x, destination.position.z)

        // Create temporary nodes for start and end
        let startNode = GKGraphNode2D(point: startPos2D)
        let endNode = GKGraphNode2D(point: endPos2D)

        graph.connectUsingObstacles(node: startNode)
        graph.connectUsingObstacles(node: endNode)

        defer {
            graph.remove([startNode, endNode])
        }

        // Find path using A*
        let pathNodes = graph.findPath(from: startNode, to: endNode) as? [GKGraphNode2D]

        guard let nodes = pathNodes, nodes.count >= 2 else {
            // Fallback: try to find path through waypoints
            return fallbackPathfinding(from: start, to: destination, through: waypoints)
        }

        // Convert 2D path to 3D with floor height
        var path3D = nodes.map { node in
            SIMD3<Float>(node.position.x, floorHeight, node.position.y)
        }

        // Smooth the path
        path3D = smoothPath(path3D)

        return path3D
    }

    // MARK: - Fallback Pathfinding

    private func fallbackPathfinding(
        from start: SIMD3<Float>,
        to destination: NavigationAnchor,
        through waypoints: [NavigationAnchor]
    ) -> [SIMD3<Float>] {
        // Try hybrid approach: use waypoints but check for obstacle intersections
        let basicPath = PathFinder.findPath(from: start, to: destination, through: waypoints)

        guard basicPath.count >= 2 else {
            return [start, destination.position]
        }

        // Validate each segment against obstacles
        var validPath: [SIMD3<Float>] = [basicPath[0]]

        for i in 1..<basicPath.count {
            let from2D = vector_float2(validPath.last!.x, validPath.last!.z)
            let to2D = vector_float2(basicPath[i].x, basicPath[i].z)

            if isPathClear(from: from2D, to: to2D) {
                validPath.append(basicPath[i])
            } else {
                // Try to find intermediate point around obstacle
                if let detour = findDetour(from: from2D, to: to2D) {
                    validPath.append(SIMD3<Float>(detour.x, floorHeight, detour.y))
                }
                validPath.append(basicPath[i])
            }
        }

        return validPath
    }

    private func isPathClear(from: vector_float2, to: vector_float2) -> Bool {
        for obstacle in obstacles {
            if lineIntersectsObstacle(from: from, to: to, obstacle: obstacle) {
                return false
            }
        }
        return true
    }

    private func lineIntersectsObstacle(from: vector_float2, to: vector_float2, obstacle: GKPolygonObstacle) -> Bool {
        let vertexCount = obstacle.vertexCount
        guard vertexCount >= 3 else { return false }

        for i in 0..<vertexCount {
            let v1 = obstacle.vertex(at: i)
            let v2 = obstacle.vertex(at: (i + 1) % vertexCount)

            if segmentsIntersect(from, to, v1, v2) {
                return true
            }
        }

        return false
    }

    private func segmentsIntersect(
        _ a1: vector_float2, _ a2: vector_float2,
        _ b1: vector_float2, _ b2: vector_float2
    ) -> Bool {
        let d1 = direction(b1, b2, a1)
        let d2 = direction(b1, b2, a2)
        let d3 = direction(a1, a2, b1)
        let d4 = direction(a1, a2, b2)

        if ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
           ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0)) {
            return true
        }

        return false
    }

    private func direction(_ a: vector_float2, _ b: vector_float2, _ c: vector_float2) -> Float {
        (c.x - a.x) * (b.y - a.y) - (b.x - a.x) * (c.y - a.y)
    }

    private func findDetour(from: vector_float2, to: vector_float2) -> vector_float2? {
        // Simple detour: try perpendicular offsets
        let mid = (from + to) / 2
        let dir = simd_normalize(to - from)
        let perp = vector_float2(-dir.y, dir.x)

        let offsets: [Float] = [0.5, -0.5, 1.0, -1.0]

        for offset in offsets {
            let detour = mid + perp * offset
            if isPathClear(from: from, to: detour) && isPathClear(from: detour, to: to) {
                return detour
            }
        }

        return nil
    }

    // MARK: - Path Smoothing

    private func smoothPath(_ path: [SIMD3<Float>]) -> [SIMD3<Float>] {
        guard path.count >= 3 else { return path }

        var smoothed: [SIMD3<Float>] = [path[0]]

        for i in 1..<(path.count - 1) {
            let p0 = path[max(0, i - 1)]
            let p1 = path[i]
            let p2 = path[min(path.count - 1, i + 1)]

            // Catmull-Rom interpolation for smoother curves
            let t: Float = 0.5
            let smoothPoint = catmullRom(p0: p0, p1: p1, p2: p2, t: t)
            smoothed.append(smoothPoint)
        }

        smoothed.append(path.last!)
        return smoothed
    }

    private func catmullRom(p0: SIMD3<Float>, p1: SIMD3<Float>, p2: SIMD3<Float>, t: Float) -> SIMD3<Float> {
        let t2 = t * t
        let blend = SIMD3<Float>(
            -pathSmoothing * t + 2 * pathSmoothing * t2 - pathSmoothing * t2 * t,
            1 + (pathSmoothing - 3) * t2 + (2 - pathSmoothing) * t2 * t,
            pathSmoothing * t + (3 - 2 * pathSmoothing) * t2 + (pathSmoothing - 2) * t2 * t
        )

        return p0 * blend.x + p1 * blend.y + p2 * blend.z
    }

    // MARK: - Debugging

    var obstacleCount: Int { obstacles.count }
    var hasGraph: Bool { obstacleGraph != nil }
}
