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
        .executableTarget(
            name: "MacTunnel",
            dependencies: ["MacTunnelHelper"],
            path: "Sources/MacTunnel",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
