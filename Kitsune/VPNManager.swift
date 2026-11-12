import NetworkExtension
import Observation
#if os(macOS)
import AppKit
#endif
import Shared

/// Installs the VPN profile, starts/stops the PacketTunnel extension and mirrors its status.
@MainActor @Observable
final class VPNManager {
    private(set) var status: NEVPNStatus = .invalid
    private(set) var lastError: String?
    /// macOS: true while the app explains why the system will ask for the administrator password.
    var showPasswordExplainer = false
    private var passwordConsent: CheckedContinuation<Bool, Never>?

    func answerPasswordExplainer(_ proceed: Bool) {
        showPasswordExplainer = false
        passwordConsent?.resume(returning: proceed)
        passwordConsent = nil
    }

    fileprivate func askPasswordConsent() async -> Bool {
        await withCheckedContinuation { continuation in
            passwordConsent = continuation
            showPasswordExplainer = true
        }
    }
    private(set) var connectedDate: Date?
    /// Live speed (bytes/s) and session totals (bytes), from the core's /traffic stream.
    private(set) var downRate: Int64 = 0
    private(set) var upRate: Int64 = 0
    private(set) var downTotal: Int64 = 0
    private(set) var upTotal: Int64 = 0
    /// Last ~40 seconds of download speed, for the sparkline.
    private(set) var downHistory: [Int64] = []
    private(set) var upHistory: [Int64] = []
    /// Programs using the most traffic right now (bytes/s), macOS only: the core must look up the owner of each connection.
    private(set) var topApps: [(name: String, rate: Int64)] = []
    /// A short plain-language note, e.g. after the tunnel recovered by itself. Clears after a few seconds.
    private(set) var notice: String?
    /// Servers present in the running tunnel's config, i.e. measurable through it.
    private(set) var tunnelServerIDs: Set<String> = []
    private var manager: NETunnelProviderManager?
    #if os(macOS)
    private var monitor: Task<Void, Never>?
    fileprivate var coreProcess: Process?
    /// What the user last connected with, to rebuild the tunnel after an unexpected drop.
    fileprivate var lastConnect: (server: ServerConfig, servers: [ServerConfig], routing: RoutingSettings)?
    fileprivate var reconnectAttempts = 0
    #endif

    init() {
        Task { await trafficLoop() }
        Task { await appsLoop() }
        #if !os(macOS)
        Task { await load() }
        Task {
            for await _ in NotificationCenter.default.notifications(named: .NEVPNStatusDidChange) {
                await refreshStatus()
            }
        }
        #else
        status = .disconnected
        // Quitting must not leave a root-owned tunnel behind: removing the flag file stops it.
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if self?.status.isActive == true { self?.disconnect() } }
        }
        #endif
    }

    /// Builds the sing-box config for this server and routing, then starts the tunnel.
    func connect(_ server: ServerConfig, servers: [ServerConfig], routing: RoutingSettings) async {
        lastError = nil
        #if os(macOS)
        reconnectAttempts = 0
        await connectDirect(server, servers: servers, routing: routing)
        #else
        do {
            let config = try Self.config(server, servers: servers, routing: routing)
            let manager = try await installedManager(name: server.name)
            try manager.connection.startVPNTunnel(options: ["configContent": config as NSString])
            tunnelServerIDs = Set(([server] + servers).map(\.id))
        } catch {
            lastError = Self.describe(error)
        }
        #endif
    }

    /// Swaps the running tunnel's config without disconnecting (server or routing changed).
    func reload(_ server: ServerConfig, servers: [ServerConfig], routing: RoutingSettings) {
        #if os(macOS)
        // Only the active server can change live (selector switch); routing edits apply on the next connect.
        guard status == .connected else { return }
        Task { await Self.coreRequest("proxies/proxy", method: "PUT", body: ["name": ConfigBuilder.tag(for: server)]) }
        #else
        guard status == .connected || status == .reasserting,
              let session = manager?.connection as? NETunnelProviderSession,
              let config = try? Self.config(server, servers: servers, routing: routing)
        else { return }
        tunnelServerIDs = Set(([server] + servers).map(\.id))
        do {
            try session.sendProviderMessage(Data(config.utf8)) { [weak self] reply in
                guard let reply, !reply.isEmpty else { return }
                let message = String(decoding: reply, as: UTF8.self)
                Task { @MainActor in self?.lastError = message }
            }
        } catch {
            lastError = Self.describe(error)
        }
        #endif
    }

    /// Shows the system VPN permission prompt. Returns false if the user declined.
    func installProfile() async -> Bool {
        #if os(macOS)
        return true // no VPN profile on macOS: the app starts the core itself and asks for the admin password then
        #else
        do {
            _ = try await installedManager(name: "Kitsune")
            return true
        } catch {
            lastError = Self.describe(error)
            return false
        }
        #endif
    }

    func clearError() { lastError = nil }

    /// Connect with the selected server, or disconnect if already active.
    func toggle(library: Library) async {
        if status.isActive {
            disconnect()
        } else if let server = library.selected {
            await connect(server, servers: library.allServers, routing: library.routing)
        }
    }

    private struct Traffic: Decodable { let up: Int64; let down: Int64 }

    /// Reads sing-box's per-second /traffic stream while connected; resets the counters otherwise.
    private func trafficLoop() async {
        while !Task.isCancelled {
            guard status == .connected else {
                if !downHistory.isEmpty || downTotal != 0 || upTotal != 0 || downRate != 0 || upRate != 0 { downRate = 0; upRate = 0; downTotal = 0; upTotal = 0; downHistory = []; upHistory = [] }
                try? await Task.sleep(for: .seconds(1))
                continue
            }
            var request = URLRequest(url: URL(string: "http://127.0.0.1:\(Self.controller.port)/traffic")!, timeoutInterval: 30)
            request.setValue("Bearer \(Self.controller.secret)", forHTTPHeaderField: "Authorization")
            do {
                let (bytes, _) = try await URLSession.shared.bytes(for: request)
                for try await line in bytes.lines {
                    guard status == .connected, let t = try? JSONDecoder().decode(Traffic.self, from: Data(line.utf8)) else { break }
                    downRate = t.down; upRate = t.up
                    downTotal += t.down; upTotal += t.up
                    TrafficStats.record(down: t.down, up: t.up)
                    downHistory.append(t.down)
                    upHistory.append(t.up)
                    if downHistory.count > 60 { downHistory.removeFirst(); upHistory.removeFirst() }
                }
            } catch {}
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private struct Connections: Decodable {
        struct Item: Decodable {
            struct Meta: Decodable { let processPath: String? }
            let id: String; let upload: Int64; let download: Int64; let metadata: Meta?
        }
        let connections: [Item]?
    }

    /// Every two seconds: which program moved how many bytes, from the core's /connections list.
    private func appsLoop() async {
        var last: [String: Int64] = [:]
        var lastTime = Date.now
        var primed = false
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(2))
            guard status == .connected else {
                if !topApps.isEmpty { topApps = [] }
                last = [:]; primed = false
                continue
            }
            var request = URLRequest(url: URL(string: "http://127.0.0.1:\(Self.controller.port)/connections")!, timeoutInterval: 3)
            request.setValue("Bearer \(Self.controller.secret)", forHTTPHeaderField: "Authorization")
            guard let (data, _) = try? await URLSession.shared.data(for: request),
                  let list = try? JSONDecoder().decode(Connections.self, from: data) else { continue }
            let now = Date.now
            let seconds = max(now.timeIntervalSince(lastTime), 0.5)
            lastTime = now
            var perApp: [String: Int64] = [:]
            var current: [String: Int64] = [:]
            for item in list.connections ?? [] {
                let total = item.upload + item.download
                current[item.id] = total
                guard primed, let path = item.metadata?.processPath, !path.isEmpty else { continue }
                perApp[Self.appName(path), default: 0] += max(total - (last[item.id] ?? 0), 0)
            }
            last = current
            let wasPrimed = primed
            primed = true
            guard wasPrimed else { continue }
            topApps = perApp.map { (name: $0.key, rate: Int64(Double($0.value) / seconds)) }
                .filter { $0.rate > 1024 }.sorted { $0.rate > $1.rate }.prefix(3).map { $0 }
        }
    }

    /// "/Applications/Claude.app/…/Claude Helper (air)" → "Claude": the outermost app bundle, without the user the core appends.
    private static func appName(_ path: String) -> String {
        if let app = path.split(separator: "/").first(where: { $0.hasSuffix(".app") }) { return String(app.dropLast(4)) }
        let name = URL(filePath: path).lastPathComponent
        return name.replacing(#/ \([^)]*\)$/#, with: "")
    }

    func disconnect() {
        #if os(macOS)
        status = .disconnecting
        try? FileManager.default.removeItem(at: Self.coreDir.appending(path: "run")) // the root watcher sees this and stops the core
        #else
        manager?.connection.stopVPNTunnel()
        #endif
    }

    #if !os(macOS)
    private func load() async {
        manager = try? await NETunnelProviderManager.loadAllFromPreferences().first
        await refreshStatus()
    }

    private func refreshStatus() async {
        guard let connection = manager?.connection else { status = .invalid; return }
        let previous = status
        status = connection.status
        connectedDate = connection.connectedDate
        if status == .disconnected, previous == .connecting || previous == .connected || previous == .disconnecting {
            // The async variant throws the last error instead of returning it.
            do { try await connection.fetchLastDisconnectError() } catch { lastError = Self.describe(error) }
        }
    }

    #endif

    /// Real latency through each server in the running tunnel: an HTTPS request via every outbound, done by sing-box.
    /// Returns server id → milliseconds for servers that answered, or nil when the tunnel isn't up or the API failed.
    func tunnelDelays() async -> [String: Int]? {
        guard status == .connected else { return nil }
        var url = URLComponents(string: "http://127.0.0.1:\(Self.controller.port)/group/proxy/delay")!
        url.queryItems = [.init(name: "url", value: "https://www.gstatic.com/generate_204"), .init(name: "timeout", value: "5000")]
        var request = URLRequest(url: url.url!, timeoutInterval: 10)
        request.setValue("Bearer \(Self.controller.secret)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let byTag = try? JSONDecoder().decode([String: Int].self, from: data)
        else { return nil }
        return Dictionary(byTag.map { (String($0.key.dropFirst(2)), $0.value) }, uniquingKeysWith: { first, _ in first }) // "s-<id>" → id
    }

    fileprivate static func config(_ server: ServerConfig, servers: [ServerConfig], routing: RoutingSettings) throws -> String {
        #if os(macOS)
        let share = LANSharing.current
        #else
        let share: LANShare? = nil
        #endif
        #if os(macOS)
        let findProcess = true
        #else
        let findProcess = false
        #endif
        return try ConfigBuilder.build(server, servers: servers, routing: routing, bundledRuleSets: bundledRuleSets, controller: controller, share: share, findProcess: findProcess)
    }

    /// Local control API of sing-box inside the extension. The secret persists so the API keeps working after an app relaunch.
    fileprivate static let controller: ConfigBuilder.Controller = {
        let secret = Keychain.string("controllerSecret") ?? {
            let new = UUID().uuidString + UUID().uuidString
            Keychain.set(new, for: "controllerSecret")
            return new
        }()
        return ConfigBuilder.Controller(port: 19090, secret: secret)
    }()

    /// Rule-set snapshot inside the extension bundle. Same absolute path in the app and the extension process.
    #if os(macOS)
    // The core runs from the app itself; build-mac.sh copies the snapshot next to it.
    private static let bundledRuleSets = Bundle.main.resourceURL?.appending(path: "RuleSets").path(percentEncoded: false)
    #else
    private static let bundledRuleSets = Bundle.main.builtInPlugInsURL?
        .appending(path: "PacketTunnel.appex/RuleSets").path(percentEncoded: false)
    #endif

    /// Human-readable Russian text for errors from links, VPN and the system.
    static func describe(_ error: Error) -> String {
        #if targetEnvironment(simulator)
        if (error as NSError).domain == NEVPNErrorDomain {
            return L("В симуляторе iOS VPN не работает. Проверить подключение можно только на iPhone.")
        }
        #endif
        if let error = error as? NEVPNError {
            return switch error.code {
            case .configurationReadWriteFailed: L("Не удалось сохранить VPN-профиль. Разрешите добавление VPN-конфигурации и попробуйте ещё раз.")
            case .configurationDisabled: L("VPN-профиль Kitsune выключен в Настройках → VPN.")
            case .configurationInvalid, .configurationStale, .configurationUnknown: L("VPN-профиль повреждён. Попробуйте подключиться ещё раз.")
            case .connectionFailed: L("Не удалось подключиться к серверу.")
            @unknown default: error.localizedDescription
            }
        }
        let nsError = error as NSError
        if nsError.domain == NEVPNConnectionErrorDomain, let code = NEVPNConnectionError(rawValue: nsError.code) {
            return switch code {
            case .noNetworkAvailable: L("Нет подключения к интернету.")
            case .serverAddressResolutionFailed: L("Не удалось найти адрес сервера.")
            case .serverNotResponding, .serverDead, .serverDisconnected: L("Сервер не отвечает. Выберите другой.")
            case .pluginDisabled, .configurationNotFound: L("VPN-профиль Kitsune выключен или удалён.")
            case .pluginFailed: L("VPN не запустился. Попробуйте другой сервер.")
            default: String(format: L("Подключение прервано: %@"), nsError.localizedDescription)
            }
        }
        if let error = error as? ProxyLink.ParseError {
            return switch error {
            case .unsupportedScheme(let scheme): String(format: L("Протокол %@ пока не поддерживается."), scheme)
            case .invalid(let what): String(format: L("Ссылка %@ повреждена."), what)
            }
        }
        if let error = error as? VLESSLink.ParseError {
            return switch error {
            case .notVLESS: L("Это не ссылка vless://.")
            case .missing(let field): String(format: L("В ссылке не хватает параметра %@."), field)
            case .unsupported(let value): String(format: L("Пока не поддерживается: %@."), value)
            }
        }
        return error.localizedDescription
    }

    /// First call shows the system "Add VPN Configuration" prompt.
    #if !os(macOS)
    private func installedManager(name: String) async throws -> NETunnelProviderManager {
        let manager = self.manager ?? NETunnelProviderManager()
        let proto = NETunnelProviderProtocol()
        // Derived from the app's ID so a re-signed build with a new bundle ID still finds its extension.
        proto.providerBundleIdentifier = (Bundle.main.bundleIdentifier ?? "com.kitsune.vpn") + ".PacketTunnel"
        proto.serverAddress = name
        manager.protocolConfiguration = proto
        manager.localizedDescription = "Kitsune"
        manager.isEnabled = true
        try await manager.saveToPreferences()
        try await manager.loadFromPreferences() // required after save before the first start
        self.manager = manager
        await refreshStatus()
        return manager
    }
    #endif
}

#if os(macOS)
// macOS without a signed Network Extension: run the bundled sing-box core as root (TUN needs it).
// The admin password (system prompt from osascript) is asked once; after that sudo may run exactly the installed core.
extension VPNManager {
    /// Last lines of the core's log, colour codes stripped. For the diagnostics screen.
    func coreLogTail(lines: Int = 200) -> String {
        guard let text = try? String(contentsOf: Self.coreDir.appending(path: "core.log"), encoding: .utf8) else { return "" }
        let plain = text.replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression)
        return plain.split(separator: "\n", omittingEmptySubsequences: true).suffix(lines).joined(separator: "\n")
    }

    fileprivate static let coreDir = URL(filePath: NSTemporaryDirectory()).appending(path: "kitsune-core", directoryHint: .isDirectory)

    fileprivate static let helperCore = "/Library/Kitsune/sing-box"

    /// True when the root-owned copy matches the bundled core and sudo can run it without a password.
    private static func helperReady(bundled core: String) async -> Bool {
        func size(_ path: String) -> Int? { (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int }
        guard let installed = size(helperCore), installed == size(core) else { return false }
        return await run("/usr/bin/sudo", ["-n", "-l", helperCore]) == 0
    }

    /// Copies the core to /Library/Kitsune (root-owned, so users can't swap it) and allows this user to sudo it without a password.
    /// Returns an error text, or nil on success. One system password prompt.
    private static func installHelper(core: String) async -> String? {
        let user = NSUserName().filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == "." }
        guard !user.isEmpty else { return L("не удалось определить имя пользователя") }
        let tmp = "/Library/Kitsune/sudoers.tmp"
        let shell = [
            "set -e",
            "mkdir -p /Library/Kitsune /etc/sudoers.d",
            "chown root:wheel /Library/Kitsune; chmod 755 /Library/Kitsune",
            "cp '\(core)' /Library/Kitsune/sing-box.new",
            "chown root:wheel /Library/Kitsune/sing-box.new; chmod 755 /Library/Kitsune/sing-box.new",
            "mv -f /Library/Kitsune/sing-box.new \(helperCore)",
            "printf '%s ALL=(root) NOPASSWD: \(helperCore)\\n' '\(user)' > \(tmp)",
            "chown root:wheel \(tmp); chmod 440 \(tmp)",
            "/usr/sbin/visudo -cf \(tmp) >/dev/null",
            "mv -f \(tmp) /etc/sudoers.d/kitsune",
        ].joined(separator: "; ")
        return await adminScript(shell, prompt: L("Kitsune настраивает доступ к VPN (один раз)"))
    }

    /// Removes the passwordless access again; the next connection asks for the password once more.
    func forgetAdminAccess() async {
        _ = await Self.adminScript("rm -f /etc/sudoers.d/kitsune; rm -rf /Library/Kitsune", prompt: L("Kitsune снова будет спрашивать пароль"))
    }

    private static func adminScript(_ shell: String, prompt: String) async -> String? {
        let escaped = shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges with prompt \"\(prompt)\""
        return await Task.detached { () -> String? in
            let process = Process()
            process.executableURL = URL(filePath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            let pipe = Pipe()
            process.standardError = pipe
            do { try process.run() } catch { return error.localizedDescription }
            process.waitUntilExit()
            return process.terminationStatus == 0 ? nil : String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        }.value
    }

    private static func run(_ executable: String, _ arguments: [String]) async -> Int32 {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(filePath: executable)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { return -1 }
            process.waitUntilExit()
            return process.terminationStatus
        }.value
    }

    fileprivate func connectDirect(_ server: ServerConfig, servers: [ServerConfig], routing: RoutingSettings) async {
        guard status == .disconnected || status == .invalid else { return }
        guard let core = Bundle.main.url(forResource: "sing-box", withExtension: nil)?.path(percentEncoded: false) else {
            lastError = L("В приложении нет ядра sing-box. Скачайте свежую сборку.")
            return
        }
        status = .connecting
        lastConnect = (server, servers, routing)
        let dir = Self.coreDir
        let cfg = dir.appending(path: "config.json"), log = dir.appending(path: "core.log"), flag = dir.appending(path: "run")
        do {
            let config = try Self.config(server, servers: servers, routing: routing)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try config.write(to: cfg, atomically: true, encoding: .utf8)
            FileManager.default.createFile(atPath: flag.path(percentEncoded: false), contents: nil)
            try Data().write(to: log)
            tunnelServerIDs = Set(([server] + servers).map(\.id))
        } catch {
            lastError = Self.describe(error)
            status = .disconnected
            return
        }
        func path(_ url: URL) -> String { url.path(percentEncoded: false) }
        // One admin password, once: the core goes to a root-owned folder and sudo is allowed to run exactly that file.
        if !(await Self.helperReady(bundled: core)) {
            guard await askPasswordConsent() else {
                try? FileManager.default.removeItem(at: cfg)
                try? FileManager.default.removeItem(at: flag)
                status = .disconnected
                return
            }
            if let failure = await Self.installHelper(core: core) {
                lastError = failure.contains("-128") ? L("Установка отменена: не введён пароль администратора.") : String(format: L("Не удалось настроить доступ: %@"), failure)
                try? FileManager.default.removeItem(at: cfg)
                try? FileManager.default.removeItem(at: flag)
                status = .disconnected
                return
            }
        }
        // User-level watcher: starts the core through sudo, stops it when the flag file disappears, the core dies
        // or the app is gone (so a crashed app never leaves a tunnel behind).
        let script = "\(Self.helperCore) run -D '\(path(dir))' -c '\(path(cfg))' >'\(path(log))' 2>&1 & P=$!; "
            + "while [ -e '\(path(flag))' ] && kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null && kill -0 $P 2>/dev/null; do sleep 1; done; "
            + "kill $P 2>/dev/null; wait $P 2>/dev/null; rm -f '\(path(cfg))'"
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = ["-c", "sudo -n " + script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch {
            lastError = String(format: L("Не удалось запустить ядро: %@"), error.localizedDescription)
            status = .disconnected
            return
        }
        coreProcess = process
        for _ in 0..<60 {
            if !process.isRunning { break }
            if await Self.coreAlive() {
                status = .connected
                connectedDate = Date()
                watchCore(log: log)
                return
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        lastError = Self.coreError(log) ?? L("Ядро не запустилось.")
        disconnect()
        status = .disconnected
    }

    private func watchCore(log: URL) {
        monitor?.cancel()
        monitor = Task { [weak self] in
            var misses = 0, uptime = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                misses = await Self.coreAlive() ? 0 : misses + 1
                uptime += 1
                // A connection that held for two minutes earns a fresh set of retries.
                if uptime == 60 { self?.reconnectAttempts = 0 }
                guard misses >= 2, let self else { continue }
                let intentional = self.status == .disconnecting
                let reason = Self.coreError(log) ?? L("Соединение прервано.")
                self.connectedDate = nil
                if !intentional, self.reconnectAttempts < 3, self.lastConnect != nil,
                   UserDefaults.standard.object(forKey: "autoReconnect") as? Bool ?? true {
                    await self.reconnectAfterDrop(reason: reason)
                } else {
                    if !intentional { self.lastError = reason }
                    self.status = .disconnected
                }
                return
            }
        }
    }

    /// The core died by itself: rebuild the tunnel, trying the next server if the same one keeps failing.
    private func reconnectAfterDrop(reason: String) async {
        guard var last = lastConnect else { return }
        reconnectAttempts += 1
        status = .reasserting
        try? FileManager.default.removeItem(at: Self.coreDir.appending(path: "run")) // stop the old watcher
        try? await Task.sleep(for: .seconds(2))
        if reconnectAttempts > 1, let index = last.servers.firstIndex(where: { $0.id == last.server.id }), last.servers.count > 1 {
            last.server = last.servers[(index + 1) % last.servers.count]
        }
        status = .disconnected
        await connectDirect(last.server, servers: last.servers, routing: last.routing)
        if status == .disconnected, lastError == nil { lastError = reason }
        else if status != .disconnected {
            notice = L("Соединение прервалось, туннель восстановлен")
            Task { try? await Task.sleep(for: .seconds(8)); notice = nil }
        }
    }

    private static func coreError(_ log: URL) -> String? {
        let text = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        return text.split(separator: "\n").last { $0.contains("FATAL") || $0.contains("ERROR") }.map(String.init)
    }

    fileprivate static func coreAlive() async -> Bool {
        await coreRequest("version", method: "GET", body: nil)
    }

    @discardableResult
    fileprivate static func coreRequest(_ path: String, method: String, body: [String: String]?) async -> Bool {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(controller.port)/\(path)")!, timeoutInterval: 2)
        request.httpMethod = method
        request.setValue("Bearer \(controller.secret)", forHTTPHeaderField: "Authorization")
        if let body { request.httpBody = try? JSONEncoder().encode(body) }
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
    }
}
#endif
