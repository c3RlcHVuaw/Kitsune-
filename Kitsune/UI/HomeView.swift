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
    #endif

    private var server: ServerConfig? { library.selected }
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
                    .accessibilityAddTraits(.isHeader)
                }
                .padding(.top, 8)
                #if os(macOS)
                ClipboardOffer(library: library).padding(.top, 10)
                #endif
                Spacer(minLength: 16)
                ConnectButton(status: vpn.status, action: toggle)
                StatusCaption(status: vpn.status, hasError: hasError, server: server, connectedDate: vpn.connectedDate) {
                    tab = .servers
                }
                .padding(.top, 28)
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
                                SpeedRow(vpn: vpn).appear(1)
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
        #if os(macOS)
        .onChange(of: vpn.status) { old, new in
            // Soft system sounds on connect and on a user-driven disconnect.
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
    var action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = false

    private let copper = Color(red: 1.0, green: 0.50, blue: 0.10)
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
                    .stroke(copper, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .padding(-14)
                Circle()
                    .fill(connected
                          ? AnyShapeStyle(copper.opacity(0.18))
                          : AnyShapeStyle(LinearGradient(colors: [.white.opacity(0.09), .white.opacity(0.03)], startPoint: .top, endPoint: .bottom)))
                    .overlay(Circle().stroke(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.05), copper.opacity(0.4)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
                    .shadow(color: copper.opacity(connected ? 0.55 : busy ? 0.3 : 0.12), radius: connected ? 46 : 28)
                    .shadow(color: .black.opacity(0.5), radius: 18, y: 10)
                    .glassEffect(connected ? .regular.tint(copper.opacity(0.45)) : .regular, in: .circle)
                    .animation(.smooth(duration: 0.8), value: status)
                FoxMark(color: connected ? .white : Color(red: 0.96, green: 0.80, blue: 0.62))
                    .frame(width: 88)
                    .offset(y: 4)
                    .phaseAnimator([false, true], trigger: connected) { view, phase in
                        view.offset(y: phase && connected && !reduceMotion ? -8 : 0)
                    } animation: { _ in .spring(duration: 0.35, bounce: 0.5) }
            }
            .frame(width: 200, height: 200)
            .contentShape(.circle)
            .phaseAnimator(!busy && !connected && !reduceMotion ? [1.0, 1.035] : [1.0]) { view, scale in
                view.scaleEffect(scale)
            } animation: { _ in .easeInOut(duration: 1.8) }
        }
        .buttonStyle(PressScale())
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
                        Text(exit.ip).font(.headline.monospacedDigit())
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
        exit = nil
        failed = false
        // Right after connecting the routes are still switching: a hard 6 s cap per try, a second service, a few retries.
        for attempt in 0..<4 {
            for endpoint in Self.endpoints {
                if let found = await Self.fetch(endpoint) {
                    exit = found
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

// MARK: - Live speed

/// Down/up speed from the core plus what this session has moved. Numbers roll instead of jumping.
private struct SpeedRow: View {
    let vpn: VPNManager

    var body: some View {
        HStack(spacing: 0) {
            stat("arrow.down", rate: vpn.downRate, total: vpn.downTotal)
            Divider().frame(height: 28).overlay(.white.opacity(0.3))
            stat("arrow.up", rate: vpn.upRate, total: vpn.upTotal)
        }
        .padding(.vertical, 12)
        .background(alignment: .bottom) {
            Sparkline(values: vpn.downHistory)
                .frame(height: 38)
                .opacity(0.5)
                .clipShape(.rect(cornerRadius: 20))
                .animation(.smooth(duration: 0.6), value: vpn.downHistory)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }

    private func stat(_ icon: String, rate: Int64, total: Int64) -> some View {
        VStack(spacing: 2) {
            Label(Self.rate(rate), systemImage: icon)
                .font(.headline.monospacedDigit())
                .contentTransition(.numericText())
            Text(L("за сессию ") + Self.bytes(total))
                .font(.caption.monospacedDigit())
                .opacity(0.8)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
        .animation(.smooth(duration: 0.3), value: rate)
    }

    private static func bytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .binary) }
    private static func rate(_ value: Int64) -> String { bytes(value) + L("/с") }
}

/// Download speed over the last seconds as a soft white area chart behind the speed numbers.
private struct Sparkline: View {
    let values: [Int64]

    var body: some View {
        GeometryReader { proxy in
            let peak = Double(max(values.max() ?? 1, 50_000)) // flat line, not noise, when nothing moves
            let step = proxy.size.width / CGFloat(max(values.count - 1, 1))
            let points = values.enumerated().map { index, value in
                CGPoint(x: CGFloat(index) * step, y: proxy.size.height * (1 - CGFloat(Double(value) / peak)))
            }
            ZStack {
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: CGPoint(x: first.x, y: proxy.size.height))
                    path.addLine(to: first)
                    for point in points.dropFirst() { path.addLine(to: point) }
                    path.addLine(to: CGPoint(x: points.last?.x ?? 0, y: proxy.size.height))
                    path.closeSubpath()
                }
                .fill(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0)], startPoint: .top, endPoint: .bottom))
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for point in points.dropFirst() { path.addLine(to: point) }
                }
                .stroke(.white.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
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
