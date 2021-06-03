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
        .library(
            name: "CombineTestExtensions",
            type: .dynamic,
            targets: ["CombineTestExtensions"])],
    dependencies: [
        .package(
            name: "Synchronized",
            url: "https://github.com/shareup/synchronized.git",
            from: "3.0.0")],
    targets: [
        .target(
            name: "CombineExtensions",
            dependencies: ["Synchronized"]),
        .target(
            name: "CombineTestExtensions",
            dependencies: []),
        .testTarget(
            name: "CombineExtensionsTests",
            dependencies: ["CombineExtensions", "CombineTestExtensions"])]
)
