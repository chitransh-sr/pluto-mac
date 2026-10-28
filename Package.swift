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
        )
    ]
)
