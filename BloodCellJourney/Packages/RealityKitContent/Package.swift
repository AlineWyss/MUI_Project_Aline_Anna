// swift-tools-version:6.0
// Reality Composer Pro content package for Blood Cell Journey.
// Open Package.realitycomposerpro in Reality Composer Pro to edit the models and materials.

import PackageDescription

let package = Package(
    name: "RealityKitContent",
    platforms: [
        .visionOS(.v2),
        .macOS(.v15),
        .iOS(.v18)
    ],
    products: [
        .library(
            name: "RealityKitContent",
            targets: ["RealityKitContent"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "RealityKitContent",
            dependencies: []),
    ]
)
