// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Notch",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/MrKai77/DynamicNotchKit", exact: "1.1.0")
    ],
    targets: [
        .executableTarget(
            name: "Notch",
            dependencies: [.product(name: "DynamicNotchKit", package: "DynamicNotchKit")],
            path: "Sources/Notch"
        ),
        .testTarget(
            name: "NotchTests",
            dependencies: ["Notch"],
            path: "Tests/NotchTests"
        )
    ]
)
