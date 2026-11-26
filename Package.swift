// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Supurgec",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Supurgec",
            path: "Sources/Supurgec"
        )
    ]
)
