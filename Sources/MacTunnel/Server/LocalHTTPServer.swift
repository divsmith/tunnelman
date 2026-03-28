import Foundation
import Network
import os

/// A simple HTTP server that:
/// - Serves the bundled terminal.html at GET /terminal
/// - Upgrades WebSocket connections at /ws?token=<token>
final class LocalHTTPServer {
    private let token: String
    private let requiresExternalAuth: Bool
    private weak var ptyManager: PTYManager?
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: WebSocketConnection] = [:]
    private let queue = DispatchQueue(label: "mactunnel.server")
    private static let log = Logger(subsystem: "mactunnel", category: "server")

    /// - Parameter requiresExternalAuth: When `true` (DevTunnel mode), the tunnel provider
    ///   already gates access with GitHub/Microsoft auth, so any request reaching this server
    ///   comes from an authenticated user. Unknown paths are redirected to the terminal instead
    ///   of returning 404, which recovers gracefully from post-auth redirects that drop the
    ///   original path.
    init(token: String, ptyManager: PTYManager, requiresExternalAuth: Bool = false) {
        self.token = token
        self.requiresExternalAuth = requiresExternalAuth
        self.ptyManager = ptyManager

        // Broadcast PTY output to all connected WebSocket clients
        ptyManager.onData = { [weak self] data in
            self?.broadcast(data)
        }
    }

    /// Starts the server on a random available port; returns the resolved port.
    func start() throws -> UInt16 {
        let params = NWParameters.tcp
        let listener = try NWListener(using: params, on: .any)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener.start(queue: queue)

        // Wait briefly for the listener to resolve its port
        var resolved: UInt16 = 0
        let sem = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            if case .ready = state {
                resolved = listener.port?.rawValue ?? 0
                sem.signal()
            } else if case .failed = state {
                sem.signal()
            }
        }
        sem.wait()

        guard resolved > 0 else {
            throw ServerError.portUnavailable
        }
        return resolved
    }

    func stop() {
        listener?.cancel()
        listener = nil
        connections.values.forEach { $0.cancel() }
        connections.removeAll()
    }

    private func handleConnection(_ nwConn: NWConnection) {
        // Read the first HTTP request to decide: plain HTTP or WebSocket upgrade
        let conn = HTTPConnection(nwConnection: nwConn, token: token, ptyManager: ptyManager, requiresExternalAuth: requiresExternalAuth) { [weak self] ws in
            guard let self else { return }
            let id = ObjectIdentifier(ws)
            self.connections[id] = ws
            ws.onClose = { [weak self] in self?.connections.removeValue(forKey: id) }
        }
        conn.start(on: queue)
    }

    private func broadcast(_ data: Data) {
        connections.values.forEach { $0.send(data) }
    }
}

enum ServerError: LocalizedError {
    case portUnavailable
    var errorDescription: String? { "Could not bind to a local port." }
}
