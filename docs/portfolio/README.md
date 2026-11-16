# IndoorNav app captures

The actual ScansTabView and SceneKit ScanViewer3D running in an iPhone simulator. A clearly named Sample room mesh fixture is loaded into the app’s normal mesh store. This is a sample 3D mesh, not a scan made with LiDAR. Live AR mapping, navigation, and LiDAR capture require a physical compatible device.

Captured by XCTest from the running SwiftUI application on an iPhone simulator. The screenshot files are format-converted WebP exports, with no recreated UI.

Source revision: 0df48c0cfbf16bbaa50602272a5cba4b588319f1.

[Capture workflow and build log](https://github.com/davincuaso/IndoorNav/actions/runs/43896106879). The build-only fixture setup and UI capture tests are versioned on IndoorNav’s portfolio-native-captures branch under docs/portfolio/capture-support/prepare.py. App views and renderers are retained from the source; fixtures only supply sample model data or select the Scans tab. IndoorNav’s legacy files are excluded to match its Xcode target.

- [3D viewer · simulator, sample mesh](screens/capture-01.webp)
- [Scan library · simulator, sample room](screens/capture-02.webp)
