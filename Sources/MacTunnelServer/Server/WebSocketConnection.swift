import Foundation
import Network
import MacTunnelCore
import os

private let log = Logger(subsystem: "mactunnel", category: "websocket")

/// Manages a WebSocket connection for a single browser client.
/// Performs the RFC 6455 handshake manually (since NWProtocolWebSocket
/// can only be configured at listener creation time for custom framing).
final class WebSocketConnection {
    private let nwConnection: NWConnection
    private weak var ptyManager: PTYManager?
    private let httpHeader: String
    var onClose: (() -> Void)?

    init(nwConnection: NWConnection, ptyManager: PTYManager?, httpHeader: String) {
        self.nwConnection = nwConnection
        self.ptyManager = ptyManager
        self.httpHeader = httpHeader
    }

    func cancel() {
        nwConnection.cancel()
    }

    func performHandshake(originalHeader: String, completion: @escaping () -> Void) {
        // Extract Sec-WebSocket-Key
        guard let key = extractWebSocketKey(from: originalHeader) else {
            nwConnection.cancel(); return
        }
        let acceptKey = makeAcceptKey(from: key)
        let response = """
        HTTP/1.1 101 Switching Protocols\r\n\
        Upgrade: websocket\r\n\
        Connection: Upgrade\r\n\
        Sec-WebSocket-Accept: \(acceptKey)\r\n\
        \r\n
        """
        nwConnection.send(content: Data(response.utf8), completion: .contentProcessed { [weak self] error in
            guard error == nil else { self?.nwConnection.cancel(); return }
            completion()
            self?.startReading()
        })
    }

    func send(_ data: Data) {
        let frame = encodeFrame(data: data, opcode: 0x02) // binary frame
        nwConnection.send(content: frame, completion: .idempotent)
    }

    private func startReading() {
        receiveFrame()
    }

    private func receiveFrame() {
        // Read WebSocket frame header: at least 2 bytes
        nwConnection.receive(minimumIncompleteLength: 2, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                log.debug("WebSocket read error: \(error)")
                self.close(); return
            }
            guard let data, !data.isEmpty else {
                if isComplete { self.close() }
                return
            }
            self.processFrame(data)
        }
    }

    private func processFrame(_ data: Data) {
        guard data.count >= 2 else { receiveFrame(); return }
        let byte0 = data[0]
        let byte1 = data[1]
        let opcode = byte0 & 0x0F
        let masked = (byte1 & 0x80) != 0
        var payloadLen = Int(byte1 & 0x7F)
        var offset = 2

        if payloadLen == 126 {
            guard data.count >= 4 else { receiveFrame(); return }
            payloadLen = Int(data[2]) << 8 | Int(data[3])
            offset = 4
        } else if payloadLen == 127 {
            guard data.count >= 10 else { receiveFrame(); return }
            payloadLen = 0
            for i in 2..<10 { payloadLen = payloadLen << 8 | Int(data[i]) }
            offset = 10
        }

        let maskOffset = offset
        if masked { offset += 4 }
        let payloadOffset = offset

        guard data.count >= payloadOffset + payloadLen else {
            // Need more data — for simplicity, skip (real impl would buffer)
            receiveFrame(); return
        }

        var payload = Data(data[payloadOffset..<(payloadOffset + payloadLen)])
        if masked {
            let mask = data[maskOffset..<(maskOffset + 4)]
            for i in 0..<payload.count {
                payload[i] ^= mask[mask.startIndex + i % 4]
            }
        }

        switch opcode {
        case 0x01: // text frame — may be resize control message or keyboard input
            if let dict = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
               dict["type"] as? String == "resize",
               let cols = dict["cols"] as? Int,
               let rows = dict["rows"] as? Int {
                ptyManager?.resize(cols: UInt16(cols), rows: UInt16(rows))
            } else {
                ptyManager?.write(payload)
            }
        case 0x02: // binary frame — raw keyboard input from browser
            ptyManager?.write(payload)
        case 0x08: // close
            close(); return
        case 0x09: // ping
            let pong = encodeFrame(data: payload, opcode: 0x0A)
            nwConnection.send(content: pong, completion: .idempotent)
        default:
            break
        }
        receiveFrame()
    }

    private func close() {
        nwConnection.cancel()
        onClose?()
    }

    // MARK: - Helpers

    private func extractWebSocketKey(from header: String) -> String? {
        for line in header.components(separatedBy: "\r\n") {
            if line.lowercased().hasPrefix("sec-websocket-key:") {
                return line.dropFirst("sec-websocket-key:".count).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private func makeAcceptKey(from key: String) -> String {
        webSocketAcceptKey(for: key)
    }

    private func encodeFrame(data: Data, opcode: UInt8) -> Data {
        webSocketEncodeFrame(data: data, opcode: opcode)
    }
}
