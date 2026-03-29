import Foundation
import Combine
import TunnelManCore

/// Tunnel provider using Cloudflare's cloudflared CLI (trycloudflare.com quick tunnels).
/// No account required for quick tunnels; however, authentication is provided by the session token.
/// For production, use a named tunnel with Cloudflare Access for email/OAuth enforcement.
final class CloudflaredProvider: TunnelProvider {
    private let port: UInt16
    private var process: Process?
    private let urlSubject = PassthroughSubject<URL, Never>()
    private let errorSubject = PassthroughSubject<String, Never>()

    var urlPublisher: AnyPublisher<URL, Never> { urlSubject.eraseToAnyPublisher() }
    var errorPublisher: AnyPublisher<String, Never> { errorSubject.eraseToAnyPublisher() }

    init(port: UInt16) {
        self.port = port
    }

    func start() throws {
        guard let cfPath = findExecutable("cloudflared") else {
            errorSubject.send("cloudflared not found. Install with: brew install cloudflared")
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: cfPath)
        proc.arguments = ["tunnel", "--url", "http://localhost:\(port)"]

        // cloudflared prints the tunnel URL to stderr
        let stderrPipe = Pipe()
        proc.standardError = stderrPipe
        proc.standardOutput = Pipe() // discard stdout

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            self?.parseOutput(text)
        }

        proc.terminationHandler = { [weak self] p in
            if p.terminationStatus != 0 {
                self?.errorSubject.send("cloudflared exited with status \(p.terminationStatus).")
            }
        }

        try proc.run()
        self.process = proc
    }

    func stop() {
        process?.terminate()
        process = nil
    }

    private func parseOutput(_ text: String) {
        if let url = parseCloudflaredURL(from: text) {
            urlSubject.send(url)
        }
    }
}
