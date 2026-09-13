// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "gloss",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "gloss", targets: ["gloss"]),
        .library(name: "GlossCore", targets: ["GlossCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "603.0.1")
    ],
    targets: [
        .target(name: "GlossCore", dependencies: [
            .product(name: "SwiftSyntax", package: "swift-syntax"),
            .product(name: "SwiftParser", package: "swift-syntax")
        ]),
        .executableTarget(name: "gloss", dependencies: ["GlossCore"]),
        .testTarget(name: "GlossCoreTests", dependencies: ["GlossCore"])
    ]
)
