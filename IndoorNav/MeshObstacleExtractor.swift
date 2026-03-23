import ARKit
import GameplayKit
import simd

final class MeshObstacleExtractor {

    struct FloorObstacle {
        let polygon: [SIMD2<Float>]
        let heightRange: ClosedRange<Float>
    }

    private let gridResolution: Float = 0.1  // 10cm grid cells
    private let obstacleHeightMin: Float = 0.15  // Ignore below 15cm (floor noise)
    private let obstacleHeightMax: Float = 2.0   // Ignore above 2m (ceilings)
    private let floorTolerance: Float = 0.1      // Floor detection tolerance

    private var occupancyGrid: [GridCell: Bool] = [:]
    private var floorHeight: Float = 0

    struct GridCell: Hashable {
        let x: Int
        let z: Int
    }

    // MARK: - Public Interface

    func processAnchors(_ anchors: [ARMeshAnchor], relativeTo floorY: Float) -> [GKPolygonObstacle] {
        floorHeight = floorY
        occupancyGrid.removeAll()

        for anchor in anchors {
            processMeshAnchor(anchor)
        }

        return extractObstacles()
    }

    func estimateFloorHeight(from anchors: [ARMeshAnchor]) -> Float {
        var yValues: [Float] = []

        for anchor in anchors {
            let geometry = anchor.geometry
            let vertices = geometry.vertices
            let vertexBuffer = vertices.buffer.contents()

            for i in 0..<vertices.count {
                let vertexPointer = vertexBuffer.advanced(by: vertices.offset + vertices.stride * i)
                let vertex = vertexPointer.assumingMemoryBound(to: SIMD3<Float>.self).pointee
                let worldVertex = anchor.transform * SIMD4<Float>(vertex, 1)
                yValues.append(worldVertex.y)
            }
        }

        guard !yValues.isEmpty else { return 0 }

        // Use percentile-based floor detection (lowest 10%)
        yValues.sort()
        let floorSampleCount = max(1, yValues.count / 10)
        let floorSamples = yValues.prefix(floorSampleCount)
        return floorSamples.reduce(0, +) / Float(floorSamples.count)
    }

    // MARK: - Mesh Processing

    private func processMeshAnchor(_ anchor: ARMeshAnchor) {
        let geometry = anchor.geometry
        let vertices = geometry.vertices
        let faces = geometry.faces
        let vertexBuffer = vertices.buffer.contents()
        let faceBuffer = faces.buffer.contents()
        let bytesPerIndex = faces.bytesPerIndex
        let indicesPerFace = faces.indexCountPerPrimitive

        // Process each triangle face
        for faceIndex in 0..<faces.count {
            var faceVertices: [SIMD3<Float>] = []

            for i in 0..<indicesPerFace {
                let indexOffset = (faceIndex * indicesPerFace + i) * bytesPerIndex
                let indexPointer = faceBuffer.advanced(by: indexOffset)

                let vertexIndex: Int
                if bytesPerIndex == 4 {
                    vertexIndex = Int(indexPointer.assumingMemoryBound(to: UInt32.self).pointee)
                } else {
                    vertexIndex = Int(indexPointer.assumingMemoryBound(to: UInt16.self).pointee)
                }

                let vertexPointer = vertexBuffer.advanced(by: vertices.offset + vertices.stride * vertexIndex)
                let localVertex = vertexPointer.assumingMemoryBound(to: SIMD3<Float>.self).pointee
                let worldVertex = anchor.transform * SIMD4<Float>(localVertex, 1)
                faceVertices.append(SIMD3<Float>(worldVertex.x, worldVertex.y, worldVertex.z))
            }

            processFace(faceVertices)
        }
    }

    private func processFace(_ vertices: [SIMD3<Float>]) {
        // Check if this face is an obstacle (vertical surface or elevated horizontal)
        let minY = vertices.map(\.y).min() ?? 0
        let maxY = vertices.map(\.y).max() ?? 0
        let heightAboveFloor = minY - floorHeight

        // Skip floor-level geometry and ceiling
        guard heightAboveFloor > obstacleHeightMin && heightAboveFloor < obstacleHeightMax else {
            return
        }

        // Project face onto XZ plane and mark grid cells as occupied
        for vertex in vertices {
            let cellX = Int(floor(vertex.x / gridResolution))
            let cellZ = Int(floor(vertex.z / gridResolution))
            occupancyGrid[GridCell(x: cellX, z: cellZ)] = true
        }

        // Also fill in the triangle interior
        fillTriangle(vertices.map { SIMD2<Float>($0.x, $0.z) })
    }

    private func fillTriangle(_ points: [SIMD2<Float>]) {
        guard points.count == 3 else { return }

        let minX = points.map(\.x).min()!
        let maxX = points.map(\.x).max()!
        let minZ = points.map(\.y).min()!
        let maxZ = points.map(\.y).max()!

        let startCellX = Int(floor(minX / gridResolution))
        let endCellX = Int(ceil(maxX / gridResolution))
        let startCellZ = Int(floor(minZ / gridResolution))
        let endCellZ = Int(ceil(maxZ / gridResolution))

        for cellX in startCellX...endCellX {
            for cellZ in startCellZ...endCellZ {
                let cellCenter = SIMD2<Float>(
                    Float(cellX) * gridResolution + gridResolution / 2,
                    Float(cellZ) * gridResolution + gridResolution / 2
                )
                if pointInTriangle(cellCenter, points[0], points[1], points[2]) {
                    occupancyGrid[GridCell(x: cellX, z: cellZ)] = true
                }
            }
        }
    }

    private func pointInTriangle(_ p: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>) -> Bool {
        let v0 = c - a
        let v1 = b - a
        let v2 = p - a

        let dot00 = simd_dot(v0, v0)
        let dot01 = simd_dot(v0, v1)
        let dot02 = simd_dot(v0, v2)
        let dot11 = simd_dot(v1, v1)
        let dot12 = simd_dot(v1, v2)

        let invDenom = 1 / (dot00 * dot11 - dot01 * dot01)
        let u = (dot11 * dot02 - dot01 * dot12) * invDenom
        let v = (dot00 * dot12 - dot01 * dot02) * invDenom

        return (u >= 0) && (v >= 0) && (u + v <= 1)
    }

    // MARK: - Obstacle Extraction

    private func extractObstacles() -> [GKPolygonObstacle] {
        guard !occupancyGrid.isEmpty else { return [] }

        // Find connected components of occupied cells
        var visited = Set<GridCell>()
        var obstacles: [GKPolygonObstacle] = []

        for cell in occupancyGrid.keys {
            guard !visited.contains(cell) else { continue }

            let component = floodFill(from: cell, visited: &visited)
            if component.count >= 4 {  // Minimum cells for a meaningful obstacle
                if let obstacle = createObstacle(from: component) {
                    obstacles.append(obstacle)
                }
            }
        }

        return obstacles
    }

    private func floodFill(from start: GridCell, visited: inout Set<GridCell>) -> Set<GridCell> {
        var component = Set<GridCell>()
        var queue = [start]

        while !queue.isEmpty {
            let cell = queue.removeFirst()
            guard !visited.contains(cell), occupancyGrid[cell] == true else { continue }

            visited.insert(cell)
            component.insert(cell)

            // 4-connectivity neighbors
            let neighbors = [
                GridCell(x: cell.x - 1, z: cell.z),
                GridCell(x: cell.x + 1, z: cell.z),
                GridCell(x: cell.x, z: cell.z - 1),
                GridCell(x: cell.x, z: cell.z + 1)
            ]

            for neighbor in neighbors {
                if occupancyGrid[neighbor] == true && !visited.contains(neighbor) {
                    queue.append(neighbor)
                }
            }
        }

        return component
    }

    private func createObstacle(from cells: Set<GridCell>) -> GKPolygonObstacle? {
        // Compute convex hull of cell centers
        let points = cells.map { cell in
            SIMD2<Float>(
                Float(cell.x) * gridResolution + gridResolution / 2,
                Float(cell.z) * gridResolution + gridResolution / 2
            )
        }

        let hull = convexHull(points)
        guard hull.count >= 3 else { return nil }

        // Expand hull slightly for safety margin
        let expandedHull = expandPolygon(hull, by: 0.15)

        // Convert to GKPolygonObstacle using UnsafeMutablePointer
        var gkPoints = expandedHull.map { vector_float2($0.x, $0.y) }
        return gkPoints.withUnsafeMutableBufferPointer { buffer in
            GKPolygonObstacle(points: buffer.baseAddress!, count: buffer.count)
        }
    }

    private func convexHull(_ points: [SIMD2<Float>]) -> [SIMD2<Float>] {
        guard points.count >= 3 else { return points }

        let sorted = points.sorted { $0.x < $1.x || ($0.x == $1.x && $0.y < $1.y) }

        var lower: [SIMD2<Float>] = []
        for p in sorted {
            while lower.count >= 2 && cross(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 {
                lower.removeLast()
            }
            lower.append(p)
        }

        var upper: [SIMD2<Float>] = []
        for p in sorted.reversed() {
            while upper.count >= 2 && cross(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 {
                upper.removeLast()
            }
            upper.append(p)
        }

        lower.removeLast()
        upper.removeLast()
        return lower + upper
    }

    private func cross(_ o: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
        (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
    }

    private func expandPolygon(_ polygon: [SIMD2<Float>], by amount: Float) -> [SIMD2<Float>] {
        guard polygon.count >= 3 else { return polygon }

        // Compute centroid
        let centroid = polygon.reduce(SIMD2<Float>.zero, +) / Float(polygon.count)

        // Expand each vertex away from centroid
        return polygon.map { vertex in
            let direction = simd_normalize(vertex - centroid)
            return vertex + direction * amount
        }
    }
}
