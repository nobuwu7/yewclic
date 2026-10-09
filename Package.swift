// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Yewclic",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Yewclic",
            path: "Sources/Yewclic"
        )
    ]
)
