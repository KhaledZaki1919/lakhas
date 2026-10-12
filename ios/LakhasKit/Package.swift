// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LakhasKit",
    defaultLocalization: "ar",
    // macOS is listed only so `swift test` can run the package tests on a Mac/CI host.
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "NutritionMath", targets: ["NutritionMath"]),
        .library(name: "LakhasKit", targets: ["LakhasKit"]),
    ],
    targets: [
        .target(name: "NutritionMath"),
        .target(name: "LakhasKit", dependencies: ["NutritionMath"]),
        .testTarget(name: "NutritionMathTests", dependencies: ["NutritionMath"]),
        .testTarget(name: "LakhasKitTests", dependencies: ["LakhasKit"], resources: [.copy("Fixtures")]),
    ]
)
