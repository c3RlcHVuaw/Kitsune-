import Libbox
import Network
import NetworkExtension
import Shared

/// Runs sing-box (libbox) inside the Network Extension.
/// The app passes the full sing-box JSON in start options under `configContent`.
final class PacketTunnelProvider: NEPacketTunnelProvider, @unchecked Sendable {
    private var commandServer: LibboxCommandServer?
    private var pathMonitor: NWPathMonitor?

    // Completion-handler overrides: the async ones don't compile under Swift 6 (non-Sendable options).
    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        guard let config = options?["configContent"] as? String else {
            completionHandler(TunnelError("missing configContent"))
            return
        }
        nonisolated(unsafe) let completionHandler = completionHandler
        // openTun below blocks on setTunnelNetworkSettings, so keep this off the provider's queue.
        DispatchQueue.global().async { [self] in
            do {
                try startService(config)
                completionHandler(nil)
            } catch {
                stopService()
                completionHandler(error)
            }
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        stopService()
        completionHandler()
    }

    /// The app sends a new config when the server or routing changes; reload without dropping the tunnel.
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        let config = String(decoding: messageData, as: UTF8.self)
        nonisolated(unsafe) let completionHandler = completionHandler
        DispatchQueue.global().async { [self] in
            do {
                reasserting = true
                defer { reasserting = false }
                try commandServer?.startOrReloadService(config, options: LibboxOverrideOptions())
                completionHandler?(nil)
            } catch {
                completionHandler?(Data(error.localizedDescription.utf8))
            }
        }
    }

    private func startService(_ config: String) throws {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppIdentifiers.appGroup)
            ?? FileManager.default.temporaryDirectory // a re-signed build may lack our App Group
        let setup = LibboxSetupOptions()
        setup.basePath = base.path
        setup.workingPath = base.appendingPathComponent("Working").path
        setup.tempPath = base.appendingPathComponent("Temp").path
        setup.logMaxLines = 3000
        setup.crashReportSource = "PacketTunnel"
        setup.oomKillerEnabled = true
        var error: NSError?
        LibboxSetup(setup, &error)
        if let error { throw TunnelError("setup: \(error.localizedDescription)") }

        guard let server = LibboxNewCommandServer(self, self, &error) else {
            throw TunnelError("command server: \(error?.localizedDescription ?? "unknown")")
        }
        commandServer = server
        try server.start()
        try server.startOrReloadService(config, options: LibboxOverrideOptions())
    }

    private func stopService() {
        try? commandServer?.closeService()
        commandServer?.close()
        commandServer = nil
        pathMonitor?.cancel()
        pathMonitor = nil
    }
}

struct TunnelError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

// MARK: - libbox platform interface

extension PacketTunnelProvider: LibboxPlatformInterfaceProtocol, LibboxCommandServerHandlerProtocol {
    func openTun(_ options: (any LibboxTunOptionsProtocol)?, ret0_: UnsafeMutablePointer<Int32>?) throws {
        guard let options, let ret0_ else { throw TunnelError("openTun: nil arguments") }
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        if options.getAutoRoute() {
            settings.mtu = NSNumber(value: options.getMTU())

            let v4 = prefixes(options.getInet4Address())
            let ipv4 = NEIPv4Settings(addresses: v4.map { $0.address() }, subnetMasks: v4.map { $0.mask() })
            let v4Routes = prefixes(options.getInet4RouteAddress()).map { NEIPv4Route(destinationAddress: $0.address(), subnetMask: $0.mask()) }
            ipv4.includedRoutes = v4Routes.isEmpty ? [.default()] : v4Routes
            ipv4.excludedRoutes = prefixes(options.getInet4RouteExcludeAddress()).map { NEIPv4Route(destinationAddress: $0.address(), subnetMask: $0.mask()) }
            settings.ipv4Settings = ipv4

            let v6 = prefixes(options.getInet6Address())
            let ipv6 = NEIPv6Settings(addresses: v6.map { $0.address() }, networkPrefixLengths: v6.map { NSNumber(value: $0.prefix()) })
            let v6Routes = prefixes(options.getInet6RouteAddress()).map { NEIPv6Route(destinationAddress: $0.address(), networkPrefixLength: NSNumber(value: $0.prefix())) }
            ipv6.includedRoutes = v6Routes.isEmpty ? [.default()] : v6Routes
            ipv6.excludedRoutes = prefixes(options.getInet6RouteExcludeAddress()).map { NEIPv6Route(destinationAddress: $0.address(), networkPrefixLength: NSNumber(value: $0.prefix())) }
            settings.ipv6Settings = ipv6

            if options.getDNSMode()?.value != LibboxDNSModeDisabled {
                let servers = strings(try options.getDNSServerAddress())
                if !servers.isEmpty { settings.dnsSettings = NEDNSSettings(servers: servers) }
            }
        }

        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var applyError: Error?
        setTunnelNetworkSettings(settings) { error in
            applyError = error
            done.signal()
        }
        done.wait()
        if let applyError { throw applyError }

        let fd = LibboxGetTunnelFileDescriptor()
        guard fd != -1 else { throw TunnelError("missing tunnel file descriptor") }
        ret0_.pointee = fd
    }

    func startDefaultInterfaceMonitor(_ listener: (any LibboxInterfaceUpdateListenerProtocol)?) throws {
        // libbox objects are Go-backed and safe to call from any thread.
        guard let listener else { return }
        nonisolated(unsafe) let unsafeListener = listener
        let monitor = NWPathMonitor()
        pathMonitor = monitor
        let first = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var signaled = false
        monitor.pathUpdateHandler = { path in
            // Feeds auto_detect_interface: direct traffic binds to this physical interface.
            if path.status == .unsatisfied {
                unsafeListener.updateDefaultInterface("", interfaceIndex: -1, isExpensive: false, isConstrained: false)
            } else if let interface = path.availableInterfaces.first {
                unsafeListener.updateDefaultInterface(interface.name, interfaceIndex: Int32(interface.index), isExpensive: path.isExpensive, isConstrained: path.isConstrained)
            }
            if !signaled { signaled = true; first.signal() }
        }
        monitor.start(queue: DispatchQueue(label: "kitsune.path-monitor"))
        first.wait()
    }

    func closeDefaultInterfaceMonitor(_ listener: (any LibboxInterfaceUpdateListenerProtocol)?) throws {
        pathMonitor?.cancel()
        pathMonitor = nil
    }

    func getInterfaces() throws -> any LibboxNetworkInterfaceIteratorProtocol {
        let path = pathMonitor?.currentPath
        let interfaces = (path?.status == .unsatisfied ? [] : path?.availableInterfaces ?? []).map { item in
            let interface = LibboxNetworkInterface()
            interface.name = item.name
            interface.index = Int32(item.index)
            interface.type = switch item.type {
            case .wifi: LibboxInterfaceTypeWIFI
            case .cellular: LibboxInterfaceTypeCellular
            case .wiredEthernet: LibboxInterfaceTypeEthernet
            default: LibboxInterfaceTypeOther
            }
            return interface
        }
        return InterfaceIterator(interfaces)
    }

    func underNetworkExtension() -> Bool { true }
    func includeAllNetworks() -> Bool { false }
    func usePlatformAutoDetectControl() -> Bool { false }
    func autoDetectControl(_ fd: Int32) throws {}
    func localDNSTransport() -> (any LibboxLocalDNSTransportProtocol)? { nil }
    func readWIFIState() -> LibboxWIFIState? { nil }
    func clearDNSCache() {}
    func registerMyInterface(_ name: String?) {}
    func tailscaleHostname() -> String { "" }
    func usePlatformShell() -> Bool { false }
    func usePlatformBridge() -> Bool { false }

    // Features Kitsune doesn't use: process lookup, notifications, SSH, bridges, neighbors.
    func findConnectionOwner(_ ipProtocol: Int32, sourceAddress: String?, sourcePort: Int32, destinationAddress: String?, destinationPort: Int32) throws -> LibboxConnectionOwner { throw unsupported }
    func send(_ notification: LibboxNotification?) throws {}
    func cancelNotification(_ identifier: String?, typeID: Int32) throws {}
    func startNeighborMonitor(_ listener: (any LibboxNeighborUpdateListenerProtocol)?) throws {}
    func closeNeighborMonitor(_ listener: (any LibboxNeighborUpdateListenerProtocol)?) throws {}
    func checkPlatformShell() throws { throw unsupported }
    func openShellSession(_ user: LibboxPlatformUser?, command: String?, environ: (any LibboxStringIteratorProtocol)?, term: String?, rows: Int32, cols: Int32) throws -> any LibboxShellSessionProtocol { throw unsupported }
    func lookupUser(_ username: String?) throws -> LibboxPlatformUser { throw unsupported }
    func lookupSFTPServer(_ error: NSErrorPointer) -> String { error?.pointee = unsupported; return "" }
    func readSystemSSHHostKey(_ error: NSErrorPointer) -> String { error?.pointee = unsupported; return "" }
    func createBridge(_ options: LibboxBridgeOptions?) throws -> any LibboxBridgeSessionProtocol { throw unsupported }

    // Command server handler.
    func serviceStop() throws { stopService() }
    func serviceReload() throws {}
    func getSystemProxyStatus() throws -> LibboxSystemProxyStatus { LibboxSystemProxyStatus() }
    func setSystemProxyEnabled(_ enabled: Bool) throws {}
    func triggerNativeCrash() throws {}
    func writeDebugMessage(_ message: String?) {}
    func connectSSHAgent(_ ret0_: UnsafeMutablePointer<Int32>?) throws { throw unsupported }

    private var unsupported: NSError {
        NSError(domain: "Kitsune", code: -1, userInfo: [NSLocalizedDescriptionKey: "not supported"])
    }
}

private func prefixes(_ iterator: (any LibboxRoutePrefixIteratorProtocol)?) -> [LibboxRoutePrefix] {
    var result: [LibboxRoutePrefix] = []
    while let iterator, iterator.hasNext(), let next = iterator.next() { result.append(next) }
    return result
}

private func strings(_ iterator: (any LibboxStringIteratorProtocol)?) -> [String] {
    var result: [String] = []
    while let iterator, iterator.hasNext() { result.append(iterator.next()) }
    return result
}

private final class InterfaceIterator: NSObject, LibboxNetworkInterfaceIteratorProtocol {
    private var items: [LibboxNetworkInterface]
    init(_ items: [LibboxNetworkInterface]) { self.items = items }
    func hasNext() -> Bool { !items.isEmpty }
    func next() -> LibboxNetworkInterface? { items.isEmpty ? nil : items.removeFirst() }
}
