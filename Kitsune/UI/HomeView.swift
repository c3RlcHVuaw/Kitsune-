import Charts
import NetworkExtension
#if os(macOS)
import AppKit
#endif
import Shared
import SwiftUI

/// Main screen: typographic hero (status word / session timer), details, one bar button.
struct HomeView: View {
    let vpn: VPNManager
    let library: Library
    @Binding var tab: AppTab
    #if os(macOS)
    @State private var showDiagnostics = false
    @AppStorage("sounds") private var sounds = true
    @AppStorage("haptics") private var haptics = true
    #endif

    @AppStorage("buttonTheme") private var themeRaw = "copper"
    @AppStorage("winterMode") private var winterMode = true
    @State private var check = ConnectionCheck()
    @State private var taps = 0
    @State private var flip = 0

    private var theme: ButtonTheme { ButtonTheme(rawValue: themeRaw) ?? .copper }
    private var server: ServerConfig? { library.selected }

    /// Ring colour follows the real latency through the tunnel: theme colour is fine, amber so-so, red bad.
    private var ringColor: Color {
        guard vpn.status == .connected, let server, let ping = library.pings[server.id] else { return theme.accent }
        switch ping {
        case .tunnel(let ms): return ms < 600 ? theme.accent : ms < 1500 ? Color(red: 1.0, green: 0.80, blue: 0.25) : Color(red: 0.92, green: 0.22, blue: 0.22)
        case .failed: return Color(red: 0.92, green: 0.22, blue: 0.22)
        default: return theme.accent
        }
    }
    private var hasError: Bool { vpn.lastError != nil && !vpn.status.isActive }

    var body: some View {
        Group {
            VStack(spacing: 0) {
                ZStack {
                #if os(macOS)
                HStack {
                    Spacer()
                    Button("Диагностика", systemImage: "stethoscope") { showDiagnostics = true }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .opacity(0.8)
                }
                #endif
                Text("kitsune")
                    .font(.display(15, relativeTo: .headline))
                    .onTapGesture { taps += 1; if taps % 7 == 0 { flip += 1 } }
                    .accessibilityAddTraits(.isHeader)
                }
                .padding(.top, 8)
                #if os(macOS)
                ClipboardOffer(library: library).padding(.top, 10)
                #endif
                Spacer(minLength: 16)
                ConnectButton(status: vpn.status, theme: theme, ring: ringColor, winter: winterMode && Snow.isSeason, error: hasError, action: toggle, flip: flip)
                StatusCaption(status: vpn.status, hasError: hasError, server: server, connectedDate: vpn.connectedDate) {
                    tab = .servers
                }
                .padding(.top, 28)
                if vpn.status == .connected, !hasError {
                    VStack(spacing: 8) {
                        CheckChip(state: check.state)
                        LiveLine(vpn: vpn, library: library, server: server)
                    }
                    .padding(.top, 6)
                }
                Group {
                    if let error = vpn.lastError, hasError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(Color.alert)
                            .multilineTextAlignment(.leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .glassEffect(.regular, in: .rect(cornerRadius: 18))
                    } else if vpn.status == .connected, let server {
                        GlassEffectContainer(spacing: 12) {
                            VStack(spacing: 12) {
                                ConnectionInfo(server: server).appear(0)
                                SpeedRow(vpn: vpn, accent: theme.accent).appear(1)
                            }
                        }
                    }
                }
                .padding(.top, 20)
                .transition(.blurReplace)
                Spacer(minLength: 16)
                ProfileChip(profile: Binding(get: { library.routing.profile }, set: { library.routing.profile = $0 }))
                    .padding(.bottom, 12)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
        }
        .animation(.smooth, value: vpn.status)
        .animation(.smooth, value: hasError)
        .sensoryFeedback(trigger: vpn.status) { _, new in
            switch new {
            case .connected: .success
            case .disconnected: hasError ? .error : .impact(weight: .light)
            default: nil
            }
        }
        .onChange(of: server?.id) { vpn.clearError() }
        .onChange(of: vpn.status) { _, new in
            switch new {
            case .connecting: check.prepare()
            case .connected: Task { await check.verify() }
            case .disconnected, .invalid: check.reset()
            default: break
            }
        }
        #if os(macOS)
        .onChange(of: vpn.status) { old, new in
            // Soft system sounds on connect and on a user-driven disconnect.
            if haptics {
                // A quiet click on connect, a firmer one when the tunnel drops by itself (only felt while a finger is on the trackpad).
                let performer = NSHapticFeedbackManager.defaultPerformer
                if new == .connected { performer.perform(.alignment, performanceTime: .now) }
                else if new == .disconnected, old != .disconnecting { performer.perform(.levelChange, performanceTime: .now) }
            }
            guard sounds else { return }
            if new == .connected { NSSound(named: "Glass")?.play() }
            else if new == .disconnected, old == .disconnecting { NSSound(named: "Pop")?.play() }
        }
        .sheet(isPresented: $showDiagnostics) { DiagnosticsView(vpn: vpn, server: server?.displayName) }
        #endif
    }

    private func toggle() {
        if vpn.status.isActive {
            vpn.disconnect()
        } else if let server {
            Task { await vpn.connect(server, servers: library.allServers, routing: library.routing) }
        } else {
            tab = .servers
        }
    }
}

// MARK: - Connect button

/// Dark glass disc with the fox; a copper ring spins while busy and closes when connected, the disc fills with copper.
private struct ConnectButton: View {
    let status: NEVPNStatus
    let theme: ButtonTheme
    let ring: Color
    let winter: Bool
    let error: Bool
    var action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = false
    @State private var burst: Date?
    @State private var sway: CGFloat = 0
    @State private var twitch: CGFloat = 0
    @State private var flipAngle = 0.0
    /// Bumped by the home screen when the wordmark is tapped seven times.
    var flip = 0

    private var copper: Color { theme.accent }
    private var busy: Bool { status == .connecting || status == .disconnecting || status == .reasserting }
    private var connected: Bool { status == .connected }

    var body: some View {
        Button(action: action) {
            ZStack {
                if connected && !reduceMotion {
                    Circle()
                        .stroke(copper.opacity(0.5), lineWidth: 1.5)
                        .phaseAnimator([false, true]) { view, grown in
                            view.scaleEffect(grown ? 1.35 : 1).opacity(grown ? 0 : 1)
                        } animation: { _ in .easeOut(duration: 2.2) }
                }
                Circle()
                    .trim(from: 0, to: connected ? 1 : busy ? 0.3 : 0)
                    .stroke(ring, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .padding(-14)
                    .animation(.smooth(duration: 0.8), value: ring)
                Circle()
                    .fill(connected
                          ? AnyShapeStyle(copper.opacity(0.18))
                          : AnyShapeStyle(LinearGradient(colors: [.white.opacity(0.09), .white.opacity(0.03)], startPoint: .top, endPoint: .bottom)))
                    .overlay(Circle().stroke(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.05), copper.opacity(0.4)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
                    .shadow(color: copper.opacity(connected ? 0.55 : busy ? 0.3 : 0.12), radius: connected ? 46 : 28)
                    .shadow(color: .black.opacity(0.5), radius: 18, y: 10)
                    .glassEffect(connected ? .regular.tint(copper.opacity(0.45)) : .regular, in: .circle)
                    .animation(.smooth(duration: 0.8), value: status)
                FoxMark(color: connected ? .white : theme.soft, droop: error ? 1 : 0, sway: sway, twitch: twitch)
                    .animation(.smooth(duration: 0.5), value: error)
                    .rotation3DEffect(.degrees(flipAngle), axis: (x: 0, y: 1, z: 0))
                    .frame(width: 88)
                    .offset(y: 4)
                    .phaseAnimator([false, true], trigger: connected) { view, phase in
                        view.offset(y: phase && connected && !reduceMotion ? -8 : 0)
                    } animation: { _ in .spring(duration: 0.35, bounce: 0.5) }
            }
            .overlay { if winter { SnowCap().padding(1) } }
            .overlay { if winter { Snow().frame(width: 260, height: 300) } }
            .overlay { SparkBurst(start: burst, colors: [theme.accent, theme.soft, .white]).frame(width: 420, height: 420) }
            .frame(width: 200, height: 200)
            .contentShape(.circle)
            .phaseAnimator(!busy && !connected && !reduceMotion ? [1.0, 1.035] : [1.0]) { view, scale in
                view.scaleEffect(scale)
            } animation: { _ in .easeInOut(duration: 1.8) }
        }
        .buttonStyle(PressScale())
        .task {
            // The fox lives its own life: now and then an ear flicks.
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: 7...16)))
                guard !error, !busy else { continue }
                for value in [1, 0, 1, 0] as [CGFloat] {
                    withAnimation(.easeInOut(duration: 0.09)) { twitch = value }
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
        }
        .onChange(of: flip) {
            guard !reduceMotion else { return }
            withAnimation(.spring(duration: 0.9, bounce: 0.25)) { flipAngle = 360 }
            Task { try? await Task.sleep(for: .seconds(1)); flipAngle = 0 }
        }
        .onChange(of: connected) { _, isConnected in
            guard isConnected, !reduceMotion else { return }
            burst = .now
            // The ears wiggle a few times: the fox is happy.
            Task {
                for lean in [1, -1, 0.8, -0.8, 0.5, -0.5, 0] as [CGFloat] {
                    withAnimation(.easeInOut(duration: 0.11)) { sway = lean }
                    try? await Task.sleep(for: .milliseconds(110))
                }
            }
        }
        .onChange(of: busy, initial: true) { _, isBusy in
            guard !reduceMotion else { return }
            if isBusy {
                withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { spin = true }
            } else {
                withAnimation(.default) { spin = false }
            }
        }
        .accessibilityLabel(status.isActive ? L("Отключить VPN") : L("Подключить VPN"))
    }
}

private struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

// MARK: - Status

/// "Подключить" / "Защищено" with the server (tap to change) and the session timer.
private struct StatusCaption: View {
    let status: NEVPNStatus
    let hasError: Bool
    let server: ServerConfig?
    let connectedDate: Date?
    var onServerTap: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.display(24, relativeTo: .largeTitle))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .contentTransition(.opacity)
            Button(action: onServerTap) {
                HStack(spacing: 6) {
                    if let flag = server?.flag { Text(flag) }
                    Text(server?.displayName ?? L("Добавьте сервер"))
                    if status == .connected, let connectedDate {
                        Text("·")
                        Text(connectedDate, style: .timer).monospacedDigit()
                    }
                    Image(systemName: "chevron.right").font(.caption.weight(.bold))
                }
                .font(.subheadline)
                .opacity(0.9)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Открыть список серверов")
        }
        .multilineTextAlignment(.center)
    }

    private var title: String {
        if hasError { return L("Ошибка подключения") }
        return switch status {
        case .connected: L("Защищено")
        case .connecting, .reasserting: L("Подключение…")
        case .disconnecting: L("Отключение…")
        default: L("Подключить")
        }
    }
}

// MARK: - Chips

/// On: Russia direct (filled white). Off: everything through VPN. The custom profile lives on the Routes tab.
private struct ProfileChip: View {
    @Binding var profile: RoutingSettings.Profile
    private var on: Bool { profile == .russiaDirect }

    var body: some View {
        Button {
            withAnimation(.smooth) { profile = on ? .allVPN : .russiaDirect }
        } label: {
            Label("Россия напрямую", systemImage: on ? "checkmark" : "arrow.triangle.branch")
                .symbolEffect(.bounce, value: on)
                .contentTransition(.symbolEffect(.replace))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(on ? Color(red: 0.96, green: 0.80, blue: 0.62) : .white.opacity(0.7))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(on ? Color(red: 1.0, green: 0.50, blue: 0.10).opacity(0.18) : .clear, in: .capsule)
                .overlay(Capsule().stroke(on ? Color(red: 1.0, green: 0.50, blue: 0.10).opacity(0.5) : .white.opacity(0.15), lineWidth: 0.6))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .sensoryFeedback(.selection, trigger: on)
        .accessibilityValue(on ? L("Включено") : L("Выключено"))
        .accessibilityHint("Российские сайты без VPN")
    }
}

// MARK: - Connection info

/// The IP and country sites see, asked through the tunnel.
private struct ConnectionInfo: View {
    let server: ServerConfig

    @State private var exit: ExitIP?
    @State private var failed = false
    @State private var copied = false

    private struct ExitIP: Decodable { let ip: String; let country: String }

    var body: some View {
        HStack(spacing: 12) {
            if let exit {
                Text(flag(exit.country)).font(.title2)
                Button {
                    Clipboard.copy(exit.ip)
                    withAnimation(.smooth) { copied = true }
                    Task { try? await Task.sleep(for: .seconds(1.6)); withAnimation(.smooth) { copied = false } }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exit.ip).font(.headline.monospacedDigit()).contentTransition(.numericText()).animation(.smooth(duration: 0.9), value: exit.ip)
                        Label(copied ? L("Скопировано") : (Locale.current.localizedString(forRegionCode: exit.country) ?? exit.country),
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                            .labelStyle(.titleAndIcon)
                            .font(.footnote)
                            .opacity(0.8)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.success, trigger: copied) { _, new in new }
                .accessibilityHint("Скопировать IP-адрес")
            } else if failed {
                Button { Task { await lookup() } } label: {
                    Label("IP не определён · повторить", systemImage: "arrow.clockwise").font(.subheadline)
                }
                .buttonStyle(.plain)
            } else {
                ProgressView().tint(.white)
                Text("Определяем IP…").font(.subheadline)
            }
            Spacer(minLength: 0)
            Text("Сайты видят").font(.caption).opacity(0.8)
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
        .task(id: server.id) { await lookup() }
    }

    private func lookup() async {
        failed = false // the old address stays until the new one arrives, so the digits roll
        // Right after connecting the routes are still switching: a hard 6 s cap per try, a second service, a few retries.
        for attempt in 0..<4 {
            for endpoint in Self.endpoints {
                if let found = await Self.fetch(endpoint) {
                    withAnimation(.smooth(duration: 0.9)) { exit = found }
                    return
                }
                if Task.isCancelled { return }
            }
            if attempt < 3 { try? await Task.sleep(for: .seconds(2)) }
        }
        failed = true
    }

    private static let endpoints = ["https://api.country.is/", "https://ipwho.is/"]

    /// A real deadline: URLSession's own timeout only measures silence and can let a stalled connection hang.
    private static func fetch(_ endpoint: String) async -> ExitIP? {
        await withTaskGroup(of: ExitIP?.self) { group in
            group.addTask {
                var request = URLRequest(url: URL(string: endpoint)!, timeoutInterval: 6)
                request.cachePolicy = .reloadIgnoringLocalCacheData
                guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
                if let exit = try? JSONDecoder().decode(ExitIP.self, from: data) { return exit }
                return (try? JSONDecoder().decode(Whois.self, from: data)).map { ExitIP(ip: $0.ip, country: $0.country_code) }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(7))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private struct Whois: Decodable { let ip: String; let country_code: String }

    private func flag(_ code: String) -> String {
        String(String.UnicodeScalarView(code.uppercased().unicodeScalars.compactMap { Unicode.Scalar(0x1F1A5 + $0.value) }))
    }
}

// MARK: - Connection check

/// A short green tick (or amber hint) right after connecting; it fades away by itself.
private struct CheckChip: View {
    let state: ConnectionCheck.State

    var body: some View {
        Group {
            switch state {
            case .idle: EmptyView()
            case .running:
                Label { Text("Проверяем соединение…") } icon: { ProgressView().controlSize(.mini) }
            case .ok(let text):
                Label(text, systemImage: "checkmark.circle.fill").foregroundStyle(Color(red: 0.45, green: 0.90, blue: 0.55))
            case .warn(let text):
                Label(text, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.30))
            }
        }
        .font(.footnote.weight(.medium))
        .transition(.blurReplace)
        .animation(.smooth, value: state)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Live line

/// One quiet line under the status that cycles: exit country, routing profile, current speed, time protected today.
private struct LiveLine: View {
    let vpn: VPNManager
    let library: Library
    let server: ServerConfig?
    @State private var index = 0

    private var lines: [String] {
        var result: [String] = []
        if let code = server?.countryCode, let name = Locale.current.localizedString(forRegionCode: code) { result.append(String(format: L("Выход: %@"), name)) }
        let profile = switch library.routing.profile {
        case .russiaDirect: L("Россия напрямую")
        case .allVPN: L("Весь трафик через VPN")
        case .custom: L("Свои правила")
        }
        result.append(profile)
        result.append(String(format: L("Скорость %@"), ByteCountFormatter.string(fromByteCount: vpn.downRate + vpn.upRate, countStyle: .binary) + L("/с")))
        result.append(String(format: L("Сегодня под защитой: %@"), todayText))
        return result
    }

    private var todayText: String {
        let start = Calendar.current.startOfDay(for: .now)
        var seconds = History.sessions.filter { $0.start >= start }.reduce(0) { $0 + $1.duration }
        if let date = vpn.connectedDate { seconds += Date.now.timeIntervalSince(max(date, start)) }
        let s = Int(seconds), h = s / 3600, m = s % 3600 / 60
        return h > 0 ? String(format: L("%lld ч %lld мин"), h, m) : String(format: L("%lld мин"), max(m, 1))
    }

    var body: some View {
        let all = lines
        Text(all[index % all.count])
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.6))
            .id(index % all.count)
            .transition(.blurReplace)
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(4))
                    withAnimation(.smooth(duration: 0.6)) { index += 1 }
                }
            }
    }
}

// MARK: - Live speed

/// Live speed: rolling down/up rates on top, a 60-second area chart below, session totals at the bottom.
private struct SpeedRow: View {
    let vpn: VPNManager
    let accent: Color
    private var down: Color { accent }
    private let up = Color.white

    private struct Point: Identifiable { let id: Int; let down: Double; let up: Double }
    private var points: [Point] {
        let d = vpn.downHistory, u = vpn.upHistory
        return d.indices.map { Point(id: 60 - d.count + $0, down: Double(d[$0]), up: Double(u.indices.contains($0) ? u[$0] : 0)) }
    }
    /// Average of the last 8 seconds: the placeholder wave returns when traffic calms down, and stays faintly behind real traffic.
    private var recent: Int64 { (vpn.downHistory.suffix(8).reduce(0, +) + vpn.upHistory.suffix(8).reduce(0, +)) / 8 }
    private var peak: Int64 { max(vpn.downHistory.max() ?? 0, vpn.upHistory.max() ?? 0) }

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top) {
                rate("arrow.down", vpn.downRate, down)
                Spacer()
                VStack(spacing: 2) {
                    Text("пик").font(.caption2).foregroundStyle(.secondary)
                    Text(Self.rate(peak)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Spacer()
                rate("arrow.up", vpn.upRate, up)
            }
            ZStack {
            IdleWave(strength: max(0.3, 1 - Double(recent) / 400_000), accent: accent).frame(height: 70)
            Chart(points) { p in
                AreaMark(x: .value("t", p.id), y: .value("down", p.down), series: .value("s", "down"))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(LinearGradient(colors: [down.opacity(0.55), down.opacity(0)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("t", p.id), y: .value("down", p.down), series: .value("s", "down"))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(down)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                LineMark(x: .value("t", p.id), y: .value("up", p.up), series: .value("s", "up"))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(up.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
            .chartXScale(domain: 0...59)
            .chartYScale(domain: 0...Double(max(peak, 100_000)) * 1.15) // calm line, not noise, when nothing moves
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 70)
            .animation(.smooth(duration: 0.6), value: vpn.downHistory)
            }
            HStack {
                Text(L("за сессию ") + Self.bytes(vpn.downTotal)).foregroundStyle(down)
                Spacer()
                Text(L("за сессию ") + Self.bytes(vpn.upTotal)).foregroundStyle(.secondary)
            }
            .font(.caption.monospacedDigit())
            .contentTransition(.numericText())
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }

    private func rate(_ icon: String, _ value: Int64, _ color: Color) -> some View {
        Label(Self.rate(value), systemImage: icon)
            .font(.headline.monospacedDigit())
            .foregroundStyle(color)
            .contentTransition(.numericText())
            .animation(.smooth(duration: 0.3), value: value)
    }

    private static func bytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .binary) }
    private static func rate(_ value: Int64) -> String { bytes(value) + L("/с") }
}

/// Calm placeholder while the tunnel is quiet: two slow glowing waves that fade out as real traffic appears.
private struct IdleWave: View {
    let strength: Double
    let accent: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: reduceMotion || strength < 0.02)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                for (index, color) in [accent, Color.white].enumerated() {
                    var line = Path()
                    let k = Double(index)
                    for x in stride(from: 0.0, through: size.width, by: 3) {
                        let u = x / size.width
                        let envelope = sin(u * .pi) // calm at both ends
                        let y = size.height * (0.62 - 0.2 * envelope * sin(u * (5 + k * 2) + t * (0.9 + k * 0.5) + k * 2) - 0.08 * envelope * sin(u * 11 - t * 0.7))
                        if x == 0 { line.move(to: CGPoint(x: x, y: y)) } else { line.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    var area = line
                    area.addLine(to: CGPoint(x: size.width, y: size.height))
                    area.addLine(to: CGPoint(x: 0, y: size.height))
                    ctx.fill(area, with: .linearGradient(Gradient(colors: [color.opacity(k == 0 ? 0.28 : 0.1), .clear]),
                                                         startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                    ctx.stroke(line, with: .color(color.opacity(k == 0 ? 0.8 : 0.35)), style: StrokeStyle(lineWidth: k == 0 ? 2 : 1.2, lineCap: .round))
                }
            }
        }
        .opacity(strength)
        .animation(.smooth(duration: 0.8), value: strength)
        .accessibilityHidden(true)
    }
}

#if os(macOS)
/// Offers to add a server link that is sitting in the clipboard.
private struct ClipboardOffer: View {
    let library: Library
    @State private var link: String?
    @State private var dismissedChange = -1
    @State private var failed = false

    private static let schemes = ["vless://", "hysteria2://", "hy2://", "trojan://", "vmess://", "ss://"]

    var body: some View {
        Group {
            if let link {
                HStack(spacing: 10) {
                    Image(systemName: failed ? "exclamationmark.triangle" : "doc.on.clipboard")
                    Text(failed ? L("Не удалось добавить ссылку") : L("В буфере есть ссылка на сервер")).font(.subheadline)
                    Button("Добавить") {
                        Task {
                            do { try await library.add(any: link); dismiss() } catch { failed = true }
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.subheadline.weight(.medium))
                    Button("Скрыть", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .opacity(0.6)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)
                .transition(.blurReplace)
            }
        }
        .animation(.smooth, value: link)
        .onAppear(perform: check)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in check() }
    }

    private func check() {
        let board = NSPasteboard.general
        guard board.changeCount != dismissedChange,
              let text = board.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              Self.schemes.contains(where: text.lowercased().hasPrefix), !text.contains("\n"),
              !library.allServers.contains(where: { (try? ProxyLink.parse(text))?.id == $0.id })
        else { link = nil; return }
        failed = false
        link = text
    }

    private func dismiss() {
        dismissedChange = NSPasteboard.general.changeCount
        link = nil
    }
}
#endif
