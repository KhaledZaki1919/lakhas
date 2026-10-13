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
        .target(name: "LakhasKit", dependencies: ["NutritionMath"], resources: [.process("Resources")]),
        .testTarget(name: "NutritionMathTests", dependencies: ["NutritionMath"]),
        .testTarget(name: "LakhasKitTests", dependencies: ["LakhasKit"]),
    ],
    // Swift 5 language mode, minimal concurrency checking (ADR-019).
    swiftLanguageModes: [.v5]
)
