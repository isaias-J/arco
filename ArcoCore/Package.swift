// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ArcoCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v14)
    ],
    products: [
        .library(name: "ArcoCore", targets: ["ArcoCore"])
    ],
    targets: [
        .target(
            name: "ArcoCore",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "ArcoCoreTests",
            dependencies: ["ArcoCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
