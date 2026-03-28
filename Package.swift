// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacTunnel",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "MacTunnelHelper",
            path: "Sources/MacTunnelHelper",
            publicHeadersPath: "include"
        ),
        // Pure-logic library: no AppKit/SwiftUI, no OS I/O — fully testable
        .target(
            name: "MacTunnelCore",
            path: "Sources/MacTunnelCore"
        ),
        .executableTarget(
            name: "MacTunnel",
            dependencies: ["MacTunnelHelper", "MacTunnelCore"],
            path: "Sources/MacTunnel",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "MacTunnelTests",
            dependencies: ["MacTunnelCore"],
            path: "Tests/MacTunnelTests"
        )
    ]
)
