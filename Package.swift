// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Ward",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .target(name: "WardCore"),
        .executableTarget(
            name: "Ward",
            dependencies: ["WardCore"]
        ),
        .testTarget(
            name: "WardCoreTests",
            dependencies: ["WardCore"]
        )
    ]
)
