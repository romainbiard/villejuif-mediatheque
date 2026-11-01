// swift-tools-version: 6.2
// Ma médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import PackageDescription

let dependencies: Target.Dependency = .product(name: "Dependencies", package: "swift-dependencies")

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
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "SearchFeature", targets: ["SearchFeature"]),
        .library(name: "AgendaFeature", targets: ["AgendaFeature"]),
        .library(name: "InfoFeature", targets: ["InfoFeature"]),
        .library(name: "AccountFeature", targets: ["AccountFeature"]),
        .library(name: "DigitalFeature", targets: ["DigitalFeature"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.17.0"),
        .package(url: "https://github.com/pointfreeco/swift-clocks", from: "1.0.0"),
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
                dependencies,
                .product(name: "DependenciesMacros", package: "swift-dependencies"),
            ],
            resources: [.process("Localization/Localizable.xcstrings")]
        ),
        .target(name: "DesignSystem", resources: [.process("Resources"), .process("Localization/Localizable.xcstrings")]),
        .target(name: "SearchFeature", dependencies: ["MediathequeCore", "DesignSystem", dependencies], resources: [.process("Localization/Localizable.xcstrings")]),
        .target(name: "AgendaFeature", dependencies: ["MediathequeCore", "DesignSystem", dependencies], resources: [.process("Localization/Localizable.xcstrings")]),
        .target(name: "InfoFeature", dependencies: ["MediathequeCore", "DesignSystem", dependencies], resources: [.process("Localization/Localizable.xcstrings")]),
        .target(name: "AccountFeature", dependencies: ["MediathequeCore", "DesignSystem", "SearchFeature", dependencies], resources: [.process("Localization/Localizable.xcstrings")]),
        .target(name: "DigitalFeature", dependencies: ["MediathequeCore", "DesignSystem", dependencies], resources: [.process("Localization/Localizable.xcstrings")]),
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
        .testTarget(
            name: "FeatureTests",
            dependencies: [
                "SearchFeature",
                "AgendaFeature",
                "InfoFeature",
                "AccountFeature",
                "DigitalFeature",
                .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
                .product(name: "Clocks", package: "swift-clocks"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
