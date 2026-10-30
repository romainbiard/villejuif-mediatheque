// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Mediatheque",
    defaultLocalization: "fr",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "BokehAPI", targets: ["BokehAPI"]),
        .library(name: "MediathequeCore", targets: ["MediathequeCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.17.0"),
        .package(url: "https://github.com/scinfu/SwiftSoup", from: "2.14.0"),
    ],
    targets: [
        .target(
            name: "BokehAPI",
            dependencies: [
                .product(name: "SwiftSoup", package: "SwiftSoup"),
            ]
        ),
        .target(
            name: "MediathequeCore",
            dependencies: [
                "BokehAPI",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesMacros", package: "swift-dependencies"),
            ]
        ),
        .testTarget(
            name: "BokehAPITests",
            dependencies: ["BokehAPI"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "MediathequeCoreTests",
            dependencies: [
                "BokehAPI",
                "MediathequeCore",
                .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
