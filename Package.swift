// swift-tools-version:5.9
//
// This package is a *test harness only*. The iOS app is built from
// `Sidestreet.xcodeproj`. The package compiles the platform-independent
// discovery core (`Sidestreet/Core`, Foundation only) so that its unit tests
// can run with `swift test` on macOS or Linux, without Xcode or a simulator.
//
// Open `Sidestreet.xcodeproj` in Xcode to build the app.

import PackageDescription

let package = Package(
    name: "SidestreetCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [
        .library(name: "SidestreetCore", targets: ["SidestreetCore"]),
    ],
    targets: [
        .target(
            name: "SidestreetCore",
            path: "Sidestreet/Core",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "SidestreetTests",
            dependencies: ["SidestreetCore"],
            path: "SidestreetTests",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
    ]
)
