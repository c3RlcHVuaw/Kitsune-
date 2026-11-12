import Foundation
import UserNotifications
import Network
import Observation
import Shared
import Synchronization

/// A subscription URL and what it last returned.
struct Subscription: Codable, Identifiable {
    var id = UUID()
    var url: URL
    var info = SubscriptionInfo()
    var servers: [ServerConfig] = []
    var updatedAt: Date?
    var lastError: String?
    var skipped = 0
    var collapsed = false

    var name: String { info.title ?? url.host() ?? L("Подписка") }
    var intervalHours: Int { info.updateIntervalHours ?? 12 }
    var isDue: Bool { updatedAt.map { Date().timeIntervalSince($0) > Double(intervalHours) * 3600 } ?? true }
}

enum Ping: Equatable {
    case measuring
    /// TLS handshake straight to the server: reachability only.
    case ms(Int)
    /// Full HTTPS request through the server inside the running tunnel: the real latency.
    case tunnel(Int)
    case failed, unavailable

    var milliseconds: Int? {
        switch self {
        case .ms(let ms), .tunnel(let ms): ms
        default: nil
        }
    }
}

/// Servers, subscriptions, the selected server and routing. Links carry secrets, so they live in the Keychain.
@MainActor @Observable
final class Library {
    private(set) var subscriptions: [Subscription] = []
    private(set) var manual: [ServerConfig] = []
    private(set) var updating: Set<UUID> = []
    private(set) var pings: [String: Ping] = [:]
    /// Last measurements per server (milliseconds, oldest first), for the mini graph.
    private(set) var pingHistory: [String: [Int]] = [:]
    /// Servers the user pinned to the top of every list. Not secret, so plain defaults.
    var pinned: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "pinnedServers") ?? []) {
        didSet { UserDefaults.standard.set(Array(pinned), forKey: "pinnedServers") }
    }
    /// The last servers actually connected, newest first.
    private(set) var recent: [String] = UserDefaults.standard.stringArray(forKey: "recentServers") ?? []
    /// True while the active server answers much slower than it did a few minutes ago.
    var slowAlert = false
    /// Servers that did not answer the last three checks in a row; the list shows them dimmed.
    private(set) var silent: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "silentServers") ?? [])
    private var failStreak: [String: Int] = [:]
    /// A clearly faster server found by the daily check, offered once on the Servers screen.
    var betterHint: (server: ServerConfig, saved: Int)?
    var selectedID: String? { didSet { UserDefaults.standard.set(selectedID, forKey: "selectedServer"); slowAlert = false } }
    var routing: RoutingSettings { didSet { saveRouting() } }
    /// Set by the root view; used to measure through the running tunnel.
    weak var vpn: VPNManager?

    private struct Stored: Codable {
        var subscriptions: [Subscription]
        var manual: [ServerConfig]
    }

    init() {
        routing = (UserDefaults.standard.data(forKey: "routing")).flatMap { try? JSONDecoder().decode(RoutingSettings.self, from: $0) } ?? RoutingSettings()
        selectedID = UserDefaults.standard.string(forKey: "selectedServer")
        if let data = Keychain.string("library")?.data(using: .utf8), let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            subscriptions = stored.subscriptions
            manual = stored.manual
        } else if let legacy = Keychain.string("serverLink"), let server = try? ProxyLink.parse(legacy) {
            manual = [server] // stage 2 kept a single link
            selectedID = server.id
            save()
        }
    }

    // MARK: Queries

    var allServers: [ServerConfig] { manual + subscriptions.flatMap(\.servers) }
    var isEmpty: Bool { manual.isEmpty && subscriptions.isEmpty }

    /// The chosen server, falling back to the first one if it disappeared from a subscription.
    var selected: ServerConfig? {
        allServers.first { $0.id == selectedID } ?? allServers.first
    }

    // MARK: Servers

    @discardableResult
    func add(link: String) throws -> ServerConfig {
        let server = try ProxyLink.parse(link)
        if !manual.contains(where: { $0.id == server.id }) { manual.append(server) }
        if selected == nil || selectedID == nil { selectedID = server.id }
        save()
        return server
    }

    func replace(_ old: ServerConfig, link: String) throws {
        let server = try ProxyLink.parse(link)
        guard let index = manual.firstIndex(where: { $0.id == old.id }) else { return }
        manual[index] = server
        if selectedID == old.id { selectedID = server.id }
        save()
    }

    func remove(_ server: ServerConfig) {
        manual.removeAll { $0.id == server.id }
        save()
    }

    /// Adds a server link or a subscription URL, whichever the text is.
    func add(any text: String) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if let url = URL(string: trimmed), ["http", "https"].contains(url.scheme?.lowercased()) {
                try await addSubscription(url)
            } else {
                try add(link: trimmed)
            }
        } catch let error as SubscriptionError {
            throw error
        } catch {
            throw SubscriptionError(message: VPNManager.describe(error))
        }
    }

    // MARK: Subscriptions

    func addSubscription(_ url: URL) async throws {
        guard !subscriptions.contains(where: { $0.url == url }) else { return }
        let subscription = Subscription(url: url)
        subscriptions.append(subscription)
        save()
        await refresh(subscription.id)
        if let error = subscriptions.first(where: { $0.id == subscription.id })?.lastError, subscriptions.first(where: { $0.id == subscription.id })?.servers.isEmpty == true {
            subscriptions.removeAll { $0.id == subscription.id }
            save()
            throw SubscriptionError(message: error)
        }
    }

    func refresh(_ id: UUID) async {
        guard let url = subscriptions.first(where: { $0.id == id })?.url, !updating.contains(id) else { return }
        updating.insert(id)
        defer { updating.remove(id) }
        do {
            var request = URLRequest(url: url, timeoutInterval: 20)
            request.setValue("Kitsune/\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0")", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw SubscriptionError(message: "Нет ответа от сервера") }
            guard (200..<300).contains(http.statusCode) else { throw SubscriptionError(message: String(format: L("Сервер ответил %lld"), http.statusCode)) }
            let (servers, skipped) = SubscriptionParser.servers(from: data)
            guard !servers.isEmpty else { throw SubscriptionError(message: "В подписке нет поддерживаемых серверов") }
            let headers = Dictionary(http.allHeaderFields.compactMap { key, value in (key as? String).map { ($0, "\(value)") } }, uniquingKeysWith: { _, last in last })
            update(id) {
                $0.servers = servers
                $0.skipped = skipped
                $0.info = SubscriptionInfo.parse(headers: headers)
                $0.updatedAt = .now
                $0.lastError = nil
            }
            if let updated = subscriptions.first(where: { $0.id == id }) { await Self.notifyIfRunningOut(updated) }
        } catch {
            // Keep the last good server list; only record the failure.
            update(id) { $0.lastError = (error as? SubscriptionError)?.message ?? error.localizedDescription }
        }
    }

    /// A local notification (at most once a day per subscription) when it expires within 3 days or most of its traffic is used.
    private static func notifyIfRunningOut(_ subscription: Subscription) async {
        let info = subscription.info
        var problem: String?
        if let expire = info.expire, expire.timeIntervalSinceNow < 3 * 86_400 {
            problem = expire < .now ? L("Подписка закончилась") : L("Подписка скоро закончится")
        } else if let total = info.total, total > 0, let used = info.used, Double(used) / Double(total) > 0.9 {
            problem = L("Трафик подписки почти израсходован")
        }
        guard let problem, UserDefaults.standard.object(forKey: "notifications") as? Bool ?? true else { return }
        let key = "notified-\(subscription.id)"
        let today = Calendar.current.startOfDay(for: .now).timeIntervalSince1970
        guard UserDefaults.standard.double(forKey: key) < today else { return }
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        let content = UNMutableNotificationContent()
        content.title = problem
        content.body = subscription.name
        try? await center.add(UNNotificationRequest(identifier: key, content: content, trigger: nil))
        UserDefaults.standard.set(today + 1, forKey: key)
    }

    func refreshDue() async {
        for subscription in subscriptions where subscription.isDue {
            await refresh(subscription.id)
        }
    }

    func remove(_ subscription: Subscription) {
        subscriptions.removeAll { $0.id == subscription.id }
        save()
    }

    func toggleCollapsed(_ id: UUID) {
        update(id) { $0.collapsed.toggle() }
    }

    // MARK: Ping

    /// Through the tunnel when it's up (real latency, any protocol); otherwise a TLS handshake straight to the server.
    func ping(_ servers: [ServerConfig]) async {
        let tunnelIDs = vpn?.status == .connected ? vpn?.tunnelServerIDs ?? [] : []
        let viaTunnel = servers.filter { tunnelIDs.contains($0.id) }
        let direct = servers.filter { !tunnelIDs.contains($0.id) }
        for server in viaTunnel { pings[server.id] = .measuring }
        for server in direct { pings[server.id] = server.isUDP ? .unavailable : .measuring }
        async let tunnel: Void = pingThroughTunnel(viaTunnel)
        async let handshake: Void = pingDirect(direct)
        _ = await (tunnel, handshake)
        for server in servers { track(server.id, pings[server.id]) }
    }

    private func track(_ id: String, _ ping: Ping?) {
        switch ping {
        case .failed:
            failStreak[id, default: 0] += 1
            if failStreak[id]! >= 3, silent.insert(id).inserted { UserDefaults.standard.set(Array(silent), forKey: "silentServers") }
        case .some(.unavailable), .some(.measuring), .none: break
        default:
            failStreak[id] = 0
            if silent.remove(id) != nil { UserDefaults.standard.set(Array(silent), forKey: "silentServers") }
        }
    }

    /// Once a day: measure a spread of servers (pinned, recent, one per country) and remember a much faster one.
    func checkBetterIfDue() async {
        let key = "betterCheck"
        guard Date.now.timeIntervalSince1970 - UserDefaults.standard.double(forKey: key) > 20 * 3600,
              let current = selected, vpn?.status != .connecting else { return }
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: key)
        var seenCountries: Set<String> = []
        let spread = allServers.filter { s in s.countryCode.map { seenCountries.insert($0).inserted } ?? false }
        let candidates = Array(Set(([current] + allServers.filter { pinned.contains($0.id) || recent.contains($0.id) } + spread).map(\.id)))
            .compactMap { id in allServers.first { $0.id == id } }
        await ping(candidates)
        guard let now = pings[current.id]?.milliseconds,
              let best = candidates.compactMap({ s in pings[s.id]?.milliseconds.map { (s, $0) } }).min(by: { $0.1 < $1.1 }),
              best.0.id != current.id, best.1 + 40 <= now, Double(best.1) <= Double(now) * 0.7 else { return }
        betterHint = (best.0, now - best.1)
    }

    private func pingThroughTunnel(_ servers: [ServerConfig]) async {
        guard !servers.isEmpty else { return }
        let delays = await vpn?.tunnelDelays()
        for server in servers {
            pings[server.id] = delays?[server.id].map(Ping.tunnel) ?? .failed
            if let ms = delays?[server.id] { record(server.id, ms) }
        }
    }

    /// TLS handshake time (TCP when the server has no TLS), measured in parallel.
    /// A bare TCP connect lies: local proxies and our own tunnel accept it instantly. QUIC servers can't be measured this way.
    private func pingDirect(_ servers: [ServerConfig]) async {
        await withTaskGroup(of: (String, Int?).self) { group in
            for server in servers where !server.isUDP {
                let sni = Self.serverName(server)
                group.addTask { (server.id, await Self.handshakePing(host: server.host, port: server.port, sni: sni)) }
            }
            for await (id, ms) in group {
                pings[id] = ms.map(Ping.ms) ?? .failed
                if let ms { record(id, ms) }
            }
        }
    }

    func markRecent(_ id: String) {
        recent = Array(([id] + recent.filter { $0 != id }).prefix(3))
        UserDefaults.standard.set(recent, forKey: "recentServers")
    }

    /// Another server to move to when this one is slow: the best measured one, otherwise simply the next in the list.
    func alternative(to current: ServerConfig) -> ServerConfig? {
        let others = allServers.filter { $0.id != current.id }
        return others.compactMap { s in pings[s.id]?.milliseconds.map { (s, $0) } }.min { $0.1 < $1.1 }?.0
            ?? allServers.firstIndex(where: { $0.id == current.id }).flatMap { allServers.isEmpty ? nil : allServers[($0 + 1) % allServers.count] }
    }

    /// Slow = the last three samples are more than twice the earlier typical value and above half a second.
    private func checkSlow(_ id: String) {
        guard let samples = pingHistory[id], samples.count >= 8 else { return }
        let earlier = samples.dropLast(3).sorted()
        let baseline = earlier[earlier.count / 2]
        let recentAverage = samples.suffix(3).reduce(0, +) / 3
        if recentAverage > baseline * 2, recentAverage > 500 {
            if !slowAlert { slowAlert = true; Task { await Self.notifySlow() } }
        } else if recentAverage < baseline * 3 / 2 {
            slowAlert = false
        }
    }

    private static func notifySlow() async {
        guard UserDefaults.standard.object(forKey: "notifications") as? Bool ?? true else { return }
        let key = "notified-slow"
        guard Date.now.timeIntervalSince1970 - UserDefaults.standard.double(forKey: key) > 1800 else { return }
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        let content = UNMutableNotificationContent()
        content.title = L("Сервер тормозит")
        content.body = L("Откройте Kitsune и смените сервер.")
        try? await center.add(UNNotificationRequest(identifier: key, content: content, trigger: nil))
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: key)
    }

    private func record(_ id: String, _ ms: Int) {
        pingHistory[id] = Array((pingHistory[id] ?? []).suffix(23) + [ms])
        PingStats.record(id, ms)
    }

    /// Real round trip through the running tunnel for the selected server: one tiny request, so it is cheap enough to repeat.
    func sampleActive() async {
        guard vpn?.status == .connected, let id = selected?.id else { return }
        var request = URLRequest(url: URL(string: "https://www.gstatic.com/generate_204")!, timeoutInterval: 5)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let start = ContinuousClock.now
        let ok = (try? await URLSession.shared.data(for: request)) != nil
        let elapsed = start.duration(to: .now).components
        let ms = Int(elapsed.seconds * 1000 + elapsed.attoseconds / 1_000_000_000_000_000)
        if ok { pings[id] = .tunnel(ms); record(id, ms); checkSlow(id) } else { pings[id] = .failed }
        track(id, pings[id])
    }

    /// Picks the server with the lowest ping among those measured.
    func selectFastest(in servers: [ServerConfig]) {
        let best = servers.compactMap { server -> (String, Int)? in
            pings[server.id]?.milliseconds.map { (server.id, $0) }
        }.min { $0.1 < $1.1 }
        if let best { selectedID = best.0 }
    }

    /// TLS server name from the outbound, or nil for plain servers.
    private static func serverName(_ server: ServerConfig) -> String? {
        guard let outbound = try? JSONSerialization.jsonObject(with: Data(server.outbound.utf8)) as? [String: Any],
              let tls = outbound["tls"] as? [String: Any], tls["enabled"] as? Bool == true
        else { return nil }
        return tls["server_name"] as? String ?? server.host
    }

    nonisolated static func handshakePing(host: String, port: Int, sni: String?, timeout: Double = 4) async -> Int? {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else { return nil }
        let parameters: NWParameters
        if let sni {
            let tls = NWProtocolTLS.Options()
            sec_protocol_options_set_tls_server_name(tls.securityProtocolOptions, sni)
            // Only timing matters; Reality and self-signed servers would fail normal validation.
            sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, _, complete in complete(true) }, .global())
            parameters = NWParameters(tls: tls)
        } else {
            parameters = .tcp
        }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: parameters)
        let start = ContinuousClock.now
        let done = Mutex(false)
        return await withCheckedContinuation { continuation in
            let finish: @Sendable (Int?) -> Void = { result in
                guard done.withLock({ old in defer { old = true }; return !old }) else { return }
                connection.cancel()
                continuation.resume(returning: result)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let elapsed = ContinuousClock.now - start
                    finish(Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000))
                case .failed, .waiting, .cancelled: finish(nil)
                default: break
                }
            }
            connection.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { finish(nil) }
        }
    }

    // MARK: Persistence

    private func update(_ id: UUID, _ change: (inout Subscription) -> Void) {
        guard let index = subscriptions.firstIndex(where: { $0.id == id }) else { return }
        change(&subscriptions[index])
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(Stored(subscriptions: subscriptions, manual: manual)) else { return }
        Keychain.set(String(decoding: data, as: UTF8.self), for: "library")
    }

    private func saveRouting() {
        UserDefaults.standard.set(try? JSONEncoder().encode(routing), forKey: "routing")
    }
}

struct SubscriptionError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
