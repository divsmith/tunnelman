import Foundation
import Combine

/// Protocol for all tunnel providers.
protocol TunnelProvider: AnyObject {
    /// Emits the public base URL (without path/query) once the tunnel is ready.
    var urlPublisher: AnyPublisher<URL, Never> { get }
    /// Emits a human-readable error message if the tunnel fails.
    var errorPublisher: AnyPublisher<String, Never> { get }
    func start() throws
    func stop()
}
