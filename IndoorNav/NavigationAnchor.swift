import ARKit

/// Custom ARAnchor that carries a destination name (e.g. "Meeting Room").
/// Conforms to NSSecureCoding so it persists inside an ARWorldMap archive.
class NavigationAnchor: ARAnchor, @unchecked Sendable {

    static let nameKey = "destinationName"

    let destinationName: String

    override init(name: String, transform: simd_float4x4) {
        self.destinationName = name
        super.init(name: name, transform: transform)
    }

    // MARK: - ARAnchor copy contract

    required init(anchor: ARAnchor) {
        if let navAnchor = anchor as? NavigationAnchor {
            self.destinationName = navAnchor.destinationName
        } else {
            self.destinationName = anchor.name ?? "Unknown"
        }
        super.init(anchor: anchor)
    }

    // MARK: - NSSecureCoding

    override class var supportsSecureCoding: Bool { true }

    required init?(coder: NSCoder) {
        self.destinationName = coder.decodeObject(
            of: NSString.self,
            forKey: NavigationAnchor.nameKey
        ) as? String ?? "Unknown"
        super.init(coder: coder)
    }

    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(destinationName as NSString, forKey: NavigationAnchor.nameKey)
    }
}
