import Foundation
import Darwin
import TunnelManHelper

/// Manages a pseudo-terminal (PTY) running the user's shell.
final class PTYManager {
    private(set) var masterFD: Int32 = -1
    private var slaveFD: Int32 = -1
    private var childPID: pid_t = -1
    private var readSource: DispatchSourceRead?

    /// Called whenever the PTY produces output bytes.
    var onData: ((Data) -> Void)?

    func start() throws {
        var master: Int32 = 0
        var slave: Int32 = 0

        guard openpty(&master, &slave, nil, nil, nil) == 0 else {
            throw PTYError.openFailed(errno)
        }
        masterFD = master
        slaveFD = slave

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"

        // Build a null-terminated C environment array
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"

        let envPairs = env.map { "\($0.key)=\($0.value)" }
        var cEnv: [UnsafeMutablePointer<CChar>?] = envPairs.map { strdup($0) }
        cEnv.append(nil)

        let pid = shell.withCString { shellPtr -> pid_t in
            cEnv.withUnsafeMutableBufferPointer { envBuf -> pid_t in
                pty_spawn_shell(master, slave, shellPtr, envBuf.baseAddress!)
            }
        }

        // Free strdup'd strings
        cEnv.compactMap { $0 }.forEach { free($0) }

        guard pid > 0 else {
            throw PTYError.forkFailed(errno)
        }

        close(slave)
        childPID = pid
        startReading()
    }

    func write(_ data: Data) {
        guard masterFD >= 0 else { return }
        data.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            _ = Darwin.write(masterFD, base, data.count)
        }
    }

    func stop() {
        readSource?.cancel()
        readSource = nil
        if childPID > 0 {
            kill(childPID, SIGHUP)
            childPID = -1
        }
        if masterFD >= 0 { close(masterFD); masterFD = -1 }
    }

    func resize(cols: UInt16, rows: UInt16) {
        guard masterFD >= 0 else { return }
        var ws = winsize()
        ws.ws_col = cols
        ws.ws_row = rows
        ws.ws_xpixel = 0
        ws.ws_ypixel = 0
        _ = ioctl(masterFD, TIOCSWINSZ, &ws)
    }

    private func startReading() {
        let source = DispatchSource.makeReadSource(fileDescriptor: masterFD, queue: .global())
        source.setEventHandler { [weak self] in
            guard let self, self.masterFD >= 0 else { return }
            var buf = [UInt8](repeating: 0, count: 4096)
            let n = Darwin.read(self.masterFD, &buf, buf.count)
            if n > 0 {
                let data = Data(buf[..<n])
                self.onData?(data)
            }
        }
        source.resume()
        readSource = source
    }
}

enum PTYError: LocalizedError {
    case openFailed(Int32)
    case forkFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .openFailed(let e): return "openpty failed: errno \(e)"
        case .forkFailed(let e): return "fork failed: errno \(e)"
        }
    }
}
