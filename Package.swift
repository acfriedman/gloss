// swift-tools-version: 6.0
import PackageDescription

// Layers, each depending only on the ones before it, so the compiler keeps them apart. SwiftLucid's
// LucidRead parses the sources once, into declarations and their doc comments, and its LucidLint checks
// those docs against the house style; here, GlossModel reads them as contracts and a graph, never
// knowing the lint; GlossMap arranges the model for reading, with the lint's findings beside it, and lays
// out its maps; GlossPage renders that arrangement as HTML; GlossApp shows it in a native window.
let package = Package(
    name: "gloss",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "gloss", targets: ["gloss"]),
        .executable(name: "GlossApp", targets: ["GlossApp"]),
        .library(name: "GlossModel", targets: ["GlossModel"]),
        .library(name: "GlossMap", targets: ["GlossMap"]),
        .library(name: "GlossPage", targets: ["GlossPage"])
    ],
    dependencies: [
        .package(url: "https://github.com/acfriedman/SwiftLucid.git", from: "0.1.0"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "603.0.1")
    ],
    targets: [
        // Each module's README is its page, which the lint reads and the build leaves out.
        .target(name: "GlossModel", dependencies: [
            .product(name: "LucidRead", package: "SwiftLucid")
        ], exclude: ["README.md"]),
        .target(name: "GlossMap", dependencies: [
            .product(name: "LucidRead", package: "SwiftLucid"),
            .product(name: "LucidLint", package: "SwiftLucid"),
            "GlossModel",
            .product(name: "SwiftSyntax", package: "swift-syntax"),
            .product(name: "SwiftParser", package: "swift-syntax"),
            .product(name: "SwiftIDEUtils", package: "swift-syntax")
        ], exclude: ["README.md"]),
        .target(name: "GlossPage", dependencies: [
            .product(name: "LucidRead", package: "SwiftLucid"),
            .product(name: "LucidLint", package: "SwiftLucid"),
            "GlossModel",
            "GlossMap"
        ], exclude: ["README.md"]),
        .executableTarget(name: "gloss", dependencies: [
            .product(name: "LucidRead", package: "SwiftLucid"),
            .product(name: "LucidLint", package: "SwiftLucid"),
            "GlossModel",
            "GlossMap",
            "GlossPage"
        ], exclude: ["README.md"]),
        .executableTarget(name: "GlossApp", dependencies: [
            .product(name: "LucidRead", package: "SwiftLucid"),
            .product(name: "LucidLint", package: "SwiftLucid"),
            "GlossModel",
            "GlossMap"
        ], exclude: ["README.md"]),
        .testTarget(name: "GlossTests", dependencies: [
            .product(name: "LucidRead", package: "SwiftLucid"),
            .product(name: "LucidLint", package: "SwiftLucid"),
            "GlossModel",
            "GlossMap",
            "GlossPage"
        ])
    ]
)
