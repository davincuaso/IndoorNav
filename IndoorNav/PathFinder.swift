import simd
import ARKit

/// Builds a walkable graph from NavigationAnchors and finds the shortest path using Dijkstra.
enum PathFinder {

    /// Maximum distance (meters) between two anchors for them to be considered connected.
    static let connectionRadius: Float = 5.0

    /// Finds the shortest waypoint-routed path from a start position to a destination anchor.
    ///
    /// - Parameters:
    ///   - start: The current camera position.
    ///   - destination: The target destination anchor.
    ///   - anchors: All anchors (destinations + waypoints) forming the walkable graph.
    /// - Returns: Ordered array of 3D positions from start to destination.
    static func findPath(
        from start: SIMD3<Float>,
        to destination: NavigationAnchor,
        through anchors: [NavigationAnchor]
    ) -> [SIMD3<Float>] {
        guard !anchors.isEmpty else {
            return [start, destination.position]
        }

        // Node indices: 0..<anchors.count are the anchors, last index is the virtual start
        let n = anchors.count
        let startIdx = n
        let totalNodes = n + 1

        guard let destIdx = anchors.firstIndex(where: { $0.identifier == destination.identifier }) else {
            return [start, destination.position]
        }

        var positions = anchors.map(\.position)
        positions.append(start)

        // Build adjacency: anchor-to-anchor within connectionRadius,
        // virtual start connects to nearest anchors within a generous radius.
        let startRadius = max(connectionRadius, nearestDistance(from: start, in: positions, excluding: startIdx) * 1.5)

        var adj = [[Edge]](repeating: [], count: totalNodes)

        for i in 0..<n {
            for j in (i + 1)..<n {
                let d = simd_length(positions[i] - positions[j])
                if d <= connectionRadius {
                    adj[i].append(Edge(to: j, weight: d))
                    adj[j].append(Edge(to: i, weight: d))
                }
            }
            // Start node connections
            let d = simd_length(positions[i] - start)
            if d <= startRadius {
                adj[startIdx].append(Edge(to: i, weight: d))
                adj[i].append(Edge(to: startIdx, weight: d))
            }
        }

        // Dijkstra
        var dist = [Float](repeating: .infinity, count: totalNodes)
        var prev = [Int](repeating: -1, count: totalNodes)
        var visited = [Bool](repeating: false, count: totalNodes)
        dist[startIdx] = 0

        for _ in 0..<totalNodes {
            var u = -1
            var best: Float = .infinity
            for v in 0..<totalNodes where !visited[v] && dist[v] < best {
                best = dist[v]
                u = v
            }
            guard u != -1 else { break }
            if u == destIdx { break }
            visited[u] = true

            for edge in adj[u] {
                let newDist = dist[u] + edge.weight
                if newDist < dist[edge.to] {
                    dist[edge.to] = newDist
                    prev[edge.to] = u
                }
            }
        }

        guard dist[destIdx] < .infinity else {
            return [start, destination.position]
        }

        var path = [SIMD3<Float>]()
        var cur = destIdx
        while cur != -1 {
            path.append(positions[cur])
            cur = prev[cur]
        }
        path.reverse()
        return path
    }

    // MARK: - Private

    private struct Edge {
        let to: Int
        let weight: Float
    }

    private static func nearestDistance(from point: SIMD3<Float>, in positions: [SIMD3<Float>], excluding idx: Int) -> Float {
        var best: Float = .infinity
        for (i, pos) in positions.enumerated() where i != idx {
            let d = simd_length(pos - point)
            if d < best { best = d }
        }
        return best == .infinity ? connectionRadius : best
    }
}
