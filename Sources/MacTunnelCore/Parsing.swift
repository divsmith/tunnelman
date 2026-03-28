import Foundation
import CryptoKit

// MARK: - WebSocket helpers

/// Computes the Sec-WebSocket-Accept response header value per RFC 6455 §1.3.
public func webSocketAcceptKey(for clientKey: String) -> String {
    let magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    let hash = Insecure.SHA1.hash(data: Data((clientKey + magic).utf8))
    return Data(hash).base64EncodedString()
}

/// Encodes a WebSocket frame (server-to-client, unmasked).
public func webSocketEncodeFrame(data: Data, opcode: UInt8) -> Data {
    var frame = Data()
    frame.append(0x80 | opcode)
    let len = data.count
    if len < 126 {
        frame.append(UInt8(len))
    } else if len < 65536 {
        frame.append(126)
        frame.append(UInt8((len >> 8) & 0xFF))
        frame.append(UInt8(len & 0xFF))
    } else {
        frame.append(127)
        for i in stride(from: 56, through: 0, by: -8) {
            frame.append(UInt8((len >> i) & 0xFF))
        }
    }
    frame.append(data)
    return frame
}

// MARK: - HTTP token extraction

/// Extracts the `token` query parameter from a URL path string (e.g. `/terminal?token=abc`).
public func extractSessionToken(from path: String) -> String? {
    guard let queryStart = path.firstIndex(of: "?") else { return nil }
    let query = String(path[path.index(after: queryStart)...])
    return URLComponents(string: "http://x?\(query)")?.queryItems?.first(where: { $0.name == "token" })?.value
}

// MARK: - Tunnel URL parsing

/// Parses a DevTunnel public URL from a chunk of devtunnel CLI output.
/// Matches multi-level subdomains like `abc123-8080.usw3.devtunnels.ms`.
public func parseDevTunnelURL(from text: String) -> URL? {
    guard let range = text.range(of: #"https://[a-z0-9][a-z0-9\-\.]+\.devtunnels\.ms[^\s]*"#, options: .regularExpression) else {
        return nil
    }
    return URL(string: String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines))
}

/// Parses a Cloudflare quick-tunnel URL from a chunk of cloudflared CLI output.
public func parseCloudflaredURL(from text: String) -> URL? {
    guard let range = text.range(of: #"https://[a-z0-9\-]+\.trycloudflare\.com"#, options: .regularExpression) else {
        return nil
    }
    return URL(string: String(text[range]))
}
