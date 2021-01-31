// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "CombineExtensions",
    platforms: [
        .macOS(.v10_15), .iOS(.v13), .tvOS(.v13), .watchOS(.v5),
    ],
    products: [
        .library(
            name: "CombineExtensions",
            targets: ["CombineExtensions"]),
    ],
    dependencies: [
        .package(
            name: "Synchronized",
            url: "https://github.com/shareup/synchronized.git",
            from: "2.1.0"
        )
    ],
    targets: [
        .target(
            name: "CombineExtensions",
            dependencies: ["Synchronized"]),
        .testTarget(
            name: "CombineExtensionsTests",
            dependencies: ["CombineExtensions"]),
    ]
)
