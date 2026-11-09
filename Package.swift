// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Mantel",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Mantel",
            path: "Sources/Mantel"
        ),
        .testTarget(
            name: "MantelTests",
            dependencies: ["Mantel"],
            path: "Tests/MantelTests"
        )
    ]
)
