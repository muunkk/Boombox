// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Kaset",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .executable(
            name: "YTMPrivate",
            targets: ["Kaset"]
        ),
    ],
    dependencies: [],
    targets: [
        // Main app executable
        .executableTarget(
            name: "Kaset",
            dependencies: [],
            resources: [
                .process("Resources"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        // Unit tests
        .testTarget(
            name: "KasetTests",
            dependencies: ["Kaset"],
            resources: [
                .process("Fixtures"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
