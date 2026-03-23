# IndoorNav — AR Indoor Navigation

A production-ready, hardware-free indoor AR navigation app for iOS. An admin maps a physical space by walking through it — the app automatically lays down waypoints along corridors and the admin drops named destination markers at key locations. Users then load that map, relocalize their device, and follow an **obstacle-aware AR path** that renders realistically behind real-world objects.

Built with **SwiftUI**, **ARKit**, **SceneKit**, and **GameplayKit**.

---

## Key Features

- **LiDAR-Powered Obstacle Avoidance** — Path routes around walls, furniture, and obstacles using mesh reconstruction
- **AR Occlusion** — Navigation path renders behind real-world objects for realistic depth
- **3D Scan Viewer** — Browse and explore your mapped spaces in an interactive 3D viewer
- **Multi-Zone Support** — Organize maps into named zones (Lobby, Floor 2, Cafeteria)
- **Animated Path Visualization** — Glowing chevrons that flow toward your destination
- **Rich Haptic Feedback** — CoreHaptics patterns for all interactions
- **ARCoachingOverlay** — Built-in Apple guidance for tracking quality

---

## Table of Contents

- [Requirements](#requirements)
- [Getting Started](#getting-started)
- [App Tabs](#app-tabs)
  - [AR Navigation Tab](#ar-navigation-tab)
  - [My Scans Tab](#my-scans-tab)
- [How It Works](#how-it-works)
  - [1. Map the Space (Admin Mode)](#1-map-the-space-admin-mode)
  - [2. Navigate (User Mode)](#2-navigate-user-mode)
- [Architecture](#architecture)
  - [File Overview](#file-overview)
  - [Key Classes](#key-classes)
  - [Data Flow](#data-flow)
- [Technical Details](#technical-details)
  - [AR Configuration & Occlusion](#ar-configuration--occlusion)
  - [Waypoints & Auto-Drop](#waypoints--auto-drop)
  - [Pathfinding (Obstacle-Aware)](#pathfinding-obstacle-aware)
  - [Map & Mesh Storage](#map--mesh-storage)
  - [Custom Anchor Serialization](#custom-anchor-serialization)
  - [Relocalization](#relocalization)
  - [Path Rendering](#path-rendering)
- [Example: Mapping Your Office](#example-mapping-your-office)
- [Troubleshooting](#troubleshooting)
- [Limitations](#limitations)
- [License](#license)

---

## Requirements

| Requirement | Minimum |
|---|---|
| Xcode | 15.0+ |
| iOS Deployment Target | 16.0 |
| Swift | 5.9 |
| Device | Physical iPhone or iPad with ARKit support (A9 chip or later) |
| Recommended | LiDAR-equipped device (iPhone 12 Pro+, iPad Pro 2020+) for obstacle avoidance and AR occlusion |

ARKit does **not** run in the iOS Simulator. You must build and run on a physical device.

**LiDAR Benefits:**
- Obstacle-aware pathfinding (routes around walls/furniture)
- AR occlusion (path renders behind real objects)
- 3D mesh export for the Scans tab
- Faster and more accurate relocalization

---

## Getting Started

### 1. Clone or open the project

```bash
cd /path/to/lidar-project
open IndoorNav.xcodeproj
```

### 2. Configure signing

1. Open `IndoorNav.xcodeproj` in Xcode.
2. Select the **IndoorNav** target in the project navigator.
3. Go to **Signing & Capabilities**.
4. Set **Team** to your Apple Developer account (free or paid).
5. Optionally change **Bundle Identifier** from `com.example.IndoorNav` to something unique.

### 3. Build and run

1. Connect a physical iOS device via USB or Wi-Fi.
2. Select your device as the run destination.
3. Press **Cmd+R** to build and run.
4. Grant camera access when prompted.

---

## App Tabs

The app has two main tabs accessible from the bottom tab bar.

### AR Navigation Tab

The primary interface for mapping and navigating indoor spaces.

- **Map the Space mode**: Walk through a space to create a navigable map with destinations and waypoints
- **Navigate mode**: Load a saved map, relocalize, and follow the AR path to your destination
- **Zone Selection**: Create and manage named zones for different areas
- **Real-time Feedback**: Status indicators for tracking quality, world mapping, and LiDAR status

### My Scans Tab

A gallery of all your mapped zones with interactive 3D visualization.

- **Scan Cards**: Visual grid of all zones with preview icons and metadata
- **3D Viewer**: Pan, rotate, and zoom your scans in SceneKit
- **Height Visualization**: Color-coded mesh based on elevation (blue→cyan→green→yellow)
- **Destination Markers**: See your placed destinations as 3D markers
- **Mesh Statistics**: View vertex count, bounding box dimensions
- **Display Options**: Toggle wireframe mode, color schemes, destination visibility

---

## How It Works

The AR Navigation tab has two modes, controlled by a segmented toggle at the top of the screen.

### 1. Map the Space (Admin Mode)

This mode is for an administrator to create a navigable map of an indoor space.

#### Step A: Enable auto-waypoints and walk

1. Toggle **Auto-Waypoints** ON (yellow switch at the top of the controls).
2. Walk slowly through every corridor, hallway, and room you want to be navigable.
3. The app automatically drops a waypoint every ~1.5 meters as you walk. These appear as small yellow spheres in AR space. They define the **walkable paths** that navigation will follow.
4. You can also tap **+ WP** to manually drop a waypoint at your current position (useful for corners or junctions).

#### Step B: Drop destination markers

At each point of interest (meeting room door, restroom, elevator, kitchen, etc.):
1. Type a name in the "Destination name" field (e.g., "Meeting Room A").
2. Tap **Drop**. A blue 3D sphere with a floating label appears at that position.
3. Repeat for every destination in the space.

#### Step C: Save the map

1. Type a name in the "Map name" field (e.g., "Office Floor 3").
2. Wait until the World Map status is at least **Extending** (yellow) or **Mapped** (green).
3. Tap **Save**. The entire world map — including all waypoints, destinations, and visual features — is archived to disk.

You can save multiple maps (different floors, buildings, etc.). Each is stored as a separate file.

**Tips for good mapping:**
- Walk slowly and steadily. Avoid sudden movements.
- Cover corridors from one end to the other — don't skip sections.
- At junctions/intersections, walk each branch so waypoints connect all paths.
- Ensure adequate lighting and visual texture (posters, furniture, signs help).
- More waypoints = better route quality. Auto-drop at 1.5m spacing is usually sufficient.

### 2. Navigate (User Mode)

This mode is for anyone who needs to find their way through a mapped space.

#### Step A: Select a map

Switch to "Navigate" mode. A list of all saved maps appears. Tap the map you want (e.g., "Office Floor 3").

#### Step B: Relocalize

The app loads the saved world map and starts matching the live camera to it. A spinner shows "Look around to localize..." — point the device at the same physical area where the map was created and move slowly. When ARKit matches enough visual features, a green "Localized" badge appears.

#### Step C: Select a destination

Tap one of the destination buttons (e.g., "Meeting Room A"). A cyan dotted path appears in AR space, **following the waypoints** through corridors — not cutting through walls.

#### Step D: Follow the path

Walk along the dotted path. The route and distance update in real-time. When you're within 0.5 meters, "You have arrived!" appears.

You can tap a different destination at any time to reroute, or tap **Clear** to dismiss the path.

---

## Example: Mapping Your Office

Here's a concrete walkthrough for mapping a typical office floor:

1. **Start at the entrance.** Open the app, ensure you're in "Map the Space" mode, and toggle Auto-Waypoints ON.

2. **Walk the main corridor.** Walk slowly down the main hallway. The app drops yellow waypoints every 1.5m automatically. You'll see the waypoint counter incrementing.

3. **At each door, drop a destination.** When you reach the entrance to "Conference Room B", stop, type "Conference Room B", and tap Drop. A blue sphere appears at that spot.

4. **Walk every branch.** If there's a side corridor to the kitchen, walk down it (waypoints auto-drop along the way), drop a "Kitchen" destination, then walk back to the main corridor and continue.

5. **Cover the whole floor.** Walk every corridor you want to be navigable. The more thoroughly you walk, the better the navigation routes will be.

6. **Save.** Once you've covered everything and the world map status is yellow or green, type "Office 3rd Floor" as the map name and tap Save.

7. **Test it.** Switch to Navigate mode, select "Office 3rd Floor", localize, and tap a destination. The path should follow the corridors you walked.

---

## Architecture

### File Overview

```
IndoorNav/
├── App
│   └── IndoorNavApp.swift           # @main entry point → MainTabView
│
├── Views
│   ├── MainTabView.swift            # Tab container (AR + Scans tabs)
│   ├── ARViewContainer.swift        # UIViewRepresentable + ARCoachingOverlay
│   ├── ScansTabView.swift           # 3D scan gallery with cards
│   ├── ScanViewer3D.swift           # Interactive SceneKit 3D viewer
│   └── ZoneSelectorView.swift       # Zone picker + editor sheet
│
├── ViewModels
│   └── NavigationViewModel.swift    # @Published state, zone management
│
├── Services
│   ├── ARManager.swift              # AR session, occlusion, mesh tracking
│   ├── MapStore.swift               # ARWorldMap persistence
│   ├── MeshDataStore.swift          # 3D mesh export/import for Scans tab
│   ├── PathFinder.swift             # Dijkstra waypoint routing
│   ├── ObstacleAwarePathfinder.swift # GKObstacleGraph mesh-based routing
│   ├── MeshObstacleExtractor.swift  # LiDAR mesh → polygon obstacles
│   └── HapticManager.swift          # CoreHaptics patterns
│
├── Models
│   ├── NavigationAnchor.swift       # Custom ARAnchor (destination/waypoint)
│   ├── MapZone.swift                # Zone model + ZoneStore
│   └── AppError.swift               # Typed errors with recovery
│
├── Rendering
│   └── PathRenderer.swift           # Animated chevrons with occlusion
│
└── Design
    └── DesignSystem.swift           # Colors, fonts, view modifiers
```

### Key Classes

**`ARManager`** — Manages the AR session lifecycle, LiDAR mesh tracking, and obstacle graph building. Configures scene depth for AR occlusion. Coordinates with `NavigationViewModel` for state updates.

**`NavigationViewModel`** — The central `@MainActor` observable state container. Handles mode transitions, zone management, relocalization timeout, and all published properties for SwiftUI binding.

**`ObstacleAwarePathfinder`** — Uses GameplayKit's `GKObstacleGraph` to route around physical obstacles detected by LiDAR. Falls back to waypoint-based Dijkstra when no mesh data is available.

**`MeshObstacleExtractor`** — Processes `ARMeshAnchor` data into an occupancy grid, extracts connected components, computes convex hulls, and creates `GKPolygonObstacle` instances for pathfinding.

**`PathRenderer`** — Renders the navigation path with three styles (chevrons, dots, dotted line). Supports animated wave effects, color gradients, and depth buffer reading for AR occlusion.

**`MeshDataStore`** — Exports LiDAR mesh data (vertices, normals, indices) to JSON for the 3D scan viewer. Reconstructs SceneKit geometry with height-based coloring.

**`ZoneStore`** — Singleton managing the zone manifest. Handles CRUD operations, automatic migration of legacy maps, and zone metadata persistence.

**`HapticManager`** — Singleton providing rich haptic feedback using both `UIFeedbackGenerator` and `CoreHaptics` for custom patterns (e.g., arrival celebration).

### Data Flow

```
User taps (SwiftUI)
      |
      v
ContentView (@StateObject sessionManager)
      |
      v
ARSessionManager (@Published state)
      |
      +--> ARSession (ARKit)
      |       |
      |       v
      |    ARSessionDelegate
      |       |-- didUpdate frame --> update tracking/mapping status
      |       |                   --> auto-drop waypoints (if enabled)
      |       |
      |       v
      |    @Published updates --> SwiftUI re-renders
      |
      +--> ARSCNView (SceneKit)
      |       |
      |       v
      |    ARSCNViewDelegate
      |       |-- nodeFor anchor    --> render destination/waypoint 3D markers
      |       |-- updateAtTime      --> PathFinder.findPath() --> renderPath()
      |
      +--> MapStore
      |       |-- save/load/list/delete world maps
      |
      +--> PathFinder
              |-- builds graph from anchors
              |-- Dijkstra shortest path
              |-- returns ordered [SIMD3<Float>] positions
```

---

## Technical Details

### AR Configuration & Occlusion

Both modes use `ARWorldTrackingConfiguration` with:
- **Plane detection:** horizontal and vertical
- **Environment texturing:** automatic
- **Scene reconstruction:** `.meshWithClassification` on LiDAR devices
- **Scene depth:** enabled for AR occlusion (`sceneDepth` frame semantics)
- **Person segmentation:** enabled for people occlusion (`personSegmentationWithDepth`)
- **Debug options:** feature points shown as yellow dots

**AR Occlusion** makes the navigation path render realistically behind real-world objects:
```swift
// ARManager configures depth semantics
if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
    config.frameSemantics.insert(.sceneDepth)
}

// PathRenderer materials read from depth buffer
material.readsFromDepthBuffer = true
material.writesToDepthBuffer = true
```

### Waypoints & Auto-Drop

Waypoints are lightweight `NavigationAnchor` instances with `kind = .waypoint`. They represent walkable positions along corridors.

**Auto-drop mode** monitors the camera position in `session(_:didUpdate:)`. When the device has moved >= 1.5 meters from the last waypoint, a new waypoint is dropped automatically. This creates a dense trail of walkable nodes along every corridor the admin walks.

**Manual drop** via the "+ WP" button allows placing waypoints at specific locations (corners, junctions, narrow passages).

Waypoints render as small semi-transparent yellow spheres (2.5cm radius) in AR space — visible to the admin during mapping but unobtrusive.

### Pathfinding (Obstacle-Aware)

The app uses a two-tier pathfinding system:

#### Tier 1: LiDAR Mesh-Based Routing (ObstacleAwarePathfinder)

On LiDAR-equipped devices, the app extracts physical obstacles from the mesh and routes around them:

1. **Mesh extraction:** `MeshObstacleExtractor` processes `ARMeshAnchor` data into an occupancy grid at floor level.
2. **Obstacle detection:** Connected components in the grid are identified as obstacles. Convex hulls are computed and expanded by a buffer radius.
3. **GKObstacleGraph:** GameplayKit's `GKObstacleGraph` builds a navigation mesh with `GKPolygonObstacle` instances.
4. **Path smoothing:** The resulting path is smoothed using Catmull-Rom interpolation for natural curves.

```swift
obstacleGraph = GKObstacleGraph(
    obstacles: obstacles,
    bufferRadius: 0.4  // 40cm buffer for human width
)
```

#### Tier 2: Waypoint-Based Dijkstra (Fallback)

When no mesh data is available, `PathFinder` uses the classic approach:

1. **Graph construction:** Every pair of anchors within 5 meters gets a bidirectional edge with Euclidean distance as the weight.
2. **Virtual start node:** The user's current camera position is added as a temporary node connected to nearby anchors.
3. **Dijkstra's algorithm:** Finds the shortest weighted path. O(n²) implementation, fast for hundreds of waypoints.
4. **Fallback:** If no graph path exists (disconnected waypoints), falls back to a straight line.

The result is an ordered array of 3D positions that the path renderer draws through.

### Map & Mesh Storage

Maps and mesh data are saved to the app's Documents directory:

```
<App Documents>/IndoorNavMaps/<map-name>.arexperience   # ARWorldMap
<App Documents>/MeshData/<zone-id>.json                  # 3D mesh for Scans tab
<App Documents>/zones.json                               # Zone manifest
```

**ARWorldMap files** contain:
- ARKit's visual feature point cloud
- Detected planes
- All `NavigationAnchor` instances (destinations and waypoints)
- Environment texture data

**Mesh data files** (JSON) contain:
- Vertex positions, normals, and triangle indices
- Transform matrices for each mesh chunk
- Bounding box information for visualization

**Zone manifest** tracks:
- Zone metadata (name, description, timestamps)
- Destination and waypoint counts
- References to map files

`MapStore` provides CRUD operations for world maps. `MeshDataStore` handles mesh export/import for the 3D viewer. `ZoneStore` manages the zone manifest with automatic migration of legacy maps.

### Custom Anchor Serialization

`NavigationAnchor` extends `ARAnchor` with `destinationName` (String) and `kind` (AnchorKind enum). Both properties are encoded via `NSSecureCoding`:

- `encode(with:)` calls `super.encode(with:)` then encodes both custom properties as `NSString`.
- `init?(coder:)` decodes both properties then calls `super.init(coder:)`.
- `init(anchor:)` copies properties from another anchor (ARKit's internal copy contract).

### Relocalization

When a world map is loaded with `initialWorldMap`:
1. Tracking starts as `.limited(.relocalizing)`.
2. ARKit matches live features against the saved map's feature cloud.
3. On match, tracking transitions to `.normal`.
4. The app detects this in `session(_:didUpdate:)` and sets `isRelocalized = true`.

Best results when the user is in the same area with similar lighting.

### Path Rendering

The path follows the Dijkstra-computed waypoint route:

1. **Segment walking:** The renderer walks along each path segment, placing dots at regular intervals (25cm apart).
2. **Color gradient:** Green-cyan near the user, blue-cyan near the destination.
3. **Arrow terminus:** The final dot uses a cone/arrow geometry.
4. **Update rate:** ~6-7 FPS (every 150ms in the SceneKit render loop).
5. **Distance:** Computed as the sum of all path segment lengths (walking distance, not straight-line).

---

## Troubleshooting

| Problem | Solution |
|---|---|
| "AR not available" | Must be a physical device with A9+ chip. Not supported in the Simulator. |
| World Map stays red/orange | Move slowly. Ensure visual texture and good lighting. |
| Save button disabled | World map status must reach Extending or Mapped. Keep walking. |
| Relocalization stuck on spinner | Must be in the same physical area with similar lighting. Point at distinctive features. |
| Path goes through walls | Not enough waypoints in that area. Re-map with auto-waypoints ON, walking through every corridor. |
| Path not found (straight line) | Waypoints may be disconnected (gap > 5m). Walk the connecting corridor to add waypoints, then re-save. |
| "No saved maps" error | Map the space first and save before switching to Navigate. |

---

## Limitations

- **LiDAR required for obstacle avoidance.** On non-LiDAR devices, paths follow waypoints only. Without sufficient waypoints, paths may take suboptimal routes.
- **Same-device only.** Maps are stored locally. Sharing between devices would require file export or a backend.
- **Lighting sensitivity.** Maps created in daylight may not relocalize well at night.
- **No floor-level clamping.** Path dots follow 3D waypoint positions, which may be at varying heights depending on how the admin held the device.
- **Single-floor per zone.** Each zone/map covers one contiguous area. Multi-floor navigation requires selecting different zones per floor.
- **Portrait orientation only.**

---

## License

This project is provided as-is for educational and prototyping purposes.
