import NetworkExtension
import Shared
import SwiftUI

@main
struct KitsuneApp: App {
    @State private var vpn = VPNManager()
    @State private var library = Library()
    @State private var tab = AppTab.home
    @AppStorage("autoConnect") private var autoConnect = false
    @AppStorage("showMenuBar") private var showMenuBar = true
    @AppStorage("buttonTheme") private var themeRaw = "copper"
    private var theme: ButtonTheme { ButtonTheme(rawValue: themeRaw) ?? .copper }

    init() {
        BrandFont.register()
        // Remember whether this install predates the badge: people who already finished onboarding were here from the early releases.
        let defaults = UserDefaults.standard
        if defaults.string(forKey: "firstVersion") == nil {
            defaults.set(defaults.bool(forKey: "onboardingDone") ? "early" : (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"), forKey: "firstVersion")
        }
        #if os(macOS)
        Task { await Updater.shared.checkIfDue() }
        #endif
    }

    private var root: some View {
        RootView(vpn: vpn, library: library, tab: $tab)
            .tint(.white)
            .modifier(WhatsNewModifier())
            // vless:// and similar links open Kitsune and add the server.
            .onChange(of: vpn.status) { _, new in
                if new == .connected { History.begin(server: library.selected?.displayName ?? "", country: library.selected?.countryCode) }
                else if new == .disconnected || new == .invalid { History.end(down: vpn.downTotal, up: vpn.upTotal) }
                #if os(macOS)
                DockBadge.update(connected: new == .connected, theme: theme)
                #endif
            }
            .onChange(of: themeRaw) { _, _ in
                #if os(macOS)
                DockBadge.update(connected: vpn.status == .connected, theme: theme)
                #endif
            }
            .task(id: vpn.status == .connected) {
                // A live latency sample every few seconds while the tunnel is up: feeds the ping ring and the server graph.
                guard vpn.status == .connected else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(4))
                    await library.sampleActive()
                    try? await Task.sleep(for: .seconds(6))
                }
            }
            #if os(macOS)
            .task {
                DockBadge.update(connected: vpn.status == .connected, theme: theme)
                Hotkey.action = { Task { await vpn.toggle(library: library) } }
                Hotkey.set(enabled: UserDefaults.standard.object(forKey: "globalHotkey") as? Bool ?? true)
            }
            #endif
            .onOpenURL { url in Task { try? await library.add(any: url.absoluteString) } }
            // White text and dark system chrome sit best on the fox-orange background.
            .preferredColorScheme(.dark)
    }

    var body: some Scene {
        #if os(macOS)
        WindowGroup(id: "main") {
            root.frame(minWidth: 490, minHeight: 720)
        }
        // Phone-like proportions by default, so the Mac app matches the iPhone layout.
        .defaultSize(width: 540, height: 880)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandMenu("VPN") {
                Button(vpn.status.isActive ? L("Отключить") : L("Подключить")) { Task { await vpn.toggle(library: library) } }
                    .keyboardShortcut("k")
                Divider()
                Button("Главная") { tab = .home }.keyboardShortcut("1")
                Button("Серверы") { tab = .servers }.keyboardShortcut("2")
                Button("Маршруты") { tab = .routing }.keyboardShortcut("3")
                Button("Настройки") { tab = .settings }.keyboardShortcut(",")
            }
        }

        // Quick control from the menu bar, even with the window closed.
        MenuBarExtra(isInserted: $showMenuBar) {
            MenuBarContent(vpn: vpn, library: library, autoConnect: $autoConnect)
        } label: {
            Image(nsImage: DockBadge.menuIcon(connected: vpn.status == .connected, theme: theme))
        }
        #else
        WindowGroup { root }
        #endif
    }
}

enum AppTab: Hashable, CaseIterable {
    case home, servers, routing, settings

    var title: String {
        switch self {
        case .home: L("Главная")
        case .servers: L("Серверы")
        case .routing: L("Маршруты")
        case .settings: L("Настройки")
        }
    }

    var icon: String {
        switch self {
        case .home: "shield.lefthalf.filled"
        case .servers: "server.rack"
        case .routing: "arrow.triangle.branch"
        case .settings: "gearshape"
        }
    }
}

struct RootView: View {
    let vpn: VPNManager
    let library: Library
    @Binding var tab: AppTab
    @AppStorage("onboardingDone") private var onboardingDone = false
    #if os(macOS)
    @AppStorage("autoConnect") private var autoConnect = false
    #endif
    @Environment(\.scenePhase) private var scenePhase
    #if os(macOS)
    /// Narrow window: the tab bar would collapse into a ">>" menu, so show icons only.
    @State private var compact = false
    #endif

    var body: some View {
        Group {
            if onboardingDone {
                #if os(macOS)
                // Own tab bar: the system one collapses into a ">>" menu in narrow windows; this one switches to icons.
                screen(tab)
                    .toolbar {
                        // Native toolbar segmented control: titles when there is room, icons when the window is narrow.
                        ToolbarItem(placement: .principal) {
                            Picker("Раздел", selection: $tab) {
                                ForEach(AppTab.allCases, id: \.self) { item in
                                    Group {
                                        if compact { Image(systemName: item.icon) } else { Text(item.title) }
                                    }
                                    .tag(item)
                                }
                            }
                            .pickerStyle(.segmented)
                            .id(compact) // rebuild the native control as soon as the window width crosses the limit
                        }
                    }
                #else
                TabView(selection: $tab) {
                    ForEach(AppTab.allCases, id: \.self) { item in
                        Tab(value: item) { screen(item) } label: { Label(item.title, systemImage: item.icon) }
                    }
                }
                #endif
            } else {
                OnboardingView(vpn: vpn, library: library) {
                    withAnimation(.smooth) { onboardingDone = true }
                }
            }
        }
        .onAppear { library.vpn = vpn }
        // Subscriptions refresh on their own interval, not only when the app comes to the front.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1800))
                await library.refreshDue()
            }
        }
        #if os(macOS)
        .onGeometryChange(for: Bool.self) { $0.size.width < 540 } action: { compact = $0 }
        .alert("Нужен пароль администратора", isPresented: .constant(vpn.showPasswordExplainer)) {
            Button("Продолжить") { vpn.answerPasswordExplainer(true) }
            Button("Отмена", role: .cancel) { vpn.answerPasswordExplainer(false) }
        } message: {
            Text("Чтобы создать защищённый VPN-туннель, macOS один раз попросит пароль администратора. Он вводится в системном окне: Kitsune его не видит и не хранит. Дальше пароль спрашиваться не будет.")
        }
        .task {
            // Launch auto-connect: give the library a moment to load, then connect once.
            guard autoConnect, onboardingDone else { return }
            try? await Task.sleep(for: .seconds(1))
            if vpn.status == .disconnected, let server = library.selected {
                await vpn.connect(server, servers: library.allServers, routing: library.routing)
            }
        }
        #endif
        // A new server, routing or server list applies to the running tunnel right away.
        .onChange(of: library.selected) { applyIfConnected() }
        .onChange(of: library.routing) { applyIfConnected() }
        .onChange(of: library.allServers.map(\.id)) { applyIfConnected() }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { Task { await library.refreshDue() } }
        }
    }

    @ViewBuilder private func screen(_ item: AppTab) -> some View {
        Group {
            switch item {
            case .home: HomeView(vpn: vpn, library: library, tab: $tab)
            case .servers: ServersView(library: library, tunnelUp: vpn.status == .connected)
            case .routing: RoutingView(library: library)
            case .settings: SettingsView(vpn: vpn, library: library)
            }
        }
        .id(item)
        .transition(.blurReplace)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.smooth(duration: 0.3), value: item)
        .background {
            // The living glow belongs to the Home screen only; the other tabs stay flat.
            if item == .home { KitsuneBackground(mood: mood, active: tab == item) }
            else { Color(red: 0.028, green: 0.026, blue: 0.030).ignoresSafeArea() }
        }
    }

    private var mood: KitsuneBackground.Mood {
        if vpn.lastError != nil && !vpn.status.isActive { return .error }
        return switch vpn.status {
        case .connected: .connected
        case .connecting, .reasserting, .disconnecting: .connecting
        default: .idle
        }
    }

    private func applyIfConnected() {
        guard let server = library.selected else { return }
        vpn.reload(server, servers: library.allServers, routing: library.routing)
    }
}

extension NEVPNStatus {
    var title: String {
        switch self {
        case .connected: L("Подключено")
        case .connecting: L("Подключение…")
        case .disconnecting: L("Отключение…")
        case .reasserting: L("Переподключение…")
        case .disconnected, .invalid: L("Отключено")
        @unknown default: L("Неизвестно")
        }
    }

    var isActive: Bool { self == .connected || self == .connecting || self == .reasserting }
}

extension RoutingSettings.Profile {
    var title: String {
        switch self {
        case .russiaDirect: L("Россия напрямую")
        case .allVPN: L("Всё через VPN")
        case .custom: L("Свой")
        }
    }

    /// Fits the segmented control.
    var shortTitle: String {
        switch self {
        case .russiaDirect: L("Россия")
        case .allVPN: L("Всё в VPN")
        case .custom: L("Свой")
        }
    }

    var subtitle: String {
        switch self {
        case .russiaDirect: L("Банки, маркетплейсы и Госуслуги — без VPN")
        case .allVPN: L("Весь трафик через VPN")
        case .custom: L("Только ваши правила, остальное через VPN")
        }
    }
}

#if os(macOS)
import AppKit

/// Menu bar popover menu: status, speed, connect/disconnect, server choice, launch options.
private struct MenuBarContent: View {
    let vpn: VPNManager
    let library: Library
    @Binding var autoConnect: Bool
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(vpn.status == .connected ? L("Защищено") : vpn.status.title)
        if vpn.status == .connected {
            Text("↓ \(rate(vpn.downRate))   ↑ \(rate(vpn.upRate))")
        }
        Divider()
        Button(vpn.status.isActive ? L("Отключить") : L("Подключить")) {
            if vpn.status.isActive {
                vpn.disconnect()
            } else if let server = library.selected {
                Task { await vpn.connect(server, servers: library.allServers, routing: library.routing) }
            }
        }
        .disabled(library.selected == nil || vpn.status == .disconnecting)
        Menu(String(format: L("Сервер: %@"), library.selected?.displayName ?? L("не выбран"))) {
            ForEach(library.allServers) { server in
                Toggle("\(server.flag ?? "") \(server.displayName)", isOn: Binding(
                    get: { library.selected?.id == server.id },
                    set: { _ in library.selectedID = server.id }))
            }
        }
        .disabled(library.allServers.isEmpty)
        Divider()
        Toggle("Подключаться при запуске", isOn: $autoConnect)
        Button("Снова спрашивать пароль") { Task { await vpn.forgetAdminAccess() } }
        Button("Открыть Kitsune") {
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
                window.makeKeyAndOrderFront(nil)
            } else {
                openWindow(id: "main")
            }
        }
        Button("Выйти") { NSApp.terminate(nil) }
    }

    private func rate(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .binary) + L("/с") }
}
#endif
