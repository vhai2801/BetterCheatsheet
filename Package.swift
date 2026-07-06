// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BetterCheatsheet",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "BetterCheatsheet",
            path: "Sources/BetterCheatsheet"
        )
    ]
)
