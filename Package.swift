// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StickyNote",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "StickyNote",
            path: "Sources"
        )
    ]
)
