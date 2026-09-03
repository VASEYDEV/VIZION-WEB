// swift-tools-version: 6.0
// VizionCore — the platform-agnostic half of VIZION: the model roster, the six
// modes, the wire contracts, the diff, library helpers, and every pure function
// the SwiftUI app renders from. No UIKit, no SwiftUI, no network — so it builds
// and tests on Linux (CI) as well as inside Xcode.
import PackageDescription

let package = Package(
  name: "VizionCore",
  platforms: [.iOS(.v18), .macOS(.v14)],
  products: [
    .library(name: "VizionCore", targets: ["VizionCore"]),
  ],
  targets: [
    .target(
      name: "VizionCore",
      swiftSettings: [
        .enableUpcomingFeature("ExistentialAny"),
      ]
    ),
    .testTarget(
      name: "VizionCoreTests",
      dependencies: ["VizionCore"]
    ),
  ],
  swiftLanguageModes: [.v6]
)
