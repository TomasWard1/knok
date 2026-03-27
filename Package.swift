// swift-tools-version:6.0

import PackageDescription

let package = Package(
    name: "Knok",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "KnokCore", targets: ["KnokCore"]),
        .executable(name: "knok-cli", targets: ["KnokCLI"]),
        .executable(name: "knok-mcp", targets: ["KnokMCP"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.9.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", "2.6.4"..<"2.7.0"),
    ],
    targets: [
        // Shared library — models, protocol, socket client, constants
        .target(
            name: "KnokCore",
            dependencies: []
        ),
        // Menu bar app
        .executableTarget(
            name: "KnokApp",
            dependencies: [
                "KnokCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            exclude: ["Info.plist"],
            resources: [
                .process("Assets.xcassets"),
                .process("Resources/app.getknok.Knok.plist"),
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", "Sources/KnokApp/Info.plist"]),
            ]
        ),
        // CLI tool
        .executableTarget(
            name: "KnokCLI",
            dependencies: [
                "KnokCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        // MCP stdio server
        .executableTarget(
            name: "KnokMCP",
            dependencies: [
                "KnokCore",
                .product(name: "MCP", package: "swift-sdk"),
            ]
        ),
        // Tests
        .testTarget(
            name: "KnokCoreTests",
            dependencies: ["KnokCore"]
        ),
    ]
)
