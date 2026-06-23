import Foundation
import Network
import Observation

// MARK: - NetworkMonitor

/// Monitors network connectivity using NWPathMonitor.
/// Uses system callbacks for real-time updates (no polling needed).
/// Note: NWPathMonitor requires DispatchQueue - no async/await API available from Apple.
@MainActor
@Observable
final class NetworkMonitor {
    /// Shared singleton instance.
    static let shared = NetworkMonitor()

    /// Whether the network is currently available.
    private(set) var isConnected: Bool = true

    /// Whether the connection is expensive (cellular/hotspot).
    private(set) var isExpensive: Bool = false

    /// Whether the connection is constrained (low data mode).
    private(set) var isConstrained: Bool = false

    /// The current network interface type.
    private(set) var interfaceType: InterfaceType = .unknown

    /// Human-readable description of the current connection status.
    var statusDescription: String {
        if !self.isConnected {
            return "No internet connection"
        }
        var description = self.interfaceType.description
        if self.isExpensive {
            description += " (expensive)"
        }
        if self.isConstrained {
            description += " (low data mode)"
        }
        return description
    }

    /// Network interface types.
    enum InterfaceType {
        case wifi
        case cellular
        case wiredEthernet
        case loopback
        case other
        case unknown

        var description: String {
            switch self {
            case .wifi: "Wi-Fi"
            case .cellular: "Cellular"
            case .wiredEthernet: "Ethernet"
            case .loopback: "Loopback"
            case .other: "Other"
            case .unknown: "Unknown"
            }
        }
    }

    /// NWPathMonitor is Sendable and immutable, so no isolation annotation needed.
    private let monitor: NWPathMonitor
    private let queue: DispatchQueue
    private let logger = DiagnosticsLogger.network

    /// Long-lived task that applies path updates in submission order. Cancelled
    /// when the monitor is torn down.
    @ObservationIgnored
    private var consumerTask: Task<Void, Never>?

    private init() {
        self.monitor = NWPathMonitor()
        self.queue = DispatchQueue(label: "com.melboonchan.boombox.networkMonitor", qos: .utility)
        self.startMonitoring()
    }

    deinit {
        self.monitor.cancel()
        self.consumerTask?.cancel()
    }

    /// Starts monitoring network changes.
    ///
    /// Path updates are funneled through an `AsyncStream` consumed by a single
    /// long-lived task so they are applied in submission order. Spawning a fresh
    /// `Task` per update (the prior approach) does not guarantee ordering, so a
    /// stale "unsatisfied" update could run after a newer "satisfied" one and
    /// strand `isConnected` on a false value during rapid flapping.
    private func startMonitoring() {
        let (stream, continuation) = AsyncStream<NWPath>.makeStream(
            bufferingPolicy: .bufferingNewest(16)
        )

        self.consumerTask = Task { @MainActor [weak self] in
            for await path in stream {
                self?.updatePath(path)
            }
        }

        // pathUpdateHandler is invoked serially on the monitor queue; yielding
        // preserves that order for the consumer.
        self.monitor.pathUpdateHandler = { path in
            continuation.yield(path)
        }
        self.monitor.start(queue: self.queue)
        self.logger.info("Network monitoring started")
    }

    /// Updates state based on the new network path.
    private func updatePath(_ path: NWPath) {
        let wasConnected = self.isConnected
        self.isConnected = path.status == .satisfied
        self.isExpensive = path.isExpensive
        self.isConstrained = path.isConstrained
        self.interfaceType = Self.mapInterfaceType(path)

        // Log connectivity changes
        if wasConnected != self.isConnected {
            if self.isConnected {
                self.logger.info("Network connected: \(self.statusDescription)")
            } else {
                self.logger.warning("Network disconnected")
            }
        }
    }

    /// Maps NWPath interface to our InterfaceType.
    private static func mapInterfaceType(_ path: NWPath) -> InterfaceType {
        if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            return .wiredEthernet
        } else if path.usesInterfaceType(.loopback) {
            return .loopback
        } else if path.usesInterfaceType(.other) {
            return .other
        }
        return .unknown
    }
}
