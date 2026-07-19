// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CheKeynoteMCP",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.0")
    ],
    targets: [
        .executableTarget(
            name: "CheKeynoteMCP",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk")
            ],
            path: "Sources/CheKeynoteMCP",
            exclude: ["Info.plist", "Entitlements.plist"],
            linkerSettings: [
                // Embed Info.plist into the unbundled CLI binary so TCC can read
                // NSAppleEventsUsageDescription (che-ical-mcp proven pattern —
                // there is no .app bundle to carry it).
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/CheKeynoteMCP/Info.plist",
                ])
            ]
        ),
        .testTarget(
            name: "CheKeynoteMCPTests",
            dependencies: ["CheKeynoteMCP"],
            path: "Tests/CheKeynoteMCPTests"
        ),
    ]
)
