import Foundation

struct MapZone: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var description: String
    var mapFileName: String
    var createdAt: Date
    var updatedAt: Date
    var destinationCount: Int
    var waypointCount: Int
    var thumbnailData: Data?

    init(
        id: UUID = UUID(),
        name: String,
        description: String = "",
        mapFileName: String? = nil,
        destinationCount: Int = 0,
        waypointCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.mapFileName = mapFileName ?? "zone_\(id.uuidString)"
        self.createdAt = Date()
        self.updatedAt = Date()
        self.destinationCount = destinationCount
        self.waypointCount = waypointCount
        self.thumbnailData = nil
    }

    var displayName: String {
        name.isEmpty ? "Unnamed Zone" : name
    }

    var summary: String {
        var parts: [String] = []
        if destinationCount > 0 {
            parts.append("\(destinationCount) destination\(destinationCount == 1 ? "" : "s")")
        }
        if waypointCount > 0 {
            parts.append("\(waypointCount) waypoint\(waypointCount == 1 ? "" : "s")")
        }
        return parts.isEmpty ? "Empty" : parts.joined(separator: ", ")
    }

    var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: updatedAt, relativeTo: Date())
    }
}

final class ZoneStore: ObservableObject {

    static let shared = ZoneStore()

    @Published private(set) var zones: [MapZone] = []

    private let zonesFileName = "zones_manifest.json"

    private var zonesFileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("IndoorNavMaps")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(zonesFileName)
    }

    private init() {
        loadZones()
        migrateExistingMaps()
    }

    // MARK: - CRUD Operations

    func createZone(name: String, description: String = "") -> MapZone {
        let zone = MapZone(name: name, description: description)
        zones.append(zone)
        saveZones()
        return zone
    }

    func updateZone(_ zone: MapZone) {
        guard let index = zones.firstIndex(where: { $0.id == zone.id }) else { return }
        var updated = zone
        updated.updatedAt = Date()
        zones[index] = updated
        saveZones()
    }

    func deleteZone(_ zone: MapZone) {
        // Delete the map file
        try? MapStore.delete(name: zone.mapFileName)

        // Remove from manifest
        zones.removeAll { $0.id == zone.id }
        saveZones()
    }

    func zone(for id: UUID) -> MapZone? {
        zones.first { $0.id == id }
    }

    func zone(forMapName mapName: String) -> MapZone? {
        zones.first { $0.mapFileName == mapName }
    }

    // MARK: - Map File Association

    func associateMap(zone: MapZone, destinationCount: Int, waypointCount: Int) {
        guard let index = zones.firstIndex(where: { $0.id == zone.id }) else { return }
        var updated = zones[index]
        updated.destinationCount = destinationCount
        updated.waypointCount = waypointCount
        updated.updatedAt = Date()
        zones[index] = updated
        saveZones()
    }

    func mapExists(for zone: MapZone) -> Bool {
        MapStore.exists(name: zone.mapFileName)
    }

    // MARK: - Persistence

    private func loadZones() {
        guard FileManager.default.fileExists(atPath: zonesFileURL.path) else {
            zones = []
            return
        }

        do {
            let data = try Data(contentsOf: zonesFileURL)
            zones = try JSONDecoder().decode([MapZone].self, from: data)
        } catch {
            print("Failed to load zones: \(error)")
            zones = []
        }
    }

    private func saveZones() {
        do {
            let data = try JSONEncoder().encode(zones)
            try data.write(to: zonesFileURL, options: .atomic)
        } catch {
            print("Failed to save zones: \(error)")
        }
    }

    // MARK: - Migration

    private func migrateExistingMaps() {
        // Convert existing maps (saved before zone support) into zones
        let existingMapNames = MapStore.list()
        let knownMapNames = Set(zones.map(\.mapFileName))

        for mapName in existingMapNames {
            guard !knownMapNames.contains(mapName) else { continue }

            // Create a zone for this orphan map
            var zone = MapZone(name: mapName, mapFileName: mapName)

            // Try to load the map and get anchor counts
            if let worldMap = try? MapStore.load(name: mapName) {
                let summary = MapStore.anchorSummary(for: worldMap)
                zone.destinationCount = summary.destinations
                zone.waypointCount = summary.waypoints
            }

            zones.append(zone)
        }

        if existingMapNames.count > knownMapNames.count {
            saveZones()
        }
    }

    // MARK: - Sorting

    func sortedZones(by sortOrder: SortOrder = .recentFirst) -> [MapZone] {
        switch sortOrder {
        case .recentFirst:
            return zones.sorted { $0.updatedAt > $1.updatedAt }
        case .oldestFirst:
            return zones.sorted { $0.updatedAt < $1.updatedAt }
        case .alphabetical:
            return zones.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .mostDestinations:
            return zones.sorted { $0.destinationCount > $1.destinationCount }
        }
    }

    enum SortOrder {
        case recentFirst
        case oldestFirst
        case alphabetical
        case mostDestinations
    }
}
