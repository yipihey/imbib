// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "PublicationManagerCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "PublicationManagerCore",
            targets: ["PublicationManagerCore"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/evgenyneu/keychain-swift", from: "20.0.0")
    ],
    targets: [
        .target(
            name: "PublicationManagerCore",
            dependencies: [
                .product(name: "KeychainSwift", package: "keychain-swift")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "PublicationManagerCoreTests",
            dependencies: ["PublicationManagerCore"],
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
)
