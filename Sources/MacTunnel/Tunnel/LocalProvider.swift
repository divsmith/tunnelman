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

        var current = ifaddr
        while let ifa = current {
            let flags = Int32(ifa.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            if isUp && !isLoopback, ifa.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                var addr = ifa.pointee.ifa_addr.pointee
                var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                inet_ntop(AF_INET, &addr, &buf, socklen_t(INET_ADDRSTRLEN))
                let ip = String(cString: buf)
                // Prefer non-loopback, non-link-local
                if !ip.hasPrefix("169.254") {
                    return ip
                }
            }
            current = ifa.pointee.ifa_next
        }
        return nil
    }
}
