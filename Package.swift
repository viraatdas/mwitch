// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "mwitch",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "mwitch",
            path: "Sources/mwitch",
            swiftSettings: [
                .unsafeFlags(["-O", "-whole-module-optimization"], .when(configuration: .release))
            ]
        )
    ]
)
