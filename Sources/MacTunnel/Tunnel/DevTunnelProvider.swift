import Foundation
import Combine

/// Tunnel provider using Microsoft DevTunnel CLI.
/// Requires: `devtunnel user login` completed once beforehand.
final class DevTunnelProvider: TunnelProvider {
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
        guard let devtunnelPath = findExecutable("devtunnel") else {
            errorSubject.send("devtunnel not found. Install with: brew install --cask devtunnel")
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: devtunnelPath)
        proc.arguments = ["host", "-p", "\(port)", "--allow-anonymous", "false"]

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            self?.parseOutput(text)
        }

        proc.terminationHandler = { [weak self] p in
            if p.terminationStatus != 0 {
                self?.errorSubject.send("devtunnel exited with status \(p.terminationStatus). Run 'devtunnel user login' if not authenticated.")
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
        // devtunnel outputs lines like:
        //   Connect via browser: https://abc123.devtunnels.ms
        // or
        //   Tunnel ID: abc123
        //   Hosting port: 8080 at https://abc123-8080.devtunnels.ms
        let patterns = [
            #"https://[a-z0-9\-]+\.devtunnels\.ms[^\s]*"#,
        ]
        for pattern in patterns {
            if let range = text.range(of: pattern, options: .regularExpression) {
                let urlStr = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if let url = URL(string: urlStr) {
                    urlSubject.send(url)
                    return
                }
            }
        }
    }
}
