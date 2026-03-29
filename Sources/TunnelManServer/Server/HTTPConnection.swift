import Foundation
import Network
import TunnelManCore
import os

private let log = Logger(subsystem: "tunnelman", category: "http")

/// Handles a single incoming TCP connection: parses HTTP request and routes it.
final class HTTPConnection {
    private let nwConnection: NWConnection
    private let token: String
    private let requiresExternalAuth: Bool
    private weak var ptyManager: PTYManager?
    private let onWebSocketUpgrade: (WebSocketConnection) -> Void
    private var buffer = Data()

    init(
        nwConnection: NWConnection,
        token: String,
        ptyManager: PTYManager?,
        requiresExternalAuth: Bool = false,
        onWebSocketUpgrade: @escaping (WebSocketConnection) -> Void
    ) {
        self.nwConnection = nwConnection
        self.token = token
        self.requiresExternalAuth = requiresExternalAuth
        self.ptyManager = ptyManager
        self.onWebSocketUpgrade = onWebSocketUpgrade
    }

    func start(on queue: DispatchQueue) {
        nwConnection.start(queue: queue)
        receiveHTTPRequest()
    }

    private func receiveHTTPRequest() {
        nwConnection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [self] data, _, isComplete, error in
            if let data { self.buffer.append(data) }

            // Wait until we have the full HTTP header (ends with \r\n\r\n)
            if let headerEnd = self.buffer.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = self.buffer[..<headerEnd.lowerBound]
                guard let headerStr = String(data: headerData, encoding: .utf8) else {
                    self.sendBadRequest(); return
                }
                self.routeRequest(headerStr)
            } else if isComplete {
                self.sendBadRequest()
            } else if error == nil {
                self.receiveHTTPRequest()
            }
        }
    }

    private func routeRequest(_ header: String) {
        let lines = header.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { sendBadRequest(); return }
        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else { sendBadRequest(); return }

        let path = parts[1]

        // Check for WebSocket upgrade
        let isUpgrade = lines.contains { $0.lowercased().hasPrefix("upgrade: websocket") }

        if isUpgrade && path.hasPrefix("/ws") {
            // Validate token from query string
            guard extractToken(from: path) == token else {
                send401(); return
            }
            // Hand off to WebSocket handler
            let wsConn = WebSocketConnection(nwConnection: nwConnection, ptyManager: ptyManager, httpHeader: header)
            wsConn.performHandshake(originalHeader: header) { [self] in
                self.onWebSocketUpgrade(wsConn)
            }
        } else if path == "/" || path == "/terminal" || path.hasPrefix("/terminal?") {
            // Validate token
            guard extractToken(from: path) == token else {
                // After devtunnel GitHub auth the browser may land on / with no token; redirect to terminal.
                if requiresExternalAuth { sendRedirect(to: "/terminal?token=\(token)"); return }
                send401(); return
            }
            serveTerminalHTML()
        } else {
            // After devtunnel auth the redirect may land on an unrecognised path; send the user to the terminal.
            if requiresExternalAuth { sendRedirect(to: "/terminal?token=\(token)"); return }
            send404()
        }
    }

    private func extractToken(from path: String) -> String? {
        extractSessionToken(from: path)
    }

    private func serveTerminalHTML() {
        guard let htmlURL = Bundle.module.url(forResource: "terminal", withExtension: "html"),
              let html = try? Data(contentsOf: htmlURL) else {
            send500(); return
        }
        let header = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.count)\r\nConnection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(html)
        nwConnection.send(content: response, completion: .contentProcessed { [self] _ in
            self.nwConnection.cancel()
        })
    }

    private func sendRedirect(to location: String) {
        let header = "HTTP/1.1 302 Found\r\nLocation: \(location)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        nwConnection.send(content: Data(header.utf8), completion: .contentProcessed { [self] _ in
            self.nwConnection.cancel()
        })
    }

    private func sendBadRequest() {
        sendStatus(400, body: "Bad Request")
    }

    private func send401() {
        sendStatus(401, body: "Unauthorized — invalid or missing session token.")
    }

    private func send404() {
        sendStatus(404, body: "Not Found")
    }

    private func send500() {
        sendStatus(500, body: "Internal Server Error")
    }

    private func sendStatus(_ code: Int, body: String) {
        let bodyData = Data(body.utf8)
        let header = "HTTP/1.1 \(code)\r\nContent-Type: text/plain\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(bodyData)
        nwConnection.send(content: response, completion: .contentProcessed { [self] _ in
            self.nwConnection.cancel()
        })
    }
}
