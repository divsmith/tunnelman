import Foundation
import Combine

public enum TunnelState: Equatable {
    case idle
    case starting
    case connected(url: URL)
    case error(message: String)
    case needsDevTunnelLogin
}

public enum TunnelMode: String, CaseIterable, Identifiable {
    case local = "Local Network"
    case devtunnel = "Microsoft DevTunnel"
    case cloudflare = "Cloudflare Tunnel"

    public var id: String { rawValue }
}

/// Central coordinator: owns the PTY, HTTP server, WebSocket handler, and tunnel provider.
@MainActor
public final class SessionManager: ObservableObject {
    @Published public var tunnelState: TunnelState = .idle
    @Published public var tunnelMode: TunnelMode = .local
    @Published public var sessionURL: URL?

    public private(set) var sessionToken: String = ""
    private var httpServer: LocalHTTPServer?
    private var ptyManager: PTYManager?
    private var tunnelProvider: TunnelProvider?
    private var loginProcess: Process?
    private var cancellables = Set<AnyCancellable>()

    public let port: UInt16 = 0
    public private(set) var resolvedPort: UInt16 = 0

    public init() {}

    public func startSession() {
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
                let server = LocalHTTPServer(token: sessionToken, ptyManager: pty, requiresExternalAuth: tunnelMode == .devtunnel)
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
                        guard let self else { return }
                        if message == "DEVTUNNEL_NOT_LOGGED_IN" {
                            // Clean up the failed session; user needs to log in first
                            self.tunnelProvider = nil
                            self.httpServer?.stop(); self.httpServer = nil
                            self.ptyManager?.stop(); self.ptyManager = nil
                            self.sessionURL = nil
                            self.tunnelState = .needsDevTunnelLogin
                        } else {
                            self.tunnelState = .error(message: message)
                        }
                    }
                    .store(in: &cancellables)

                try provider.start()
            } catch {
                tunnelState = .error(message: error.localizedDescription)
            }
        }
    }

    /// Launches `devtunnel user login` (or `-g` for GitHub) in a subprocess,
    /// shows the spinner while the browser OAuth flow runs, then returns to idle.
    public func loginWithDevTunnel(github: Bool) {
        guard let devtunnelPath = findExecutable("devtunnel") else {
            tunnelState = .error(message: "devtunnel not found. Install with: brew install --cask devtunnel")
            return
        }
        tunnelState = .starting

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: devtunnelPath)
        proc.arguments = github ? ["user", "login", "-g"] : ["user", "login"]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice

        proc.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.loginProcess = nil
                self?.tunnelState = .idle
            }
        }

        do {
            try proc.run()
            loginProcess = proc
        } catch {
            tunnelState = .error(message: "Could not launch devtunnel: \(error.localizedDescription)")
        }
    }

    public func stopSession() {
        loginProcess?.terminate()
        loginProcess = nil
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
