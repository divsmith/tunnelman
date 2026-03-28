import Foundation
import Combine

enum TunnelState: Equatable {
    case idle
    case starting
    case connected(url: URL)
    case error(message: String)
}

enum TunnelMode: String, CaseIterable, Identifiable {
    case local = "Local Network"
    case devtunnel = "Microsoft DevTunnel"
    case cloudflare = "Cloudflare Tunnel"

    var id: String { rawValue }
}

/// Central coordinator: owns the PTY, HTTP server, WebSocket handler, and tunnel provider.
@MainActor
final class SessionManager: ObservableObject {
    @Published var tunnelState: TunnelState = .idle
    @Published var tunnelMode: TunnelMode = .local
    @Published var sessionURL: URL?

    private(set) var sessionToken: String = ""
    private var httpServer: LocalHTTPServer?
    private var ptyManager: PTYManager?
    private var tunnelProvider: TunnelProvider?
    private var cancellables = Set<AnyCancellable>()

    let port: UInt16 = 0 // 0 = pick random available port; resolved at runtime
    private(set) var resolvedPort: UInt16 = 0

    func startSession() {
        guard case .idle = tunnelState else { return }
        tunnelState = .starting
        sessionToken = UUID().uuidString.replacingOccurrences(of: "-", with: "")

        Task {
            do {
                // Start PTY
                let pty = PTYManager()
                try pty.start()
                self.ptyManager = pty

                // Start HTTP + WebSocket server
                let server = LocalHTTPServer(token: sessionToken, ptyManager: pty)
                let resolvedPort = try server.start()
                self.resolvedPort = resolvedPort
                self.httpServer = server

                // Start tunnel provider
                let provider = makeTunnelProvider(port: resolvedPort)
                self.tunnelProvider = provider

                provider.urlPublisher
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] url in
                        guard let self else { return }
                        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
                        components.path = "/terminal"
                        components.queryItems = [URLQueryItem(name: "token", value: self.sessionToken)]
                        self.sessionURL = components.url
                        self.tunnelState = .connected(url: url)
                    }
                    .store(in: &cancellables)

                provider.errorPublisher
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] message in
                        self?.tunnelState = .error(message: message)
                    }
                    .store(in: &cancellables)

                try provider.start()
            } catch {
                tunnelState = .error(message: error.localizedDescription)
            }
        }
    }

    func stopSession() {
        tunnelProvider?.stop()
        httpServer?.stop()
        ptyManager?.stop()
        tunnelProvider = nil
        httpServer = nil
        ptyManager = nil
        sessionURL = nil
        cancellables.removeAll()
        tunnelState = .idle
    }

    private func makeTunnelProvider(port: UInt16) -> TunnelProvider {
        switch tunnelMode {
        case .local:      return LocalProvider(port: port)
        case .devtunnel:  return DevTunnelProvider(port: port)
        case .cloudflare: return CloudflaredProvider(port: port)
        }
    }
}
