import ARKit

enum AnchorKind: String {
    case destination
    case waypoint
}

/// Custom ARAnchor that carries a destination name and a kind (destination vs waypoint).
/// Conforms to NSSecureCoding so it persists inside an ARWorldMap archive.
class NavigationAnchor: ARAnchor, @unchecked Sendable {

    static let nameKey = "destinationName"
    static let kindKey = "anchorKind"

    let destinationName: String
    let kind: AnchorKind

    var isWaypoint: Bool { kind == .waypoint }
    var isDestination: Bool { kind == .destination }

    init(destinationName: String, kind: AnchorKind, transform: simd_float4x4) {
        self.destinationName = destinationName
        self.kind = kind
        super.init(name: destinationName, transform: transform)
    }

    override init(name: String, transform: simd_float4x4) {
        self.destinationName = name
        self.kind = .destination
        super.init(name: name, transform: transform)
    }

    // MARK: - ARAnchor copy contract

    required init(anchor: ARAnchor) {
        if let nav = anchor as? NavigationAnchor {
            self.destinationName = nav.destinationName
            self.kind = nav.kind
        } else {
            self.destinationName = anchor.name ?? "Unknown"
            self.kind = .destination
        }
        super.init(anchor: anchor)
    }

    // MARK: - NSSecureCoding

    override class var supportsSecureCoding: Bool { true }

    required init?(coder: NSCoder) {
        self.destinationName = coder.decodeObject(
            of: NSString.self, forKey: NavigationAnchor.nameKey
        ) as? String ?? "Unknown"

        let rawKind = coder.decodeObject(
            of: NSString.self, forKey: NavigationAnchor.kindKey
        ) as? String ?? "destination"
        self.kind = AnchorKind(rawValue: rawKind) ?? .destination

        super.init(coder: coder)
    }

    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(destinationName as NSString, forKey: NavigationAnchor.nameKey)
        coder.encode(kind.rawValue as NSString, forKey: NavigationAnchor.kindKey)
    }

    // MARK: - Helpers

    var position: SIMD3<Float> {
        let col = transform.columns.3
        return SIMD3<Float>(col.x, col.y, col.z)
    }
}
