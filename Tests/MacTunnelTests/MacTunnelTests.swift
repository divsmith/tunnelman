import Testing
import Foundation
import MacTunnelCore

// ============================================================
// MARK: - WebSocket Accept Key (RFC 6455 §1.3)
// ============================================================

@Suite("WebSocket Accept Key")
struct WebSocketAcceptKeyTests {
    /// RFC 6455 §1.3 provides this exact test vector.
    @Test func rfc6455KnownVector() {
        let clientKey = "dGhlIHNhbXBsZSBub25jZQ=="
        let expected  = "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
        #expect(webSocketAcceptKey(for: clientKey) == expected)
    }

    @Test func differentKeysProduceDifferentAccepts() {
        let a = webSocketAcceptKey(for: "AAAAAAAAAAAAAAAAAAAAAA==")
        let b = webSocketAcceptKey(for: "BBBBBBBBBBBBBBBBBBBBBB==")
        #expect(a != b)
    }

    @Test func acceptKeyIsValidBase64() throws {
        let key    = "dGhlIHNhbXBsZSBub25jZQ=="
        let accept = webSocketAcceptKey(for: key)
        let decoded = Data(base64Encoded: accept)
        #expect(decoded != nil, "Accept key must be valid base64")
    }
}

// ============================================================
// MARK: - WebSocket Frame Encoding
// ============================================================

@Suite("WebSocket Frame Encoding")
struct WebSocketFrameTests {
    @Test func smallBinaryFrame() {
        let payload = Data("hello".utf8)
        let frame   = webSocketEncodeFrame(data: payload, opcode: 0x02)

        // Byte 0: FIN(1) + RSV(000) + opcode(0010) = 0x82
        #expect(frame[0] == 0x82)
        // Byte 1: MASK(0) + length(5) = 0x05
        #expect(frame[1] == 0x05)
        // Payload immediately follows the 2-byte header
        #expect(frame[2...] == payload)
        #expect(frame.count == 2 + payload.count)
    }

    @Test func textFrame() {
        let frame = webSocketEncodeFrame(data: Data("hi".utf8), opcode: 0x01)
        #expect(frame[0] == 0x81) // FIN + text opcode
    }

    @Test func emptyPayload() {
        let frame = webSocketEncodeFrame(data: Data(), opcode: 0x02)
        #expect(frame.count == 2)
        #expect(frame[1] == 0x00)
    }

    @Test func mediumFrame126ByteEncoding() {
        // Payloads 126–65535 bytes use the 2-byte extended length field
        let payload = Data(repeating: 0xAB, count: 200)
        let frame   = webSocketEncodeFrame(data: payload, opcode: 0x02)

        #expect(frame[1] == 126)
        let len = Int(frame[2]) << 8 | Int(frame[3])
        #expect(len == 200)
        #expect(frame.count == 2 + 2 + payload.count)
    }

    @Test func largeFrame127ByteEncoding() {
        // Payloads ≥65536 bytes use the 8-byte extended length field
        let payload = Data(repeating: 0xCD, count: 70_000)
        let frame   = webSocketEncodeFrame(data: payload, opcode: 0x02)

        #expect(frame[1] == 127)
        var len = 0
        for i in 2..<10 { len = (len << 8) | Int(frame[i]) }
        #expect(len == 70_000)
        #expect(frame.count == 2 + 8 + payload.count)
    }
}

// ============================================================
// MARK: - HTTP Session Token Extraction
// ============================================================

@Suite("HTTP Token Extraction")
struct TokenExtractionTests {
    @Test func extractFromTerminalPath() {
        #expect(extractSessionToken(from: "/terminal?token=abc123xyz") == "abc123xyz")
    }

    @Test func extractFromWSPath() {
        #expect(extractSessionToken(from: "/ws?token=deadbeef") == "deadbeef")
    }

    @Test func extractFromRootPath() {
        #expect(extractSessionToken(from: "/?token=mytoken") == "mytoken")
    }

    @Test func missingTokenReturnsNil() {
        #expect(extractSessionToken(from: "/terminal") == nil)
        #expect(extractSessionToken(from: "/terminal?foo=bar") == nil)
    }

    @Test func noQueryStringReturnsNil() {
        #expect(extractSessionToken(from: "/") == nil)
        #expect(extractSessionToken(from: "") == nil)
    }

    @Test func additionalQueryParamsIgnored() {
        #expect(extractSessionToken(from: "/ws?session=1&token=secret&v=2") == "secret")
    }

    @Test func uuidStyleToken() {
        let uuid = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4"
        #expect(extractSessionToken(from: "/terminal?token=\(uuid)") == uuid)
    }
}

// ============================================================
// MARK: - DevTunnel URL Parsing
// ============================================================

@Suite("DevTunnel URL Parsing")
struct DevTunnelURLParsingTests {
    @Test func typicalConnectLine() {
        // Real format: cluster code (e.g. "usw3") is part of the subdomain
        let output = """
        Hosting port: 19999
        Connect via browser: https://abc123def-19999.usw3.devtunnels.ms
        Inspect network activity: https://abc123def-19999-inspect.usw3.devtunnels.ms
        """
        #expect(parseDevTunnelURL(from: output)?.absoluteString == "https://abc123def-19999.usw3.devtunnels.ms")
    }

    @Test func urlWithPortSuffix() {
        let output = "Hosting port 8080 at https://abc123-8080.usw3.devtunnels.ms"
        #expect(parseDevTunnelURL(from: output)?.absoluteString == "https://abc123-8080.usw3.devtunnels.ms")
    }

    @Test func urlWithPath() {
        let output = "Open: https://xyz-tunnel.devtunnels.ms/some/path"
        let url = parseDevTunnelURL(from: output)
        #expect(url != nil)
        #expect(url?.absoluteString.contains("devtunnels.ms") == true)
    }

    @Test func nonMatchingOutputReturnsNil() {
        #expect(parseDevTunnelURL(from: "Starting tunnel...") == nil)
        #expect(parseDevTunnelURL(from: "Error: not authenticated") == nil)
        #expect(parseDevTunnelURL(from: "https://example.com") == nil)
    }

    @Test func schemeIsHTTPS() {
        #expect(parseDevTunnelURL(from: "https://my-tunnel.usw3.devtunnels.ms")?.scheme == "https")
    }
}

// ============================================================
// MARK: - Cloudflare URL Parsing
// ============================================================

@Suite("Cloudflare URL Parsing")
struct CloudflaredURLParsingTests {
    @Test func typicalINFBlock() {
        let output = """
        2024-01-01T00:00:00Z INF +---------------------------------------------+
        2024-01-01T00:00:00Z INF |  Your quick Tunnel has been created!        |
        2024-01-01T00:00:00Z INF |  https://random-words-here.trycloudflare.com|
        2024-01-01T00:00:00Z INF +---------------------------------------------+
        """
        #expect(parseCloudflaredURL(from: output)?.absoluteString == "https://random-words-here.trycloudflare.com")
    }

    @Test func singleLineOutput() {
        let output = "INF https://example-tunnel.trycloudflare.com"
        #expect(parseCloudflaredURL(from: output)?.absoluteString == "https://example-tunnel.trycloudflare.com")
    }

    @Test func nonMatchingOutputReturnsNil() {
        #expect(parseCloudflaredURL(from: "Connecting to Cloudflare...") == nil)
        #expect(parseCloudflaredURL(from: "https://example.com") == nil)
        // http is not matched — only https
        #expect(parseCloudflaredURL(from: "http://words.trycloudflare.com") == nil)
    }

    @Test func schemeIsHTTPS() {
        #expect(parseCloudflaredURL(from: "https://my-cool-tunnel.trycloudflare.com")?.scheme == "https")
    }

    @Test func hostIsCorrect() {
        let output = "Visit https://tunnel-abc123.trycloudflare.com now"
        #expect(parseCloudflaredURL(from: output)?.host == "tunnel-abc123.trycloudflare.com")
    }
}
