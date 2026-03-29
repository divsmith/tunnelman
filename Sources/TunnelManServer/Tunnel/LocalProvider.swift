import Foundation
import Combine
import Network

/// Local network provider — no subprocess. Uses the machine's LAN IP.
final class LocalProvider: TunnelProvider {
    private let port: UInt16
    private let urlSubject = PassthroughSubject<URL, Never>()
    private let errorSubject = PassthroughSubject<String, Never>()

    var urlPublisher: AnyPublisher<URL, Never> { urlSubject.eraseToAnyPublisher() }
    var errorPublisher: AnyPublisher<String, Never> { errorSubject.eraseToAnyPublisher() }

    init(port: UInt16) {
        self.port = port
    }

    func start() throws {
        let ip = Self.localIPAddress() ?? "127.0.0.1"
        guard let url = URL(string: "http://\(ip):\(port)") else {
            errorSubject.send("Could not construct local URL.")
            return
        }
        urlSubject.send(url)
    }

    func stop() {}

    private static func localIPAddress() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }

        var fallback: String? = nil
        var current = ifaddr
        while let ifa = current {
            defer { current = ifa.pointee.ifa_next }

            let flags = Int32(ifa.pointee.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0 else { continue }
            guard ifa.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }

            // Reinterpret as sockaddr_in to access sin_addr correctly
            var sinAddr = ifa.pointee.ifa_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                $0.pointee.sin_addr
            }
            var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            inet_ntop(AF_INET, &sinAddr, &buf, socklen_t(INET_ADDRSTRLEN))
            let ip = String(cString: buf)

            guard !ip.hasPrefix("169.254") else { continue } // skip link-local

            // Prefer physical/Wi-Fi interfaces (en0, en1, …) over VPN tunnels (utun*, etc.)
            let name = String(cString: ifa.pointee.ifa_name)
            if name.hasPrefix("en") {
                return ip
            }
            if fallback == nil { fallback = ip }
        }
        return fallback
    }
}
