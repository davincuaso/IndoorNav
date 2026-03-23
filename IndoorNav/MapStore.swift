import Foundation
import ARKit

/// Manages multiple named ARWorldMap files in the app's Documents directory.
enum MapStore {

    static let fileExtension = "arexperience"

    private static var mapsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("IndoorNavMaps")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func url(for name: String) -> URL {
        mapsDirectory.appendingPathComponent(name).appendingPathExtension(fileExtension)
    }

    // MARK: - CRUD

    static func save(_ worldMap: ARWorldMap, name: String) throws {
        let data = try NSKeyedArchiver.archivedData(
            withRootObject: worldMap, requiringSecureCoding: true
        )
        try data.write(to: url(for: name), options: [.atomic])
    }

    static func load(name: String) throws -> ARWorldMap {
        let fileURL = url(for: name)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw MapStoreError.fileNotFound(name)
        }

        let data = try Data(contentsOf: fileURL)

        guard !data.isEmpty else {
            throw MapStoreError.fileCorrupted(name)
        }

        do {
            guard let map = try NSKeyedUnarchiver.unarchivedObject(
                ofClass: ARWorldMap.self, from: data
            ) else {
                throw MapStoreError.decodeFailed
            }
            return map
        } catch let error as NSError where error.domain == NSCocoaErrorDomain {
            throw MapStoreError.fileCorrupted(name)
        }
    }

    static func list() -> [String] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: mapsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        return files
            .filter { $0.pathExtension == fileExtension }
            .sorted {
                let d1 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let d2 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return d1 > d2
            }
            .map { $0.deletingPathExtension().lastPathComponent }
    }

    static func delete(name: String) throws {
        try FileManager.default.removeItem(at: url(for: name))
    }

    static func exists(name: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: name).path)
    }

    // MARK: - Helpers

    static func anchorSummary(for worldMap: ARWorldMap) -> (destinations: Int, waypoints: Int) {
        let navAnchors = worldMap.anchors.compactMap { $0 as? NavigationAnchor }
        let dests = navAnchors.filter(\.isDestination).count
        let wps = navAnchors.filter(\.isWaypoint).count
        return (dests, wps)
    }

    enum MapStoreError: LocalizedError {
        case decodeFailed
        case fileNotFound(String)
        case fileCorrupted(String)

        var errorDescription: String? {
            switch self {
            case .decodeFailed:
                return "Could not decode the world map file."
            case .fileNotFound(let name):
                return "Map \"\(name)\" was not found."
            case .fileCorrupted(let name):
                return "Map \"\(name)\" appears to be corrupted."
            }
        }
    }
}
