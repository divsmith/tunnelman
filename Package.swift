// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TunnelMan",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "TunnelManHelper",
            path: "Sources/TunnelManHelper",
            publicHeadersPath: "include"
        ),
        // Pure-logic library: no AppKit/SwiftUI, no OS I/O — fully testable
        .target(
            name: "TunnelManCore",
            path: "Sources/TunnelManCore"
        ),
        // Server, terminal, tunnel logic — no AppKit/SwiftUI, fully testable
        .target(
            name: "TunnelManServer",
            dependencies: ["TunnelManHelper", "TunnelManCore"],
            path: "Sources/TunnelManServer",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "TunnelMan",
            dependencies: ["TunnelManServer"],
            path: "Sources/TunnelMan"
        ),
        .testTarget(
            name: "TunnelManTests",
            dependencies: ["TunnelManCore", "TunnelManServer"],
            path: "Tests/TunnelManTests"
        )
    ]
)
