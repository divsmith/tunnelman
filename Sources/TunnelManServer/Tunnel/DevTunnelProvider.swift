import Foundation
import Combine
import TunnelManCore

/// Tunnel provider using Microsoft DevTunnel CLI.
/// Requires: `devtunnel user login` completed once beforehand.
final class DevTunnelProvider: TunnelProvider {
    private let port: UInt16
    private var process: Process?
    private let urlSubject = PassthroughSubject<URL, Never>()
    private let errorSubject = PassthroughSubject<String, Never>()
    private var outputBuffer = ""

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
        proc.arguments = ["host", "-p", "\(port)", "--allow-anonymous"]

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            self?.parseOutput(text)
        }

        proc.terminationHandler = { [weak self] p in
            guard let self else { return }
            if p.terminationStatus != 0 {
                if self.detectsLoginRequired(self.outputBuffer) {
                    self.errorSubject.send("DEVTUNNEL_NOT_LOGGED_IN")
                } else {
                    self.errorSubject.send("devtunnel exited with status \(p.terminationStatus). Run 'devtunnel user login' if not authenticated.")
                }
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
        outputBuffer += text
        if let url = parseDevTunnelURL(from: text) {
            urlSubject.send(url)
        }
    }

    private func detectsLoginRequired(_ output: String) -> Bool {
        let lower = output.lowercased()
        return lower.contains("not logged in") || lower.contains("user login")
    }
}
