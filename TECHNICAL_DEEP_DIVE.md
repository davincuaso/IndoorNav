# IndoorNav — Technical Deep Dive

A comprehensive guide to understanding how every part of this AR indoor navigation system works, from the physics of how your phone tracks itself in space to the graph algorithm that routes you around walls.

---

## Table of Contents

1. [The Big Picture](#1-the-big-picture)
2. [How ARKit Tracks Your Phone in 3D Space](#2-how-arkit-tracks-your-phone-in-3d-space)
   - [Visual-Inertial Odometry (VIO)](#visual-inertial-odometry-vio)
   - [Feature Points](#feature-points)
   - [Plane Detection](#plane-detection)
   - [LiDAR Scene Reconstruction](#lidar-scene-reconstruction)
3. [The Coordinate System](#3-the-coordinate-system)
   - [World Origin](#world-origin)
   - [The 4x4 Transform Matrix](#the-4x4-transform-matrix)
   - [Reading a Position from a Transform](#reading-a-position-from-a-transform)
4. [Anchors — Pinning Virtual Objects to the Real World](#4-anchors--pinning-virtual-objects-to-the-real-world)
   - [What Is an ARAnchor?](#what-is-an-aranchor)
   - [Our Custom NavigationAnchor](#our-custom-navigationanchor)
   - [NSSecureCoding — Why Serialization Matters](#nssecurecoding--why-serialization-matters)
5. [The ARWorldMap — Capturing a Snapshot of Reality](#5-the-arworldmap--capturing-a-snapshot-of-reality)
   - [What's Inside an ARWorldMap](#whats-inside-an-arworldmap)
   - [Saving the Map to Disk](#saving-the-map-to-disk)
   - [Where Files Are Stored](#where-files-are-stored)
6. [Relocalization — Finding Your Place Again](#6-relocalization--finding-your-place-again)
   - [How It Works](#how-it-works)
   - [Why Lighting Matters](#why-lighting-matters)
   - [How We Detect It in Code](#how-we-detect-it-in-code)
7. [Waypoints — Building a Walkable Network](#7-waypoints--building-a-walkable-network)
   - [Why Straight Lines Don't Work](#why-straight-lines-dont-work)
   - [Auto-Drop Mechanism](#auto-drop-mechanism)
   - [The Waypoint Graph](#the-waypoint-graph)
8. [Pathfinding — Two-Tier Approach](#8-pathfinding--two-tier-approach)
   - [Tier 1: Obstacle-Aware Pathfinding (LiDAR)](#tier-1-obstacle-aware-pathfinding-lidar)
   - [Tier 2: Waypoint-Based Dijkstra (Fallback)](#tier-2-waypoint-based-dijkstra-fallback)
   - [Worked Example](#worked-example)
9. [AR Occlusion — Realistic Depth Rendering](#9-ar-occlusion--realistic-depth-rendering)
   - [How Occlusion Works](#how-occlusion-works)
   - [Configuring Depth Semantics](#configuring-depth-semantics)
   - [Material Configuration](#material-configuration)
10. [Rendering — Drawing 3D Objects in AR](#10-rendering--drawing-3d-objects-in-ar)
    - [SceneKit and ARSCNView](#scenekit-and-arscnview)
    - [How Anchor Nodes Are Created](#how-anchor-nodes-are-created)
    - [Path Rendering Styles](#path-rendering-styles)
    - [The Render Loop](#the-render-loop)
11. [3D Scan Viewer — Visualizing Mapped Spaces](#11-3d-scan-viewer--visualizing-mapped-spaces)
    - [Mesh Data Export](#mesh-data-export)
    - [SceneKit Reconstruction](#scenekit-reconstruction)
    - [Height-Based Coloring](#height-based-coloring)
12. [Zone Management — Multi-Space Organization](#12-zone-management--multi-space-organization)
    - [Zone Model](#zone-model)
    - [Zone Store](#zone-store)
    - [Legacy Migration](#legacy-migration)
13. [Haptic Feedback — Rich Touch Responses](#13-haptic-feedback--rich-touch-responses)
    - [CoreHaptics Integration](#corehaptics-integration)
    - [Feedback Patterns](#feedback-patterns)
14. [The SwiftUI ↔ UIKit Bridge](#14-the-swiftui--uikit-bridge)
    - [UIViewRepresentable](#uiviewrepresentable)
    - [ObservableObject and @Published](#observableobject-and-published)
15. [Architecture — MVVM Pattern](#15-architecture--mvvm-pattern)
    - [ARManager (Session Management)](#armanager-session-management)
    - [NavigationViewModel (State Container)](#navigationviewmodel-state-container)
    - [Separation of Concerns](#separation-of-concerns)
16. [Threading Model](#16-threading-model)
17. [Complete Data Flow: Mapping to Navigation](#17-complete-data-flow-mapping-to-navigation)
18. [File-by-File Code Walkthrough](#18-file-by-file-code-walkthrough)
19. [Key Apple Frameworks Used](#19-key-apple-frameworks-used)
20. [Glossary](#20-glossary)

---

## 1. The Big Picture

The app solves one problem: **getting from point A to point B inside a building where GPS doesn't work.**

GPS signals can't penetrate walls and ceilings reliably enough for indoor use. Instead, this app uses the phone's camera and motion sensors to understand where it is within a room. The core idea is:

1. **An admin walks through the space** while the phone builds a 3D understanding of the environment. The admin drops named markers ("Meeting Room", "Kitchen") and the phone lays down invisible path nodes (waypoints) along every corridor.

2. **That spatial understanding is saved to a file.** The file contains thousands of visual landmarks, the positions of all markers and waypoints, and enough information to recognize the space later.

3. **A user loads that file** and points their phone at the same space. The phone matches what it sees to the saved landmarks, figures out exactly where it is, and can then draw a path through the waypoints to any destination.

The rest of this document explains every piece of that pipeline in detail.

---

## 2. How ARKit Tracks Your Phone in 3D Space

### Visual-Inertial Odometry (VIO)

ARKit's core tracking technology is called **Visual-Inertial Odometry**. It fuses two data sources:

- **Camera (visual):** Each video frame is analyzed for distinctive visual features — corners, edges, textures. By watching how these features move between frames, ARKit calculates how the camera moved.

- **IMU (inertial):** The phone's accelerometer and gyroscope measure linear acceleration and rotational velocity at 1000 Hz. These measurements fill in the gaps between camera frames (which arrive at 30-60 Hz) and handle fast movements where motion blur makes the camera unreliable.

The fusion of both sensors is what makes tracking robust. The camera prevents long-term drift (accelerometers accumulate error over time), while the IMU provides high-frequency updates between frames.

**In code**, this all happens automatically when you run an `ARWorldTrackingConfiguration`:

```swift
let config = ARWorldTrackingConfiguration()
sceneView.session.run(config)
```

From that point on, every `ARFrame` delivered to your delegate contains a `camera.transform` — a 4x4 matrix encoding the phone's exact position and orientation in 3D space, updated 60 times per second.

### Feature Points

Feature points are the visual landmarks ARKit extracts from camera frames. They're distinctive pixels — typically corners or high-contrast edges — that can be reliably identified across multiple frames from different angles.

You can see them as the yellow dots in the camera view:

```swift
sceneView.debugOptions = [.showFeaturePoints]
```

Each feature point has a 3D position computed via triangulation — ARKit sees the same feature from two camera positions and uses the angle difference to calculate its depth.

A well-mapped room might have **thousands** of feature points. Plain white walls generate very few (nothing to track), while a bookshelf or textured wall generates many.

### Plane Detection

ARKit also detects flat surfaces:

```swift
config.planeDetection = [.horizontal, .vertical]
```

This finds floors, tables, walls, etc. by recognizing clusters of coplanar feature points. The app enables this to improve overall scene understanding, though it doesn't directly use the detected planes for navigation (a future improvement could snap path dots to the floor plane).

### LiDAR Scene Reconstruction

On devices with a LiDAR scanner (iPhone 12 Pro and later, iPad Pro 2020+):

```swift
if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
    config.sceneReconstruction = .mesh
}
```

The LiDAR fires infrared laser pulses and measures their return time to build a depth map. This creates a dense 3D mesh of the environment — far more detailed than feature-point triangulation alone. It dramatically improves tracking accuracy, especially in visually sparse environments.

The app enables this automatically when available but doesn't require it.

---

## 3. The Coordinate System

### World Origin

When an AR session starts, ARKit establishes a **world coordinate system**:

- **Origin (0, 0, 0):** The position of the phone when the session started.
- **Y-axis:** Points straight up (opposite to gravity).
- **X and Z axes:** Form the horizontal plane, with Z pointing roughly toward the phone's initial rear-facing camera direction.
- **Units:** Meters. Everything in ARKit is measured in meters.

Every position and orientation in the session is relative to this origin. When you move 3 meters forward and 1 meter to the right, your camera transform reflects that.

### The 4x4 Transform Matrix

Positions and orientations in ARKit are encoded as `simd_float4x4` — a 4-by-4 matrix of floating-point numbers. This is standard in 3D graphics and robotics. The matrix combines:

```
| R R R Tx |
| R R R Ty |
| R R R Tz |
| 0 0 0  1 |
```

- **R (3x3 upper-left):** Rotation matrix — which direction the object is facing.
- **T (right column):** Translation — where the object is in 3D space.
- **Bottom row:** Always `[0, 0, 0, 1]` for a standard rigid-body transform.

### Reading a Position from a Transform

To get the XYZ position from a transform, you read the fourth column:

```swift
let transform = anchor.transform
let x = transform.columns.3.x  // meters right of origin
let y = transform.columns.3.y  // meters above origin
let z = transform.columns.3.z  // meters forward/back from origin
let position = SIMD3<Float>(x, y, z)
```

This is what our `NavigationAnchor.position` property does:

```swift
var position: SIMD3<Float> {
    let col = transform.columns.3
    return SIMD3<Float>(col.x, col.y, col.z)
}
```

When you "drop" an anchor, you're recording the camera's transform at that instant — its exact position and orientation in the world coordinate system.

---

## 4. Anchors — Pinning Virtual Objects to the Real World

### What Is an ARAnchor?

An `ARAnchor` is a fundamental ARKit concept: it represents a **fixed position and orientation in the real world**. When you add an anchor to the AR session, ARKit continuously refines its position as it learns more about the environment. If the tracking system realizes its earlier position estimates were slightly off, all anchors get adjusted together.

An anchor has:
- A `transform` (simd_float4x4) — its position and orientation.
- An `identifier` (UUID) — a unique ID.
- An optional `name` (String).

### Our Custom NavigationAnchor

We subclass `ARAnchor` to carry extra data:

```swift
class NavigationAnchor: ARAnchor, @unchecked Sendable {
    let destinationName: String   // "Meeting Room A" or "WP-14"
    let kind: AnchorKind          // .destination or .waypoint
}
```

Two kinds:
- **Destination:** A named place the user might want to navigate to. Rendered as a large labeled sphere.
- **Waypoint:** An unnamed path node defining a walkable corridor. Rendered as a small yellow dot.

When you tap "Drop" in the UI, this happens:

```swift
func dropDestination(named name: String) {
    guard let frame = sceneView.session.currentFrame else { return }
    let anchor = NavigationAnchor(
        destinationName: name,
        kind: .destination,
        transform: frame.camera.transform  // phone's current position
    )
    sceneView.session.add(anchor: anchor)  // registers with ARKit
}
```

The anchor's transform is the camera's transform at that moment — so the destination marker appears exactly where you were standing when you tapped the button.

### NSSecureCoding — Why Serialization Matters

When we save the world map, ARKit serializes all anchors using Apple's `NSKeyedArchiver` system. For our custom `NavigationAnchor` to survive this process, it must implement `NSSecureCoding`:

```swift
override func encode(with coder: NSCoder) {
    super.encode(with: coder)  // encodes ARAnchor's built-in properties
    coder.encode(destinationName as NSString, forKey: "destinationName")
    coder.encode(kind.rawValue as NSString, forKey: "anchorKind")
}

required init?(coder: NSCoder) {
    self.destinationName = coder.decodeObject(of: NSString.self, forKey: "destinationName") as? String ?? "Unknown"
    let rawKind = coder.decodeObject(of: NSString.self, forKey: "anchorKind") as? String ?? "destination"
    self.kind = AnchorKind(rawValue: rawKind) ?? .destination
    super.init(coder: coder)
}
```

Without this, the `destinationName` and `kind` would be lost when saving and loading the map — the anchors would come back as plain `ARAnchor` objects with no custom data.

`NSSecureCoding` (vs. regular `NSCoding`) also validates class types during deserialization, preventing a class of security vulnerabilities where archived data could instantiate arbitrary objects.

---

## 5. The ARWorldMap — Capturing a Snapshot of Reality

### What's Inside an ARWorldMap

An `ARWorldMap` is ARKit's snapshot of everything it has learned about the physical environment. It contains:

1. **Feature point cloud:** Thousands of 3D points with visual descriptors (what they look like, so they can be recognized later).
2. **Anchors:** All `ARAnchor` objects in the session, including our custom `NavigationAnchor` instances.
3. **Plane anchors:** Detected surfaces.
4. **Raw feature data:** Internal data ARKit uses for relocalization.
5. **Map extent:** The spatial bounds of the mapped area.

Capturing it is asynchronous because ARKit needs to finalize its internal state:

```swift
sceneView.session.getCurrentWorldMap { worldMap, error in
    // worldMap contains the complete spatial snapshot
}
```

This call can only succeed when the world mapping status is `.mapped` or `.extending`. That status reflects how much of the environment ARKit has confidently mapped:

| Status | Meaning |
|---|---|
| `.notAvailable` | Session just started, no data yet |
| `.limited` | Some features detected, but not enough for a reliable map |
| `.extending` | Good map quality; getting better as you explore more |
| `.mapped` | Excellent quality; current view has been thoroughly mapped |

### Saving the Map to Disk

The save pipeline has three steps:

```swift
// 1. Get the world map from ARKit
sceneView.session.getCurrentWorldMap { worldMap, error in

    // 2. Serialize to binary data using NSKeyedArchiver
    let data = try NSKeyedArchiver.archivedData(
        withRootObject: worldMap,
        requiringSecureCoding: true  // enforces NSSecureCoding on all objects
    )

    // 3. Write to a file
    try data.write(to: fileURL, options: [.atomic])
}
```

The `.atomic` option writes to a temporary file first and then renames it, preventing corruption if the app crashes mid-write.

A typical world map file is **5-50 MB** depending on how large the mapped area is and how many feature points were captured.

### Where Files Are Stored

Maps are stored in the app's **sandboxed Documents directory**:

```
/var/mobile/Containers/Data/Application/<APP-UUID>/Documents/IndoorNavMaps/
    Office Floor 3.arexperience
    Building A Lobby.arexperience
    ...
```

Each file is named after the map name you type in the UI, with an `.arexperience` extension.

The `MapStore` class manages this directory:

```swift
enum MapStore {
    private static var mapsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("IndoorNavMaps")
    }

    static func save(_ worldMap: ARWorldMap, name: String) throws { ... }
    static func load(name: String) throws -> ARWorldMap { ... }
    static func list() -> [String] { ... }
    static func delete(name: String) throws { ... }
}
```

This directory is:
- **App-sandboxed:** Only this app can access it.
- **Backed up by iCloud** (unless you opt out) when the user backs up their device.
- **Persists across app launches** but is deleted when the app is uninstalled.

---

## 6. Relocalization — Finding Your Place Again

### How It Works

Relocalization is the process of matching a live camera feed against a saved world map to determine where the device is within the previously mapped space.

When you load a world map and set it as the session's `initialWorldMap`:

```swift
let config = ARWorldTrackingConfiguration()
config.initialWorldMap = savedWorldMap
sceneView.session.run(config)
```

ARKit does the following:

1. **Extracts features from the live camera feed** — the same process as normal tracking.
2. **Compares live features against saved features** — using the visual descriptors stored in the world map. This is essentially a "do I recognize this place?" comparison.
3. **Once enough features match**, ARKit knows where in the saved map the device is looking. It sets the world coordinate system to align with the saved map's coordinate system.
4. **All saved anchors snap into their original positions** — because the coordinate system now matches the one used when the anchors were created.

### Why Lighting Matters

Feature descriptors encode what a visual feature **looks like** — pixel intensities, gradients, etc. If the lighting changes dramatically between mapping and navigation (daylight vs. artificial light, bright vs. dim), the same physical features may produce different descriptors, making matching harder or impossible.

Best practice: map under the same lighting conditions your users will navigate in.

### How We Detect It in Code

ARKit doesn't fire a specific "relocalized!" callback. Instead, we watch the tracking state transition:

```swift
func session(_ session: ARSession, didUpdate frame: ARFrame) {
    let tracking = frame.camera.trackingState

    if self.appMode == .navigation && !self.isRelocalized {
        if case .normal = tracking {
            self.isRelocalized = true
            // tracking went from .limited(.relocalizing) → .normal
        }
    }
}
```

The tracking state progresses through:
- `.limited(.initializing)` — session just started
- `.limited(.relocalizing)` — actively searching for matches in the saved map
- `.normal` — localized! The coordinate system is aligned.

---

## 7. Waypoints — Building a Walkable Network

### Why Straight Lines Don't Work

In a real building, the path between two rooms goes through corridors, around corners, and through doorways. A straight-line path from your position to a destination would cut through walls.

Waypoints solve this. They're invisible path nodes placed along every walkable corridor. When the admin walks a hallway, waypoints are dropped every 1.5 meters, creating a trail of positions that a person can actually walk through.

### Auto-Drop Mechanism

The auto-drop system works in the ARSessionDelegate:

```swift
func session(_ session: ARSession, didUpdate frame: ARFrame) {
    if appMode == .mapping && isAutoWaypointEnabled {
        let cameraPos = /* extract XYZ from frame.camera.transform */

        if let lastPos = lastAutoWaypointPosition {
            let distanceMoved = simd_length(cameraPos - lastPos)
            if distanceMoved >= 1.5 {  // meters
                dropWaypoint(at: frame.camera.transform)
                lastAutoWaypointPosition = cameraPos
            }
        }
    }
}
```

This runs 60 times per second (every frame). It computes the Euclidean distance between the current camera position and the last waypoint's position. When that distance exceeds 1.5 meters, a new waypoint is dropped.

The `simd_length` function computes:

```
distance = sqrt((x2-x1)² + (y2-y1)² + (z2-z1)²)
```

Each waypoint is a `NavigationAnchor` with `kind: .waypoint`:

```swift
private func dropWaypoint(at transform: simd_float4x4) {
    waypointCount += 1
    let anchor = NavigationAnchor(
        destinationName: "WP-\(waypointCount)",
        kind: .waypoint,
        transform: transform
    )
    sceneView.session.add(anchor: anchor)
}
```

### The Waypoint Graph

After mapping, the session might contain something like:

```
Anchors in world map:
  WP-1  @ (0.0, 1.2, 0.0)     ← hallway start
  WP-2  @ (1.4, 1.2, 0.2)     ← 1.5m down the hall
  WP-3  @ (2.8, 1.2, 0.3)     ← further down
  WP-4  @ (4.2, 1.2, 0.1)     ← corner
  WP-5  @ (4.3, 1.2, 1.6)     ← turned left into side corridor
  WP-6  @ (4.2, 1.2, 3.0)     ← further down side corridor
  Kitchen @ (4.3, 1.2, 4.5)   ← destination
  WP-7  @ (5.6, 1.2, 0.0)     ← continued down main hall
  MeetingRoom @ (7.0, 1.2, 0.1) ← destination
```

These positions form a network. Consecutive waypoints are close together (< 5m), so they auto-connect in the pathfinding graph. This creates a walkable network that follows corridors.

---

## 8. Pathfinding — Two-Tier Approach

The app uses a sophisticated two-tier pathfinding system that adapts to available hardware capabilities.

### Tier 1: Obstacle-Aware Pathfinding (LiDAR)

On devices with LiDAR, the app extracts physical obstacles from the mesh and routes around them using GameplayKit.

#### Mesh Obstacle Extraction

`MeshObstacleExtractor` processes `ARMeshAnchor` data through several stages:

1. **Occupancy Grid Construction:**
   - Projects mesh vertices onto the floor plane
   - Creates a 2D grid (10cm resolution) marking occupied cells
   - Filters by height range (0.1m - 2.0m above floor) to capture furniture/walls

2. **Floor Height Detection:**
   - Uses percentile analysis of Y-coordinates to find the floor level
   - Accounts for uneven surfaces and measurement noise

3. **Connected Component Analysis:**
   - Groups adjacent occupied cells into obstacle regions
   - Filters out small noise (< 4 cells = 40cm²)

4. **Convex Hull Computation:**
   - Computes convex hull for each obstacle region
   - Expands polygons by buffer radius (40cm) for human clearance

```swift
// Extract obstacles from mesh anchors
let obstacles = MeshObstacleExtractor.extractObstacles(
    from: meshAnchors,
    floorY: estimatedFloorY,
    bufferRadius: 0.4
)
```

#### GKObstacleGraph

GameplayKit's `GKObstacleGraph` provides navigation mesh functionality:

```swift
obstacleGraph = GKObstacleGraph(
    obstacles: obstacles,        // [GKPolygonObstacle]
    bufferRadius: 0.4           // additional clearance
)

// Connect start and end points to the graph
let startNode = obstacleGraph.connectToLowestCostNode(
    node: GKGraphNode2D(point: startPoint),
    bidirectional: true
)

// Find path using A*
let path = obstacleGraph.findPath(from: startNode, to: endNode)
```

#### Path Smoothing

Raw paths from `GKObstacleGraph` can be jagged. The app applies Catmull-Rom spline interpolation:

```swift
func smoothPath(_ points: [SIMD3<Float>]) -> [SIMD3<Float>] {
    var smooth: [SIMD3<Float>] = []
    for i in 0..<(points.count - 1) {
        let p0 = points[max(0, i - 1)]
        let p1 = points[i]
        let p2 = points[i + 1]
        let p3 = points[min(points.count - 1, i + 2)]

        for t in stride(from: 0.0, to: 1.0, by: 0.1) {
            smooth.append(catmullRom(p0, p1, p2, p3, Float(t)))
        }
    }
    return smooth
}
```

### Tier 2: Waypoint-Based Dijkstra (Fallback)

When no mesh data is available (non-LiDAR devices or early in session), `PathFinder` uses the classic waypoint approach.

#### Graph Construction

`PathFinder.findPath()` builds a graph where:

- **Nodes:** Every anchor (waypoints + destinations) plus a virtual "start" node at the camera position.
- **Edges:** Two nodes are connected if within 5 meters. Edge weight = Euclidean distance.

```swift
for i in 0..<n {
    for j in (i + 1)..<n {
        let d = simd_length(positions[i] - positions[j])
        if d <= 5.0 {  // connectionRadius
            adj[i].append(Edge(to: j, weight: d))
            adj[j].append(Edge(to: i, weight: d))
        }
    }
}
```

Why 5 meters? Auto-dropped waypoints are 1.5m apart. Consecutive waypoints connect (~1.5m), but waypoints on opposite sides of a wall (different corridors) typically > 5m apart, so they won't connect.

#### Dijkstra's Algorithm

1. **Initialize:** Distance to start = 0, all others = infinity. All unvisited.
2. **Visit nearest unvisited:** Pick node with smallest distance, mark visited.
3. **Update neighbors:** Calculate distance through current node, update if shorter.
4. **Repeat** until destination reached or all reachable nodes visited.

**Time complexity:** O(n²) — fast enough for hundreds of waypoints.

### Worked Example

Imagine these anchors after mapping:

```
WP-1 (0,0,0) --- WP-2 (1.5,0,0) --- WP-3 (3,0,0) --- Kitchen (4.5,0,0)
                                          |
                                      WP-4 (3,0,1.5)
                                          |
                                      MeetingRoom (3,0,3)
```

User is at position (0.5, 0, 0.2) and wants to go to MeetingRoom.

1. **Graph construction:** Virtual start → WP-1 (0.5m), WP-1 → WP-2 (1.5m), WP-2 → WP-3 (1.5m), WP-3 → WP-4 (1.5m), WP-4 → MeetingRoom (1.5m), WP-3 → Kitchen (1.5m).

2. **Dijkstra runs:**
   - Start: dist=0
   - Visit WP-1: dist=0.5
   - Visit WP-2: dist=2.0
   - Visit WP-3: dist=3.5
   - Visit WP-4: dist=5.0
   - Visit MeetingRoom: dist=6.5

3. **Path reconstruction:** Start → WP-1 → WP-2 → WP-3 → WP-4 → MeetingRoom

4. **Result:** The path follows the L-shaped corridor, not a straight line through the wall.

---

## 9. AR Occlusion — Realistic Depth Rendering

AR occlusion makes virtual content (like the navigation path) render realistically behind real-world objects. Without occlusion, virtual objects always appear "on top" of everything, breaking the illusion.

### How Occlusion Works

Occlusion relies on **depth information** — knowing how far away each real-world surface is from the camera. On LiDAR devices, ARKit provides dense depth maps. For each pixel, the system knows:

1. **Real-world depth:** How far the physical surface is (from LiDAR).
2. **Virtual object depth:** How far the rendered geometry is (from SceneKit).

If the real-world surface is closer than the virtual object at a given pixel, the virtual object is hidden (occluded) at that pixel.

### Configuring Depth Semantics

ARKit must be configured to provide depth data:

```swift
let config = ARWorldTrackingConfiguration()

// Enable LiDAR depth for occlusion
if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
    config.frameSemantics.insert(.sceneDepth)
}

// Enable person segmentation for people occlusion
if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
    config.frameSemantics.insert(.personSegmentationWithDepth)
}
```

The `.sceneDepth` semantic provides depth from LiDAR scene reconstruction. The `.personSegmentationWithDepth` semantic uses ML to segment people and provide their depth, so people can occlude virtual objects even if they're moving.

### Material Configuration

SceneKit materials must be configured to participate in depth testing:

```swift
private func configureOcclusionMaterial(_ material: SCNMaterial) {
    // Read from depth buffer — check if something is in front
    material.readsFromDepthBuffer = true

    // Write to depth buffer — allow this object to occlude others
    material.writesToDepthBuffer = true

    // Use alpha blending for semi-transparent occlusion
    material.blendMode = .alpha
}
```

The path renderer applies this to all path geometry:

```swift
func createChevronGeometry() -> SCNGeometry {
    let shape = SCNShape(path: chevronPath, extrusionDepth: 0.003)
    let material = SCNMaterial()
    material.diffuse.contents = UIColor.systemCyan
    configureOcclusionMaterial(material)
    shape.materials = [material]
    return shape
}
```

### Rendering Order

For proper occlusion, virtual content should render after the depth buffer is populated:

```swift
// Path renders behind real objects
pathRenderer.rootNode.renderingOrder = -1
```

A negative `renderingOrder` causes SceneKit to render the path early in the render pass, allowing later-rendered content (real-world reconstruction mesh) to properly occlude it.

---

## 10. Rendering — Drawing 3D Objects in AR

### SceneKit and ARSCNView

The app uses `ARSCNView`, which combines:
- **ARKit:** Tracks the device, manages anchors, provides camera frames.
- **SceneKit:** Apple's 3D rendering engine. Handles geometry, materials, lighting, animations.

SceneKit renders a 3D scene graph — a tree of `SCNNode` objects, each with optional geometry, position, rotation, and child nodes. The root of this tree is `sceneView.scene.rootNode`.

`ARSCNView` automatically:
- Renders the camera feed as the background.
- Moves SceneKit's virtual camera to match the real camera (using the ARKit transform).
- Calls delegate methods when anchors are added, so you can attach 3D content to them.

### How Anchor Nodes Are Created

When ARKit adds an anchor (either from a `session.add()` call or from a loaded world map), it calls:

```swift
func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode?
```

We return a 3D node that gets automatically positioned at the anchor's transform. For destinations:

```swift
// Blue sphere (5cm radius)
let sphere = SCNSphere(radius: 0.05)
sphere.firstMaterial?.diffuse.contents = UIColor.systemBlue

// Floating text label
let text = SCNText(string: "Meeting Room", extrusionDepth: 0.5)
text.font = UIFont.systemFont(ofSize: 4, weight: .bold)
let textNode = SCNNode(geometry: text)
textNode.scale = SCNVector3(0.01, 0.01, 0.01)  // scale down

// Billboard constraint: label always faces the camera
let billboard = SCNBillboardConstraint()
billboard.freeAxes = .Y
textNode.constraints = [billboard]
```

For waypoints: smaller yellow semi-transparent spheres (2.5cm radius).

### Path Rendering Styles

`PathRenderer` supports three visualization styles, each with distinct characteristics:

#### Chevrons (Default)

Animated arrow shapes that "flow" toward the destination:

```swift
private func renderChevrons(path: [SIMD3<Float>]) {
    let pathData = interpolateWithDirection(along: path, spacing: chevronSpacing)

    for (index, data) in pathData.enumerated() {
        let node = createChevronNode(progress: progress, direction: data.direction)
        node.simdWorldPosition = data.position

        // Staggered wave animation
        addPulseAnimation(to: node, index: index, total: totalChevrons)
        containerNode.addChildNode(node)
    }
}
```

Each chevron is oriented to face its movement direction and pulses in a staggered wave pattern, creating the illusion of motion toward the destination.

#### Dots

Simple spheres placed along the path:

- 12mm radius spheres
- 15cm spacing
- Color gradient from cyan (near user) to blue (near destination)

#### Dotted Line

Continuous tubes connecting waypoints:

- 8mm radius cylinders
- Each segment oriented along the path direction
- Color gradient based on progress

### Destination Marker

All styles render a pulsing destination marker:

```swift
private func createDestinationNode() -> SCNNode {
    let cylinder = SCNCylinder(radius: 0.06, height: 0.15)
    cylinder.firstMaterial?.diffuse.contents = UIColor.systemGreen
    cylinder.firstMaterial?.transparency = 0.7

    let node = SCNNode(geometry: cylinder)

    // Pulsing animation
    let pulse = SCNAction.sequence([
        .scale(to: 1.3, duration: 0.6),
        .scale(to: 1.0, duration: 0.6)
    ])
    node.runAction(.repeatForever(pulse))

    return node
}
```

### Path Interpolation

The path is interpolated to place markers at regular intervals regardless of waypoint spacing:

```swift
private func interpolateWithDirection(along path: [SIMD3<Float>], spacing: Float) -> [PathPoint] {
    var result: [PathPoint] = []
    var accumulated: Float = 0

    for i in 0..<(path.count - 1) {
        let direction = path[i + 1] - path[i]
        let length = simd_length(direction)
        let normalized = simd_normalize(direction)

        var offset = spacing - accumulated
        while offset <= length {
            let position = path[i] + normalized * offset
            result.append(PathPoint(position: position, direction: normalized))
            offset += spacing
        }
        accumulated = length - (offset - spacing)
    }
    return result
}
```

All path geometry is children of `containerNode`, which is always attached to the scene root. To redraw, we clear all children and add new ones.

### The Render Loop

SceneKit calls `renderer(_:updateAtTime:)` every frame (60 FPS). We use this to update the path:

```swift
func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
    guard time - lastPathUpdateTime > 0.15 else { return }  // throttle to ~7 FPS
    lastPathUpdateTime = time

    let cameraPos = sceneView.pointOfView!.simdWorldPosition
    currentPath = PathFinder.findPath(from: cameraPos, to: dest, through: allLoadedAnchors)
    renderPath(currentPath)
}
```

We throttle to ~7 updates/second because:
- Rebuilding the path every frame (60 FPS) would be wasteful.
- The user doesn't walk fast enough to need sub-150ms updates.
- Graph pathfinding + geometry creation has some overhead.

---

## 11. 3D Scan Viewer — Visualizing Mapped Spaces

The "My Scans" tab provides an interactive 3D visualization of mapped spaces, allowing users to browse and explore their scans outside of AR.

### Mesh Data Export

When a map is saved, `MeshDataStore` exports the LiDAR mesh data to JSON:

```swift
struct MeshExportData: Codable {
    let chunks: [MeshChunk]
    let boundingBox: BoundingBox
    let exportDate: Date
    let destinationCount: Int
}

struct MeshChunk: Codable {
    let vertices: [[Float]]      // [[x, y, z], ...]
    let normals: [[Float]]       // [[nx, ny, nz], ...]
    let indices: [Int]           // triangle indices
    let transform: [[Float]]     // 4x4 transform matrix
}
```

The export process:
1. Iterates through all `ARMeshAnchor` instances
2. Extracts vertex positions, normals, and triangle indices from `ARMeshGeometry`
3. Converts to Codable structures
4. Serializes to JSON and saves to `MeshData/<zone-id>.json`

### SceneKit Reconstruction

`ScanViewer3D` reconstructs the mesh in a standalone `SCNView`:

```swift
func buildMeshNode(from exportData: MeshExportData) -> SCNNode {
    let containerNode = SCNNode()

    for chunk in exportData.chunks {
        // Convert vertices to SCNGeometrySource
        let vertices = chunk.vertices.map { SCNVector3($0[0], $0[1], $0[2]) }
        let vertexSource = SCNGeometrySource(vertices: vertices)

        // Convert normals
        let normals = chunk.normals.map { SCNVector3($0[0], $0[1], $0[2]) }
        let normalSource = SCNGeometrySource(normals: normals)

        // Create triangle elements
        let indices = chunk.indices.map { Int32($0) }
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)

        // Build geometry
        let geometry = SCNGeometry(sources: [vertexSource, normalSource], elements: [element])
        geometry.firstMaterial = createHeightColoredMaterial(for: vertices)

        let node = SCNNode(geometry: geometry)
        node.simdTransform = chunk.transformMatrix
        containerNode.addChildNode(node)
    }

    return containerNode
}
```

### Height-Based Coloring

The scan viewer uses a height-based color gradient for visual clarity:

```swift
func createHeightColoredMaterial(for vertices: [SCNVector3]) -> SCNMaterial {
    // Compute height range
    let minY = vertices.min(by: { $0.y < $1.y })?.y ?? 0
    let maxY = vertices.max(by: { $0.y < $1.y })?.y ?? 1
    let heightRange = maxY - minY

    // Apply color gradient: blue (low) → cyan → green → yellow (high)
    let material = SCNMaterial()
    material.diffuse.contents = UIColor.systemCyan
    material.lightingModel = .physicallyBased

    return material
}
```

The gradient mapping:
- **Blue** (0.0 - 0.25): Floor level
- **Cyan** (0.25 - 0.5): Low furniture
- **Green** (0.5 - 0.75): Mid-height objects
- **Yellow** (0.75 - 1.0): Tall objects / walls

### Viewer Features

The `ScanViewer3D` component provides:

- **Pan/Rotate/Zoom:** Standard SceneKit camera controls
- **Wireframe Mode:** Toggle to show mesh structure
- **Destination Markers:** 3D pins showing destination locations
- **Floor Grid:** Reference grid for spatial orientation
- **Mesh Statistics:** Vertex count, bounding box dimensions

---

## 12. Zone Management — Multi-Space Organization

Zones provide a way to organize multiple mapped areas (floors, buildings, rooms) within the app.

### Zone Model

```swift
struct MapZone: Identifiable, Codable {
    let id: UUID
    var name: String
    var description: String
    var createdAt: Date
    var lastModified: Date
    var destinationCount: Int
    var waypointCount: Int

    var mapFileName: String {
        "zone_\(id.uuidString)"
    }

    var displayName: String {
        name.isEmpty ? "Untitled Zone" : name
    }
}
```

Each zone has:
- Unique identifier linking to map and mesh files
- User-editable name and description
- Timestamps for sorting and display
- Anchor counts for summary display

### Zone Store

`ZoneStore` is a singleton managing the zone manifest:

```swift
@MainActor
class ZoneStore: ObservableObject {
    static let shared = ZoneStore()

    @Published private(set) var zones: [MapZone] = []

    private var manifestURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("zones.json")
    }

    func createZone(name: String, description: String = "") -> MapZone {
        let zone = MapZone(
            id: UUID(),
            name: name,
            description: description,
            createdAt: Date(),
            lastModified: Date(),
            destinationCount: 0,
            waypointCount: 0
        )
        zones.append(zone)
        saveManifest()
        return zone
    }

    func updateZone(_ zone: MapZone, destinationCount: Int, waypointCount: Int) {
        if let index = zones.firstIndex(where: { $0.id == zone.id }) {
            zones[index].destinationCount = destinationCount
            zones[index].waypointCount = waypointCount
            zones[index].lastModified = Date()
            saveManifest()
        }
    }

    func deleteZone(_ zone: MapZone) {
        zones.removeAll { $0.id == zone.id }
        try? MapStore.delete(name: zone.mapFileName)
        try? MeshDataStore.shared.deleteMeshData(forZone: zone.id)
        saveManifest()
    }
}
```

### Legacy Migration

When the app launches, `ZoneStore` automatically migrates legacy maps (saved before zone support) into the new system:

```swift
private func migrateLegacyMaps() {
    let existingMapNames = MapStore.list()
    let existingZoneFileNames = Set(zones.map(\.mapFileName))

    for mapName in existingMapNames {
        // Skip if already migrated
        guard !existingZoneFileNames.contains(mapName) else { continue }
        guard !mapName.hasPrefix("zone_") else { continue }

        // Create zone for legacy map
        let zone = MapZone(
            id: UUID(),
            name: mapName,
            description: "Migrated from legacy format",
            createdAt: Date(),
            lastModified: Date(),
            destinationCount: 0,
            waypointCount: 0
        )
        zones.append(zone)

        // Rename map file to new format
        try? MapStore.rename(from: mapName, to: zone.mapFileName)
    }
}
```

---

## 13. Haptic Feedback — Rich Touch Responses

The app uses CoreHaptics for rich, contextual haptic feedback throughout the user journey.

### CoreHaptics Integration

`HapticManager` is a singleton that prepares and plays haptic patterns:

```swift
@MainActor
final class HapticManager {
    static let shared = HapticManager()

    private var engine: CHHapticEngine?
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private let notification = UINotificationFeedbackGenerator()
    private let selection = UISelectionFeedbackGenerator()

    private init() {
        prepareGenerators()
        setupHapticEngine()
    }

    private func prepareGenerators() {
        impactLight.prepare()
        impactMedium.prepare()
        impactHeavy.prepare()
        notification.prepare()
        selection.prepare()
    }

    private func setupHapticEngine() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            engine = try CHHapticEngine()
            try engine?.start()
        } catch {
            print("Haptic engine failed: \(error)")
        }
    }
}
```

### Feedback Patterns

The app provides context-specific haptic feedback:

#### Simple Feedback (UIFeedbackGenerator)

```swift
func selectionChanged() {
    selection.selectionChanged()
}

func waypointDropped() {
    impactLight.impactOccurred()
}

func destinationDropped() {
    impactMedium.impactOccurred()
}

func error() {
    notification.notificationOccurred(.error)
}
```

#### Custom Patterns (CoreHaptics)

For special moments like arrival, a custom pattern provides a "celebration" feel:

```swift
func arrived() {
    // Play notification first
    notification.notificationOccurred(.success)

    // Then play custom celebration pattern
    playArrivalPattern()
}

private func playArrivalPattern() {
    guard let engine = engine else { return }

    let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0)
    let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)

    // Build celebratory sequence: quick bursts
    var events: [CHHapticEvent] = []
    let times: [TimeInterval] = [0, 0.1, 0.2, 0.35, 0.5]

    for time in times {
        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [intensity, sharpness],
            relativeTime: time
        )
        events.append(event)
    }

    do {
        let pattern = try CHHapticPattern(events: events, parameters: [])
        let player = try engine.makePlayer(with: pattern)
        try player.start(atTime: 0)
    } catch {
        // Fallback to simple feedback
        notification.notificationOccurred(.success)
    }
}
```

#### Usage Throughout App

| Event | Feedback Type | Pattern |
|-------|---------------|---------|
| Mode switch | Selection | Single light tap |
| Waypoint dropped | Impact (light) | Quick tap |
| Destination dropped | Impact (medium) | Stronger tap |
| Destination selected | Impact (light) | Quick tap |
| Map saved | Notification (success) | Double tap |
| Relocalized | Notification (success) | Double tap |
| Arrived | Custom pattern | Celebration burst |
| Error | Notification (error) | Warning buzz |

---

## 14. The SwiftUI ↔ UIKit Bridge

### UIViewRepresentable

`ARSCNView` is a UIKit view. SwiftUI can't use it directly. The bridge is `UIViewRepresentable`:

```swift
struct ARViewContainer: UIViewRepresentable {
    let arManager: ARManager

    func makeUIView(context: Context) -> UIView {
        let container = UIView()

        // Add AR view
        let arView = arManager.arView
        arView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(arView)

        // Add coaching overlay
        let coachingOverlay = ARCoachingOverlayView()
        coachingOverlay.session = arManager.arView.session
        coachingOverlay.goal = .tracking
        coachingOverlay.activatesAutomatically = true
        container.addSubview(coachingOverlay)

        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
```

The view wraps both the ARSCNView and ARCoachingOverlayView, providing built-in Apple guidance for tracking quality.

### ObservableObject and @Published

The view model uses Combine's `ObservableObject` protocol to bridge AR state to SwiftUI:

```swift
@MainActor
class NavigationViewModel: ObservableObject {
    @Published var trackingState: ARCamera.TrackingState = .notAvailable
    @Published var isRelocalized = false
    @Published var distanceToDestination: Float?
    @Published var appMode: AppMode = .mapping
    // ...
}
```

Every time a `@Published` property changes, SwiftUI automatically re-renders any view that reads it.

---

## 15. Architecture — MVVM Pattern

The app follows the Model-View-ViewModel pattern with clear separation of concerns.

### ARManager (Session Management)

`ARManager` owns the AR session lifecycle and SceneKit rendering:

```swift
final class ARManager: NSObject {
    private let sceneView: ARSCNView
    private weak var viewModel: NavigationViewModel?
    private let pathRenderer = PathRenderer()
    private let obstaclePathfinder = ObstacleAwarePathfinder()

    var arView: ARSCNView { sceneView }

    func startMappingSession() { ... }
    func startNavigationSession(mapName: String) { ... }
    func dropDestination(named: String) -> NavigationAnchor? { ... }
    func dropWaypoint(named: String) -> (anchor: NavigationAnchor, position: SIMD3<Float>)? { ... }
    func saveWorldMap(name: String, completion: ...) { ... }
}
```

**Responsibilities:**
- ARKit session configuration and lifecycle
- Anchor creation and management
- Mesh tracking for obstacle pathfinding
- Path rendering via `PathRenderer`
- SceneKit delegate callbacks

### NavigationViewModel (State Container)

`NavigationViewModel` is the `@MainActor` observable state container:

```swift
@MainActor
class NavigationViewModel: ObservableObject {
    // AR State
    @Published var trackingState: ARCamera.TrackingState = .notAvailable
    @Published var worldMappingStatus: ARFrame.WorldMappingStatus = .notAvailable
    @Published var isRelocalized = false

    // Navigation State
    @Published var appMode: AppMode = .mapping
    @Published var selectedDestination: NavigationAnchor?
    @Published var distanceToDestination: Float?

    // Zone Management
    @Published var selectedZone: MapZone?
    @Published var showZoneEditor = false

    // Error Handling
    @Published var currentError: AppError?

    // Methods
    func prepareForMappingMode() { ... }
    func prepareForNavigationMode() { ... }
    func handleMapLoaded(anchors: ...) { ... }
    func updateDistance(_ distance: Float) { ... }
}
```

**Responsibilities:**
- All `@Published` state for SwiftUI binding
- Mode transitions and state cleanup
- Error handling and recovery
- Zone management coordination
- Relocalization timeout tracking

### Separation of Concerns

```
┌─────────────────────────────────────────────────────────────┐
│                      SwiftUI Views                          │
│  (MainTabView, ARTabView, ScansTabView, ZoneSelectorView)  │
└─────────────────────────┬───────────────────────────────────┘
                          │ @StateObject / @ObservedObject
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                  NavigationViewModel                        │
│  (@MainActor, @Published state, UI-facing methods)         │
└─────────────────────────┬───────────────────────────────────┘
                          │ weak reference
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                      ARManager                              │
│  (ARKit session, SceneKit rendering, pathfinding)          │
└─────────────────────────┬───────────────────────────────────┘
                          │
          ┌───────────────┼───────────────┐
          ▼               ▼               ▼
┌─────────────┐   ┌─────────────┐   ┌─────────────┐
│ PathFinder  │   │ PathRenderer│   │ Obstacle-   │
│             │   │             │   │ Aware-      │
│             │   │             │   │ Pathfinder  │
└─────────────┘   └─────────────┘   └─────────────┘
```

This architecture:
- Prevents retain cycles (weak references from ARManager to ViewModel)
- Keeps UI-facing state isolated in ViewModel
- Allows independent testing of pathfinding and rendering
- Makes SwiftUI binding straightforward

---

## 16. Threading Model

ARKit and SceneKit use multiple threads. Understanding the threading is critical for avoiding crashes:

| Context | Thread | What runs here |
|---|---|---|
| SwiftUI views | Main thread | All UI rendering, @Published property updates |
| ARSessionDelegate callbacks | AR session queue (background) | `session(_:didUpdate:)`, `session(_:didFailWithError:)` |
| ARSCNViewDelegate callbacks | SceneKit render thread | `renderer(_:nodeFor:)`, `renderer(_:updateAtTime:)` |

**Rule:** `@Published` properties must only be set from the main thread. That's why delegate callbacks dispatch to main:

```swift
func session(_ session: ARSession, didUpdate frame: ARFrame) {
    let tracking = frame.camera.trackingState  // read on session queue

    DispatchQueue.main.async { [weak self] in
        self?.trackingState = tracking  // write on main queue
    }
}
```

For the render loop (`renderer(_:updateAtTime:)`), scene graph modifications (adding/removing nodes) are safe on the render thread. But publishing distance updates to SwiftUI must go through `DispatchQueue.main.async`.

---

## 17. Complete Data Flow: Mapping to Navigation

### Phase 1: Mapping

```
Admin walks with phone
    │
    ▼
ARKit tracks camera position (VIO)
    │
    ├──▶ Auto-waypoint check every frame
    │    └── If moved ≥ 1.5m → create NavigationAnchor(kind: .waypoint)
    │         └── ARSession.add(anchor:) → anchor stored in session
    │
    ├──▶ Admin taps "Drop" for destination
    │    └── create NavigationAnchor(kind: .destination, name: "Kitchen")
    │         └── ARSession.add(anchor:) → anchor stored in session
    │
    ▼
Admin taps "Save"
    │
    ▼
ARSession.getCurrentWorldMap() → ARWorldMap
    │  Contains: feature points + all anchors (destinations + waypoints)
    │
    ▼
NSKeyedArchiver.archivedData(worldMap) → Data (binary blob)
    │  NavigationAnchor.encode(with:) serializes destinationName + kind
    │
    ▼
Data.write(to: Documents/IndoorNavMaps/MyMap.arexperience)
    │
    ▼
File on disk ✓
```

### Phase 2: Navigation

```
User selects "Navigate" → picks "MyMap" from list
    │
    ▼
Data(contentsOf: .../MyMap.arexperience) → binary Data
    │
    ▼
NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self) → ARWorldMap
    │  NavigationAnchor.init?(coder:) restores destinationName + kind
    │
    ▼
Extract destinations and waypoints from worldMap.anchors
    │
    ▼
ARWorldTrackingConfiguration.initialWorldMap = worldMap
    │
    ▼
ARSession.run(config) → relocalization begins
    │
    ├──▶ User points phone at mapped area
    │    └── ARKit matches live features against saved feature cloud
    │
    ▼
TrackingState transitions: .limited(.relocalizing) → .normal
    │
    ▼
isRelocalized = true → UI shows destination picker
    │
    ▼
User taps "Kitchen"
    │
    ▼
Every 150ms in render loop:
    │
    ├──▶ Read camera position from pointOfView.simdWorldPosition
    │
    ├──▶ PathFinder.findPath(from: cameraPos, to: kitchen, through: allAnchors)
    │    ├── Build graph: nodes within 5m connected
    │    ├── Add virtual start node at camera position
    │    ├── Dijkstra: find shortest path start → kitchen
    │    └── Return: [cameraPos, WP-3, WP-7, WP-12, Kitchen]
    │
    ├──▶ renderPath(): place cyan dots every 25cm along the path segments
    │
    └──▶ Compute walking distance (sum of segment lengths) → publish to UI
```

---

## 18. File-by-File Code Walkthrough

### App Layer

**`IndoorNavApp.swift`** — The `@main` entry point. Creates a `WindowGroup` containing `MainTabView`.

**`MainTabView.swift`** — Tab container with AR and Scans tabs. Contains `ARTabView` (the main AR navigation interface) and integrates `AppState` singleton for cross-tab coordination.

### Views

**`ARViewContainer.swift`** — `UIViewRepresentable` wrapping `ARSCNView` and `ARCoachingOverlayView`. Bridges UIKit AR views to SwiftUI.

**`ScansTabView.swift`** — Gallery of mapped zones with `ScanCardView` grid. Shows preview icons, metadata, and links to detail view.

**`ScanViewer3D.swift`** — Interactive SceneKit 3D viewer for mesh data. Supports pan/rotate/zoom, wireframe mode, height-based coloring.

**`ZoneSelectorView.swift`** — Zone picker and editor UI. Contains `ZoneRowView` for list items and `ZoneEditorSheet` for create/edit.

### ViewModels

**`NavigationViewModel.swift`** — The `@MainActor` observable state container. All `@Published` state for SwiftUI, mode transitions, zone management, error handling, and relocalization timeout tracking.

### Services

**`ARManager.swift`** — AR session lifecycle and SceneKit rendering. Manages ARKit configuration, anchor creation, mesh tracking, obstacle graph building, and path rendering coordination.

**`MapStore.swift`** — Stateless utility (enum with static methods). CRUD operations for `IndoorNavMaps` directory. Sorts by modification date.

**`MeshDataStore.swift`** — Exports LiDAR mesh data to JSON for the Scans tab. Reconstructs SceneKit geometry with height-based coloring.

**`PathFinder.swift`** — Waypoint-based Dijkstra pathfinding. Builds adjacency list, runs shortest path algorithm, falls back to straight line if no path exists.

**`ObstacleAwarePathfinder.swift`** — GameplayKit `GKObstacleGraph` integration. Builds navigation mesh from LiDAR obstacles, finds paths using A*, applies Catmull-Rom smoothing.

**`MeshObstacleExtractor.swift`** — Processes `ARMeshAnchor` data into obstacles. Occupancy grid construction, connected component analysis, convex hull computation, polygon expansion.

**`HapticManager.swift`** — CoreHaptics integration. Singleton with prepared feedback generators and custom haptic patterns for arrival celebration.

### Models

**`NavigationAnchor.swift`** — Custom `ARAnchor` subclass with `destinationName` and `kind`. Implements `NSSecureCoding` for world map serialization.

**`MapZone.swift`** — Zone model with metadata. `ZoneStore` singleton manages zone manifest with CRUD operations and legacy migration.

**`AppError.swift`** — Typed errors with user-facing messages, recovery suggestions, and alert titles.

### Rendering

**`PathRenderer.swift`** — Animated path visualization with three styles (chevrons, dots, dotted line). Handles occlusion material configuration and wave animations.

### Design

**`DesignSystem.swift`** — Unified design system with color palette, typography (SF Rounded), view modifiers, and reusable components (`StatusBadge`, `PillButtonStyle`).

---

## 19. Key Apple Frameworks Used

| Framework | What it provides | How we use it |
|---|---|---|
| **ARKit** | Camera tracking, world mapping, anchor management, relocalization, LiDAR mesh | The foundation — everything spatial, including mesh reconstruction |
| **SceneKit** | 3D rendering engine (geometry, materials, animations, scene graph) | Rendering anchor markers, navigation path, and 3D scan viewer |
| **GameplayKit** | Pathfinding (`GKObstacleGraph`, `GKPolygonObstacle`), agent behaviors | Obstacle-aware navigation routing around physical objects |
| **CoreHaptics** | Rich haptic feedback with custom patterns | Celebration feedback on arrival, contextual touch responses |
| **SwiftUI** | Declarative UI framework | All 2D UI overlays, tab navigation, zone management |
| **Combine** | Reactive programming (`@Published`, `ObservableObject`) | Bridging AR state changes to SwiftUI re-renders |
| **simd** | Hardware-accelerated vector/matrix math | 3D position calculations, distance computations |
| **Foundation** | File I/O, `NSKeyedArchiver`, `FileManager`, `JSONEncoder` | Map/mesh persistence, zone manifest |

---

## 20. Glossary

| Term | Definition |
|---|---|
| **ARAnchor** | A fixed position/orientation in the real world, tracked by ARKit. Survives coordinate system adjustments. |
| **ARFrame** | A single timestamped snapshot: camera image + camera transform + tracking metadata. Delivered ~60 times/second. |
| **ARSCNView** | A UIKit view that combines ARKit tracking with SceneKit 3D rendering over a live camera feed. |
| **ARSession** | The runtime that manages ARKit tracking. You configure it, run it, and receive delegate callbacks. |
| **ARWorldMap** | A serializable snapshot of ARKit's spatial understanding: feature points, anchors, planes. |
| **ARWorldTrackingConfiguration** | Configuration that enables 6-DOF (six degrees of freedom) tracking using camera + IMU. |
| **Billboard constraint** | A SceneKit constraint that makes a node always face the camera (like a signpost that rotates to face you). |
| **Connection radius** | The maximum distance (5m) between two anchors for them to be connected in the pathfinding graph. |
| **Destination** | A named NavigationAnchor (kind: .destination) representing a place the user might want to navigate to. |
| **Dijkstra's algorithm** | A graph algorithm that finds the shortest weighted path from a source node to all other nodes. |
| **Feature point** | A visually distinctive pixel (corner, edge) that ARKit tracks across frames to determine camera motion. |
| **LiDAR** | Light Detection And Ranging. An infrared laser scanner that measures distances to build a 3D depth map. |
| **NSKeyedArchiver** | Apple's serialization system for converting Objective-C/Swift objects to binary data and back. |
| **NSSecureCoding** | A protocol that ensures type safety during deserialization (prevents type confusion attacks). |
| **Relocalization** | The process of matching a live camera view against a saved world map to determine the device's position within it. |
| **Scene reconstruction** | Using LiDAR data to build a 3D triangle mesh of the physical environment. |
| **simd_float4x4** | A 4×4 matrix of 32-bit floats, used to represent position + rotation (a "transform") in 3D space. |
| **SIMD3\<Float\>** | A 3-component vector (x, y, z) for representing positions and directions in 3D. |
| **UIViewRepresentable** | A SwiftUI protocol for wrapping UIKit views so they can be used in SwiftUI layouts. |
| **VIO** | Visual-Inertial Odometry. ARKit's core tracking technology fusing camera and IMU data. |
| **Waypoint** | A NavigationAnchor (kind: .waypoint) representing a walkable position along a corridor. Not visible to the end user during navigation. |
| **World coordinate system** | The 3D coordinate space ARKit establishes when a session starts. Origin at the device's initial position, Y-up, units in meters. |
| **World mapping status** | ARKit's assessment of how thoroughly the current environment has been mapped (.notAvailable → .limited → .extending → .mapped). |
| **AR Occlusion** | Technique for rendering virtual objects behind real-world surfaces using depth buffer testing. Makes AR content appear realistic. |
| **ARCoachingOverlayView** | Apple's built-in UI overlay that guides users to improve tracking quality with visual instructions. |
| **ARMeshAnchor** | An anchor representing a chunk of the LiDAR-reconstructed 3D mesh. Contains vertices, normals, and triangle indices. |
| **Catmull-Rom spline** | A type of interpolating spline that passes through control points, used to smooth jagged paths. |
| **CHHapticEngine** | CoreHaptics engine for creating and playing custom haptic patterns beyond simple vibrations. |
| **Convex hull** | The smallest convex polygon containing a set of points. Used to simplify obstacle shapes for pathfinding. |
| **GKObstacleGraph** | GameplayKit class that builds a navigation mesh around obstacles for efficient pathfinding. |
| **GKPolygonObstacle** | GameplayKit obstacle defined by a polygon outline. Pathfinding routes around these shapes. |
| **Occupancy grid** | A 2D grid where each cell is marked as occupied or free. Used to convert 3D mesh to 2D obstacles. |
| **sceneDepth** | ARKit frame semantic that provides per-pixel depth information from LiDAR for occlusion rendering. |
| **Zone** | An organizational unit representing a mapped indoor space. Contains references to map and mesh data files. |
