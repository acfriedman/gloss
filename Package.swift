// swift-tools-version: 6.0
import PackageDescription

// Four layers, each depending only on the ones before it, so the compiler keeps them apart:
// GlossCore reads, models, and lints; GlossMap arranges the model for reading and lays out its maps;
// GlossPage renders that arrangement as HTML; GlossApp shows it in a native window.
let package = Package(
    name: "gloss",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "gloss", targets: ["gloss"]),
        .executable(name: "GlossApp", targets: ["GlossApp"]),
        .library(name: "GlossCore", targets: ["GlossCore"]),
        .library(name: "GlossMap", targets: ["GlossMap"]),
        .library(name: "GlossPage", targets: ["GlossPage"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "603.0.1")
    ],
    targets: [
        .target(name: "GlossCore", dependencies: [
            .product(name: "SwiftSyntax", package: "swift-syntax"),
            .product(name: "SwiftParser", package: "swift-syntax")
        ]),
        .target(name: "GlossMap", dependencies: [
            "GlossCore",
            .product(name: "SwiftSyntax", package: "swift-syntax"),
            .product(name: "SwiftParser", package: "swift-syntax"),
            .product(name: "SwiftIDEUtils", package: "swift-syntax")
        ]),
        .target(name: "GlossPage", dependencies: ["GlossCore", "GlossMap"]),
        .executableTarget(name: "gloss", dependencies: ["GlossCore", "GlossPage"]),
        .executableTarget(name: "GlossApp", dependencies: ["GlossCore", "GlossMap"]),
        .testTarget(name: "GlossCoreTests", dependencies: ["GlossCore", "GlossMap", "GlossPage"])
    ]
)
