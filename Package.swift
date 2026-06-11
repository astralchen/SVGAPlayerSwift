// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SVGAView",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "SVGAView",
            targets: ["SVGAView"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.0.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.0")
    ],
    targets: [
        .target(
            name: "SVGAView",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
            ],
            path: "Sources/SVGAView",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ],
            linkerSettings: [
                .linkedLibrary("z")
            ],
            plugins: [
                .plugin(name: "SwiftProtobufPlugin", package: "swift-protobuf")
            ]
        ),
        .testTarget(
            name: "SVGAViewTests",
            dependencies: ["SVGAView"],
            path: "Tests/SVGAViewTests",
            resources: [
                .copy("Resources/banner.svga"),
                .copy("Resources/bubble.svga")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
