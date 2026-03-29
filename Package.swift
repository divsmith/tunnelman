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
        // Server, terminal, tunnel logic — no AppKit/SwiftUI, fully testable
        .target(
            name: "MacTunnelServer",
            dependencies: ["MacTunnelHelper", "MacTunnelCore"],
            path: "Sources/MacTunnelServer",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "MacTunnel",
            dependencies: ["MacTunnelServer"],
            path: "Sources/MacTunnel"
        ),
        .testTarget(
            name: "MacTunnelTests",
            dependencies: ["MacTunnelCore", "MacTunnelServer"],
            path: "Tests/MacTunnelTests"
        )
    ]
)
