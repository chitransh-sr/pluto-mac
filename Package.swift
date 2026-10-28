// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PlutoMac",
    targets: [
        .executableTarget(
            name: "PlutoMac",
            path: "Sources/PlutoMac",
            swiftSettings: [
                .unsafeFlags(["-swift-version", "5"])
            ]
        ),
        .testTarget(
            name: "PlutoMacTests",
            dependencies: ["PlutoMac"],
            path: "Tests/PlutoMacTests",
            swiftSettings: [
                .unsafeFlags(["-swift-version", "5"])
            ]
        )
    ]
)
