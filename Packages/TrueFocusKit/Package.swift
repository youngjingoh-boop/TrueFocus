// swift-tools-version:5.9
//
// TrueFocusKit — the platform-free brain of TrueFocus.
// Foundation only, so it builds and tests on macOS, iOS, every app extension,
// and on Linux CI. Everything that can be a pure function lives here.

import PackageDescription

let package = Package(
    name: "TrueFocusKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "TrueFocusKit", targets: ["TrueFocusKit"]),
    ],
    targets: [
        .target(name: "TrueFocusKit"),
        .testTarget(name: "TrueFocusKitTests", dependencies: ["TrueFocusKit"]),
    ],
    swiftLanguageVersions: [.v5]
)
