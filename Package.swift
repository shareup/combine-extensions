// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "CombineExtensions",
    platforms: [
        .macOS(.v11), .iOS(.v14), .tvOS(.v14), .watchOS(.v7),
    ],
    products: [
        .library(
            name: "CombineExtensions",
            targets: ["CombineExtensions"]
        ),
        .library(
            name: "CombineTestExtensions",
            type: .dynamic,
            targets: ["CombineTestExtensions"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/shareup/synchronized.git",
            from: "4.0.0"
        ),
    ],
    targets: [
        .target(
            name: "CombineExtensions",
            dependencies: [
                .product(
                    name: "Synchronized",
                    package: "synchronized"
                ),
            ]
        ),
        .target(
            name: "CombineTestExtensions",
            cSettings: [
                .define("APPLICATION_EXTENSION_API_ONLY", to: "YES"),
            ]
        ),
        .testTarget(
            name: "CombineExtensionsTests",
            dependencies: ["CombineExtensions", "CombineTestExtensions"]
        ),
    ]
)
