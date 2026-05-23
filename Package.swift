// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Agent-Blackbox",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.14.1")
    ],
    targets: [
        .executableTarget(
            name: "Agent-Blackbox",
            dependencies: [
                .product(name: "SQLite", package: "SQLite.swift")
            ],
            path: "Agent-Blackbox",
            exclude: [
                "Info.plist"
            ],
            resources: [
                .process("Resources")
            ]
        )
    ]
)
