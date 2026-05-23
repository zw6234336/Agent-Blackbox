// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AgentBlackbox",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "AgentBlackbox",
            path: "Sources/AgentBlackbox",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
