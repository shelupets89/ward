// swift-tools-version: 5.9
import PackageDescription

/// One library target per feature, all depending on WardKit and none on each
/// other. `Ward` is a thin shell that owns the status item and nothing else —
/// adding a feature means adding a target here and one line in the shell.
///
/// Everything except the executable is a library, so every line is reachable
/// from tests. Feature code lives next to its own tests under Features/<Name>/.
let package = Package(
    name: "Ward",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .target(name: "WardKit"),
        .testTarget(name: "WardKitTests", dependencies: ["WardKit"]),

        .target(
            name: "CleaningMode",
            dependencies: ["WardKit"],
            path: "Features/CleaningMode/Sources"
        ),
        .testTarget(
            name: "CleaningModeTests",
            dependencies: ["CleaningMode"],
            path: "Features/CleaningMode/Tests"
        ),

        .target(
            name: "KeepAwakeLidClosed",
            dependencies: ["WardKit"],
            path: "Features/KeepAwakeLidClosed/Sources"
        ),
        .testTarget(
            name: "KeepAwakeLidClosedTests",
            dependencies: ["KeepAwakeLidClosed"],
            path: "Features/KeepAwakeLidClosed/Tests"
        ),

        .executableTarget(
            name: "Ward",
            dependencies: ["WardKit", "CleaningMode", "KeepAwakeLidClosed"]
        )
    ]
)
