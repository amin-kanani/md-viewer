// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MDViewer",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "MDViewer"
        )
    ]
)
