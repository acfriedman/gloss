// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "doclint",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "doclint", targets: ["doclint"]),
        .library(name: "DocLintCore", targets: ["DocLintCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "603.0.1")
    ],
    targets: [
        .target(name: "DocLintCore", dependencies: [
            .product(name: "SwiftSyntax", package: "swift-syntax"),
            .product(name: "SwiftParser", package: "swift-syntax")
        ]),
        .executableTarget(name: "doclint", dependencies: ["DocLintCore"]),
        .testTarget(name: "DocLintCoreTests", dependencies: ["DocLintCore"])
    ]
)
