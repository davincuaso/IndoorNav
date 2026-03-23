import Foundation
import ARKit
import SceneKit

final class MeshDataStore {

    static let shared = MeshDataStore()

    private let fileExtension = "scanmesh"

    private var meshDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("IndoorNavMeshes")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private init() {}

    // MARK: - Save Mesh Data

    func saveMeshData(from anchors: [ARMeshAnchor], forZone zoneId: UUID) throws {
        let meshData = MeshExportData(anchors: anchors)
        let data = try JSONEncoder().encode(meshData)
        let url = meshDirectory.appendingPathComponent("\(zoneId.uuidString).\(fileExtension)")
        try data.write(to: url, options: .atomic)
    }

    func loadMeshData(forZone zoneId: UUID) throws -> MeshExportData {
        let url = meshDirectory.appendingPathComponent("\(zoneId.uuidString).\(fileExtension)")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(MeshExportData.self, from: data)
    }

    func meshExists(forZone zoneId: UUID) -> Bool {
        let url = meshDirectory.appendingPathComponent("\(zoneId.uuidString).\(fileExtension)")
        return FileManager.default.fileExists(atPath: url.path)
    }

    func deleteMesh(forZone zoneId: UUID) {
        let url = meshDirectory.appendingPathComponent("\(zoneId.uuidString).\(fileExtension)")
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Generate SCNNode from Mesh Data

    func createSceneNode(from meshData: MeshExportData, colorScheme: MeshColorScheme = .height) -> SCNNode {
        let containerNode = SCNNode()

        for meshChunk in meshData.chunks {
            let geometry = createGeometry(from: meshChunk, colorScheme: colorScheme)
            let node = SCNNode(geometry: geometry)
            node.simdTransform = meshChunk.transform
            containerNode.addChildNode(node)
        }

        return containerNode
    }

    private func createGeometry(from chunk: MeshChunk, colorScheme: MeshColorScheme) -> SCNGeometry {
        // Create vertex source
        let vertexData = Data(bytes: chunk.vertices, count: chunk.vertices.count * MemoryLayout<SIMD3<Float>>.stride)
        let vertexSource = SCNGeometrySource(
            data: vertexData,
            semantic: .vertex,
            vectorCount: chunk.vertices.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SIMD3<Float>>.stride
        )

        // Create normal source
        let normalData = Data(bytes: chunk.normals, count: chunk.normals.count * MemoryLayout<SIMD3<Float>>.stride)
        let normalSource = SCNGeometrySource(
            data: normalData,
            semantic: .normal,
            vectorCount: chunk.normals.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SIMD3<Float>>.stride
        )

        // Create color source based on height
        var colors: [SIMD4<Float>] = []
        let minY = chunk.vertices.map(\.y).min() ?? 0
        let maxY = chunk.vertices.map(\.y).max() ?? 1
        let range = max(maxY - minY, 0.1)

        for vertex in chunk.vertices {
            let normalizedHeight = (vertex.y - minY) / range
            let color = colorScheme.color(for: normalizedHeight)
            colors.append(color)
        }

        let colorData = Data(bytes: colors, count: colors.count * MemoryLayout<SIMD4<Float>>.stride)
        let colorSource = SCNGeometrySource(
            data: colorData,
            semantic: .color,
            vectorCount: colors.count,
            usesFloatComponents: true,
            componentsPerVector: 4,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SIMD4<Float>>.stride
        )

        // Create element
        let indexData = Data(bytes: chunk.indices, count: chunk.indices.count * MemoryLayout<UInt32>.size)
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .triangles,
            primitiveCount: chunk.indices.count / 3,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )

        let geometry = SCNGeometry(sources: [vertexSource, normalSource, colorSource], elements: [element])

        let material = SCNMaterial()
        material.diffuse.contents = UIColor.white
        material.lightingModel = .physicallyBased
        material.isDoubleSided = true
        geometry.materials = [material]

        return geometry
    }
}

// MARK: - Data Models

struct MeshExportData: Codable {
    let chunks: [MeshChunk]
    let boundingBox: BoundingBox
    let createdAt: Date

    init(anchors: [ARMeshAnchor]) {
        var allChunks: [MeshChunk] = []
        var minPoint = SIMD3<Float>(Float.infinity, Float.infinity, Float.infinity)
        var maxPoint = SIMD3<Float>(-Float.infinity, -Float.infinity, -Float.infinity)

        for anchor in anchors {
            let chunk = MeshChunk(from: anchor)
            allChunks.append(chunk)

            // Update bounding box
            for vertex in chunk.vertices {
                let worldVertex = anchor.transform * SIMD4<Float>(vertex, 1)
                let v = SIMD3<Float>(worldVertex.x, worldVertex.y, worldVertex.z)
                minPoint = min(minPoint, v)
                maxPoint = max(maxPoint, v)
            }
        }

        self.chunks = allChunks
        self.boundingBox = BoundingBox(min: minPoint, max: maxPoint)
        self.createdAt = Date()
    }
}

struct MeshChunk: Codable {
    let vertices: [SIMD3<Float>]
    let normals: [SIMD3<Float>]
    let indices: [UInt32]
    let transform: simd_float4x4

    init(from anchor: ARMeshAnchor) {
        let geometry = anchor.geometry

        // Extract vertices
        var verts: [SIMD3<Float>] = []
        let vertexBuffer = geometry.vertices.buffer.contents()
        for i in 0..<geometry.vertices.count {
            let ptr = vertexBuffer.advanced(by: geometry.vertices.offset + geometry.vertices.stride * i)
            let vertex = ptr.assumingMemoryBound(to: SIMD3<Float>.self).pointee
            verts.append(vertex)
        }

        // Extract normals
        var norms: [SIMD3<Float>] = []
        let normalBuffer = geometry.normals.buffer.contents()
        for i in 0..<geometry.normals.count {
            let ptr = normalBuffer.advanced(by: geometry.normals.offset + geometry.normals.stride * i)
            let normal = ptr.assumingMemoryBound(to: SIMD3<Float>.self).pointee
            norms.append(normal)
        }

        // Extract indices
        var inds: [UInt32] = []
        let faceBuffer = geometry.faces.buffer.contents()
        for i in 0..<geometry.faces.count {
            for j in 0..<geometry.faces.indexCountPerPrimitive {
                let ptr = faceBuffer.advanced(by: geometry.faces.offset + (i * geometry.faces.indexCountPerPrimitive + j) * MemoryLayout<UInt32>.size)
                let index = ptr.assumingMemoryBound(to: UInt32.self).pointee
                inds.append(index)
            }
        }

        self.vertices = verts
        self.normals = norms
        self.indices = inds
        self.transform = anchor.transform
    }
}

struct BoundingBox: Codable {
    let min: SIMD3<Float>
    let max: SIMD3<Float>

    var center: SIMD3<Float> {
        (min + max) / 2
    }

    var size: SIMD3<Float> {
        max - min
    }

    var maxDimension: Float {
        Swift.max(size.x, Swift.max(size.y, size.z))
    }
}

// MARK: - Color Schemes

enum MeshColorScheme {
    case height
    case solid(UIColor)
    case wireframe

    func color(for normalizedHeight: Float) -> SIMD4<Float> {
        switch self {
        case .height:
            // Cool gradient: blue (low) -> cyan -> green -> yellow -> red (high)
            let h = normalizedHeight
            if h < 0.25 {
                let t = h / 0.25
                return SIMD4<Float>(0, t * 0.5, 1, 0.8)
            } else if h < 0.5 {
                let t = (h - 0.25) / 0.25
                return SIMD4<Float>(0, 0.5 + t * 0.5, 1 - t * 0.5, 0.8)
            } else if h < 0.75 {
                let t = (h - 0.5) / 0.25
                return SIMD4<Float>(t, 1, 0.5 - t * 0.5, 0.8)
            } else {
                let t = (h - 0.75) / 0.25
                return SIMD4<Float>(1, 1 - t * 0.5, 0, 0.8)
            }
        case .solid(let color):
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            return SIMD4<Float>(Float(r), Float(g), Float(b), Float(a))
        case .wireframe:
            return SIMD4<Float>(0.3, 0.8, 1.0, 1.0)
        }
    }
}
