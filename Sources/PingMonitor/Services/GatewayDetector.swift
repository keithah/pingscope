import CoreWLAN
import Darwin
import Foundation
import Network

struct GatewayInfo: Sendable, Equatable {
    let ipAddress: String
    let interfaceName: String?
    let networkName: String?

    static let unavailable = GatewayInfo(ipAddress: "", interfaceName: nil, networkName: nil)

    var isAvailable: Bool {
        !ipAddress.isEmpty
    }

    var displayName: String {
        if let networkName, !networkName.isEmpty {
            return "\(networkName) Gateway"
        }

        return ipAddress.isEmpty ? "No Network" : ipAddress
    }
}

private func getDefaultGateway() -> (ip: String, interface: String?)? {
    var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS, RTF_GATEWAY]
    var bufferSize = 0

    guard sysctl(&mib, UInt32(mib.count), nil, &bufferSize, nil, 0) == 0,
          bufferSize > 0
    else {
        return nil
    }

    var buffer = [UInt8](repeating: 0, count: bufferSize)

    guard sysctl(&mib, UInt32(mib.count), &buffer, &bufferSize, nil, 0) == 0,
          bufferSize > 0
    else {
        return nil
    }

    let alignment = MemoryLayout<Int>.size
    let messageHeaderSize = MemoryLayout<rt_msghdr>.stride

    func roundedAddressLength(_ length: Int) -> Int {
        (length + alignment - 1) & ~(alignment - 1)
    }

    func parseIPv4Address(from socketAddress: UnsafeRawPointer, length: Int) -> String? {
        let minimumLength = min(length, MemoryLayout<sockaddr_in>.size)
        guard minimumLength >= MemoryLayout<sockaddr>.size else {
            return nil
        }

        var address = sockaddr_in()
        withUnsafeMutableBytes(of: &address) { rawBuffer in
            rawBuffer.copyBytes(from: UnsafeRawBufferPointer(start: socketAddress, count: minimumLength))
        }

        guard address.sin_family == UInt8(AF_INET) else {
            return nil
        }

        var ipv4 = address.sin_addr
        var hostBuffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &ipv4, &hostBuffer, socklen_t(INET_ADDRSTRLEN)) != nil else {
            return nil
        }

        return String(cString: hostBuffer)
    }

    return buffer.withUnsafeBytes { rawBuffer in
        guard let base = rawBuffer.baseAddress else {
            return nil
        }

        var offset = 0

        while offset + messageHeaderSize <= bufferSize {
            let messagePointer = base.advanced(by: offset).assumingMemoryBound(to: rt_msghdr.self)
            let message = messagePointer.pointee
            let messageLength = Int(message.rtm_msglen)

            guard messageLength > 0, offset + messageLength <= bufferSize else {
                break
            }

            var destinationIP: String?
            var gatewayIP: String?

            var socketAddressPointer = base.advanced(by: offset + messageHeaderSize)

            for index in 0..<Int(RTAX_MAX) {
                let bitmask = Int32(1 << index)
                guard (message.rtm_addrs & bitmask) != 0 else {
                    continue
                }

                let sockaddrPointer = socketAddressPointer.assumingMemoryBound(to: sockaddr.self)
                let socketAddressLength = max(Int(sockaddrPointer.pointee.sa_len), MemoryLayout<sockaddr>.size)

                if index == Int(RTAX_DST) {
                    destinationIP = parseIPv4Address(from: socketAddressPointer, length: socketAddressLength)
                } else if index == Int(RTAX_GATEWAY) {
                    gatewayIP = parseIPv4Address(from: socketAddressPointer, length: socketAddressLength)
                }

                socketAddressPointer = socketAddressPointer.advanced(by: roundedAddressLength(socketAddressLength))
            }

            if destinationIP == "0.0.0.0", let gatewayIP {
                var interfaceName = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                let interface = if_indextoname(UInt32(message.rtm_index), &interfaceName)
                    .map { _ in String(cString: interfaceName) }
                return (gatewayIP, interface)
            }

            offset += messageLength
        }

        return nil
    }
}

private func getCurrentSSID() -> String? {
    CWWiFiClient.shared().interface()?.ssid()
}

actor GatewayDetector {
    private var pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "GatewayDetector")
    private var debounceTask: Task<Void, Never>?
    private let debounceInterval: Duration = .milliseconds(200)

    private(set) var currentGateway: GatewayInfo = .unavailable
    private var previousNetworkName: String?
    private var hasUnacknowledgedNetworkChange = false

    var isNetworkAvailable: Bool {
        currentGateway.isAvailable
    }

    var networkJustChanged: Bool {
        hasUnacknowledgedNetworkChange
    }

    func startMonitoring() -> AsyncStream<GatewayInfo> {
        AsyncStream { continuation in
            pathMonitor.pathUpdateHandler = { [weak self] path in
                guard let self else {
                    return
                }

                Task {
                    await self.handlePathUpdate(path: path, continuation: continuation)
                }
            }

            pathMonitor.start(queue: monitorQueue)

            Task {
                let gateway = await self.resolveGateway()
                self.updateGateway(gateway, continuation: continuation)
            }

            continuation.onTermination = { [weak self] _ in
                guard let self else {
                    return
                }

                Task {
                    await self.stopMonitoring()
                }
            }
        }
    }

    func stopMonitoring() {
        pathMonitor.cancel()
        debounceTask?.cancel()
        debounceTask = nil
        pathMonitor = NWPathMonitor()
    }

    func acknowledgeNetworkChange() {
        hasUnacknowledgedNetworkChange = false
    }

    private func handlePathUpdate(
        path: NWPath,
        continuation: AsyncStream<GatewayInfo>.Continuation
    ) {
        switch path.status {
        case .satisfied:
            debounceTask?.cancel()
            debounceTask = Task {
                try? await Task.sleep(for: debounceInterval)
                guard !Task.isCancelled else {
                    return
                }

                let gateway = await self.resolveGateway()
                self.updateGateway(gateway, continuation: continuation)
            }
        case .unsatisfied, .requiresConnection:
            debounceTask?.cancel()
            debounceTask = nil
            updateGateway(.unavailable, continuation: continuation)
        @unknown default:
            debounceTask?.cancel()
            debounceTask = nil
            updateGateway(.unavailable, continuation: continuation)
        }
    }

    private func resolveGateway() async -> GatewayInfo {
        async let gatewayLookup = Task.detached(priority: .utility) {
            getDefaultGateway()
        }.value
        async let ssidLookup = Task.detached(priority: .utility) {
            getCurrentSSID()
        }.value

        guard let gateway = await gatewayLookup else {
            _ = await ssidLookup
            return .unavailable
        }

        let networkName = await ssidLookup
        return GatewayInfo(
            ipAddress: gateway.ip,
            interfaceName: gateway.interface,
            networkName: networkName
        )
    }

    private func updateGateway(
        _ gateway: GatewayInfo,
        continuation: AsyncStream<GatewayInfo>.Continuation
    ) {
        if let previousNetworkName, previousNetworkName != gateway.networkName {
            hasUnacknowledgedNetworkChange = true
        }

        previousNetworkName = gateway.networkName
        currentGateway = gateway
        continuation.yield(gateway)
    }
}
