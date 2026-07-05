// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Jot",
    platforms: [
        .macOS("26.0")
    ],
    targets: [
        .executableTarget(
            name: "Jot",
            path: "Sources"
        )
    ]
)
