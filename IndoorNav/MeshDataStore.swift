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
        // Convert Vector3 arrays to SIMD3<Float> arrays
        let simdVertices = chunk.vertices.map { $0.simd }
        let simdNormals = chunk.normals.map { $0.simd }

        // Create vertex source
        var vertexArray = simdVertices
        let vertexData = Data(bytes: &vertexArray, count: vertexArray.count * MemoryLayout<SIMD3<Float>>.stride)
        let vertexSource = SCNGeometrySource(
            data: vertexData,
            semantic: .vertex,
            vectorCount: vertexArray.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SIMD3<Float>>.stride
        )

        // Create normal source
        var normalArray = simdNormals
        let normalData = Data(bytes: &normalArray, count: normalArray.count * MemoryLayout<SIMD3<Float>>.stride)
        let normalSource = SCNGeometrySource(
            data: normalData,
            semantic: .normal,
            vectorCount: normalArray.count,
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
        let range = Swift.max(maxY - minY, 0.1)

        for vertex in chunk.vertices {
            let normalizedHeight = (vertex.y - minY) / range
            let color = colorScheme.color(for: normalizedHeight)
            colors.append(color)
        }

        let colorData = Data(bytes: &colors, count: colors.count * MemoryLayout<SIMD4<Float>>.stride)
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
        var indexArray = chunk.indices
        let indexData = Data(bytes: &indexArray, count: indexArray.count * MemoryLayout<UInt32>.size)
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
                let simdVertex = vertex.simd
                let worldVertex = anchor.transform * SIMD4<Float>(simdVertex.x, simdVertex.y, simdVertex.z, 1)
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
    let vertices: [Vector3]
    let normals: [Vector3]
    let indices: [UInt32]
    let transformData: [Float]  // 16 floats for 4x4 matrix

    var transform: simd_float4x4 {
        simd_float4x4(
            SIMD4<Float>(transformData[0], transformData[1], transformData[2], transformData[3]),
            SIMD4<Float>(transformData[4], transformData[5], transformData[6], transformData[7]),
            SIMD4<Float>(transformData[8], transformData[9], transformData[10], transformData[11]),
            SIMD4<Float>(transformData[12], transformData[13], transformData[14], transformData[15])
        )
    }

    init(from anchor: ARMeshAnchor) {
        let geometry = anchor.geometry

        // Extract vertices
        var verts: [Vector3] = []
        let vertexBuffer = geometry.vertices.buffer.contents()
        let vertexStride = geometry.vertices.stride
        for i in 0..<geometry.vertices.count {
            let ptr = vertexBuffer.advanced(by: vertexStride * i)
            let vertex = ptr.assumingMemoryBound(to: SIMD3<Float>.self).pointee
            verts.append(Vector3(vertex))
        }

        // Extract normals
        var norms: [Vector3] = []
        let normalBuffer = geometry.normals.buffer.contents()
        let normalStride = geometry.normals.stride
        for i in 0..<geometry.normals.count {
            let ptr = normalBuffer.advanced(by: normalStride * i)
            let normal = ptr.assumingMemoryBound(to: SIMD3<Float>.self).pointee
            norms.append(Vector3(normal))
        }

        // Extract indices
        var inds: [UInt32] = []
        let faceBuffer = geometry.faces.buffer.contents()
        let bytesPerIndex = geometry.faces.bytesPerIndex
        let indicesPerFace = geometry.faces.indexCountPerPrimitive

        for i in 0..<geometry.faces.count {
            for j in 0..<indicesPerFace {
                let indexOffset = (i * indicesPerFace + j) * bytesPerIndex
                let ptr = faceBuffer.advanced(by: indexOffset)
                let index: UInt32
                if bytesPerIndex == 4 {
                    index = ptr.assumingMemoryBound(to: UInt32.self).pointee
                } else {
                    index = UInt32(ptr.assumingMemoryBound(to: UInt16.self).pointee)
                }
                inds.append(index)
            }
        }

        self.vertices = verts
        self.normals = norms
        self.indices = inds

        // Flatten transform matrix
        let t = anchor.transform
        self.transformData = [
            t.columns.0.x, t.columns.0.y, t.columns.0.z, t.columns.0.w,
            t.columns.1.x, t.columns.1.y, t.columns.1.z, t.columns.1.w,
            t.columns.2.x, t.columns.2.y, t.columns.2.z, t.columns.2.w,
            t.columns.3.x, t.columns.3.y, t.columns.3.z, t.columns.3.w
        ]
    }
}

// Codable wrapper for SIMD3<Float>
struct Vector3: Codable {
    let x: Float
    let y: Float
    let z: Float

    init(_ simd: SIMD3<Float>) {
        self.x = simd.x
        self.y = simd.y
        self.z = simd.z
    }

    var simd: SIMD3<Float> {
        SIMD3<Float>(x, y, z)
    }
}

struct BoundingBox: Codable {
    let minX: Float
    let minY: Float
    let minZ: Float
    let maxX: Float
    let maxY: Float
    let maxZ: Float

    init(min: SIMD3<Float>, max: SIMD3<Float>) {
        self.minX = min.x
        self.minY = min.y
        self.minZ = min.z
        self.maxX = max.x
        self.maxY = max.y
        self.maxZ = max.z
    }

    var min: SIMD3<Float> {
        SIMD3<Float>(minX, minY, minZ)
    }

    var max: SIMD3<Float> {
        SIMD3<Float>(maxX, maxY, maxZ)
    }

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
