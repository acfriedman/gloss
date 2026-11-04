// swift-tools-version: 6.0
import PackageDescription

// Layers, each depending only on the ones before it, so the compiler keeps them apart:
// GlossRead parses the sources once, into declarations and their doc comments; GlossLint checks those
// docs against the house style, and GlossModel reads them as contracts and a graph, neither knowing the
// other; GlossMap arranges the model for reading, with the lint's findings beside it, and lays out its
// maps; GlossPage renders that arrangement as HTML; GlossApp shows it in a native window.
let package = Package(
    name: "gloss",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "gloss", targets: ["gloss"]),
        .executable(name: "GlossApp", targets: ["GlossApp"]),
        .library(name: "GlossRead", targets: ["GlossRead"]),
        .library(name: "GlossLint", targets: ["GlossLint"]),
        .library(name: "GlossModel", targets: ["GlossModel"]),
        .library(name: "GlossMap", targets: ["GlossMap"]),
        .library(name: "GlossPage", targets: ["GlossPage"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "603.0.1")
    ],
    targets: [
        .target(name: "GlossRead", dependencies: [
            .product(name: "SwiftSyntax", package: "swift-syntax"),
            .product(name: "SwiftParser", package: "swift-syntax")
        ]),
        .target(name: "GlossLint", dependencies: ["GlossRead"]),
        .target(name: "GlossModel", dependencies: ["GlossRead"]),
        .target(name: "GlossMap", dependencies: [
            "GlossRead",
            "GlossLint",
            "GlossModel",
            .product(name: "SwiftSyntax", package: "swift-syntax"),
            .product(name: "SwiftParser", package: "swift-syntax"),
            .product(name: "SwiftIDEUtils", package: "swift-syntax")
        ]),
        .target(name: "GlossPage", dependencies: ["GlossRead", "GlossLint", "GlossModel", "GlossMap"]),
        .executableTarget(name: "gloss", dependencies: ["GlossRead", "GlossLint", "GlossModel", "GlossMap", "GlossPage"]),
        .executableTarget(name: "GlossApp", dependencies: ["GlossRead", "GlossLint", "GlossModel", "GlossMap"]),
        .testTarget(name: "GlossTests", dependencies: ["GlossRead", "GlossLint", "GlossModel", "GlossMap", "GlossPage"])
    ]
)
