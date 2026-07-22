// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EpycZones",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "EpycZones",
            path: "Sources/EpycZones",
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
            ]
        )
    ]
)
