import Charts
import Shared
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import ServiceManagement
#endif

/// Launch options, sounds, onboarding replay and app info.
struct SettingsView: View {
    let vpn: VPNManager
    let library: Library
    @AppStorage("minimal") private var minimal = false
    @AppStorage("countryTint") private var countryTint = true
    @State private var showHistory = false
    @State private var showNews = false
    @AppStorage("buttonTheme") private var themeRaw = "copper"
    @AppStorage("winterMode") private var winterMode = true
    #if os(macOS)
    @AppStorage("haptics") private var haptics = true
    @AppStorage("lanShare") private var lanShare = false
    @State private var sharePassword = LANSharing.password()
    @State private var passwordCopied = false
    @State private var showQR = false
    @State private var shareCopied = false
    @State private var cardCopied = false
    #endif
    @State private var transferNote: LocalizedStringKey?
    @AppStorage("onboardingDone") private var onboardingDone = true
    @State private var week = TrafficStats.last(7)
    @State private var statsCleared = false
    @State private var leak = LeakCheck()
    #if os(macOS)
    @AppStorage("autoConnect") private var autoConnect = false
    @AppStorage("sounds") private var sounds = true
    @AppStorage("autoReconnect") private var autoReconnect = true
    @AppStorage("showMenuBar") private var showMenuBar = true
    @AppStorage("notifications") private var notifications = true
    @AppStorage("autoUpdateCheck") private var autoUpdateCheck = true
    @AppStorage("globalHotkey") private var globalHotkey = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    private var updater: Updater { .shared }
    /// Applied by macOS at the next launch.
    @State private var language = (UserDefaults.standard.stringArray(forKey: "AppleLanguages")?.first.map { String($0.prefix(2)) }).flatMap { ["ru", "en"].contains($0) ? $0 : nil } ?? "system"
    @State private var showDiagnostics = false
    @State private var forgotten = false
    #endif

    /// One settings page; nil is the overview with the tiles.
    enum Pane: String, CaseIterable, Identifiable {
        case design, launch, protection, sharing, data, updates, more
        var id: String { rawValue }
        var title: String {
            switch self {
            case .design: L("Дизайн")
            case .launch: L("Запуск")
            case .protection: L("Защита")
            case .sharing: L("Раздача по сети")
            case .data: L("Данные")
            case .updates: L("Обновления")
            case .more: L("Ещё")
            }
        }
        var icon: String {
            switch self {
            case .design: "sparkles"
            case .launch: "play.rectangle"
            case .protection: "checkmark.shield"
            case .sharing: "waveform.path.ecg"
            case .data: "chart.bar.fill"
            case .updates: "arrow.down"
            case .more: "gearshape"
            }
        }
    }
    @State private var pane: Pane?

    /// Panes that gained something, with the version it came in. A copper dot marks them for people who updated
    /// from an older version, until the pane is opened once.
    private static let fresh: [Pane: String] = [.data: "1.8.8"]
    @AppStorage("previousVersion") private var previousVersion = ""
    @AppStorage("openedPanes") private var openedPanes = ""

    private func isNew(_ pane: Pane) -> Bool {
        guard let since = Self.fresh[pane], !previousVersion.isEmpty,
              since.compare(previousVersion, options: .numeric) == .orderedDescending else { return false }
        return !openedPanes.split(separator: ",").contains(Substring("\(pane.rawValue)@\(since)"))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                ScreenHeader(title: pane?.title ?? L("Настройки")) { EmptyView() }
                if pane != nil {
                    Button { withAnimation(.smooth(duration: 0.3)) { pane = nil } } label: {
                        Text("‹ Настройки").font(.subheadline.weight(.medium)).foregroundStyle(accent)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, -8)
                    .transition(.opacity)
                }
                ScrollView {
                    VStack(spacing: 16) {
                        if let pane {
                            content(for: pane)
                        } else {
                            overview
                        }
                    }
                    .id(pane)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 8)), removal: .identity))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .iOSNavigation(title: "Настройки") { EmptyView() }
            .task {
                while !Task.isCancelled {
                    week = TrafficStats.last(7)
                    try? await Task.sleep(for: .seconds(3))
                }
            }
            .task(id: vpn.status) {
                // The passport and the Protection tile show a real answer, not "not checked".
                if vpn.status == .connected, case .idle = leak.state { await leak.run() }
            }
            #if os(macOS)
            .sheet(isPresented: $showHistory) { HistoryView() }
            .sheet(isPresented: $showNews) { WhatsNewView() }
            .sheet(isPresented: $showQR) { ShareQRView(address: "\(LANSharing.localAddress() ?? "—"):\(LANSharing.port)", password: sharePassword) }
            .sheet(isPresented: $showDiagnostics) { DiagnosticsView(vpn: vpn, server: nil) }
            #endif
        }
    }

    private func open(_ pane: Pane) {
        if isNew(pane), let since = Self.fresh[pane] { openedPanes += (openedPanes.isEmpty ? "" : ",") + "\(pane.rawValue)@\(since)" }
        withAnimation(.smooth(duration: 0.3)) { self.pane = pane }
    }

    // MARK: Overview

    private var overview: some View {
        VStack(spacing: 16) {
            passport.appear(0)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(Array(tiles.enumerated()), id: \.element.pane) { index, tile in
                    tileView(tile).appear(1 + index / 2)
                }
            }
            ListSection {
                Button { open(.more) } label: {
                    ListRow {
                        Label("Ещё", systemImage: Pane.more.icon)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            .appear(3)
            aboutFooter.appear(4)
        }
    }

    /// Who you are: version and update state, the week's traffic and the last leak check, at one glance.
    private var passport: some View {
        let total = week.reduce(Int64(0)) { $0 + $1.down + $1.up }
        let peak = max(week.map { $0.down + $0.up }.max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                FoxMark(color: .white).frame(width: 30)
                    .frame(width: 56, height: 56)
                    .background(accent.opacity(0.35), in: .circle)
                    .overlay(Circle().stroke(accent.opacity(0.6), lineWidth: 1))
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "Kitsune \(shortVersion)").font(.display(15, relativeTo: .headline))
                    HStack(spacing: 6) {
                        Circle().fill(updateDot).frame(width: 6, height: 6)
                        Text(updateLine).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                    }
                    let rank = History.rank
                    HStack(spacing: 5) {
                        Image(systemName: "pawprint.fill").font(.caption2)
                        Text(rank.title).font(.caption.weight(.semibold))
                        Text(verbatim: "·").foregroundStyle(.tertiary)
                        Text(rank.hint).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                    }
                    .foregroundStyle(accent)
                    .help(rank.hint)
                }
                Spacer(minLength: 0)
            }
            Divider().opacity(0.5)
            HStack(alignment: .top, spacing: 14) {
                Button { open(.data) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Трафик за неделю").font(.caption).foregroundStyle(.secondary)
                        HStack(alignment: .bottom, spacing: 10) {
                            Text(bytes(total)).font(.display(20, relativeTo: .title2)).monospacedDigit().contentTransition(.numericText())
                            HStack(alignment: .bottom, spacing: 3) {
                                ForEach(Array(week.enumerated()), id: \.offset) { index, day in
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(accent.opacity(index == week.count - 1 ? 1 : 0.45))
                                        .frame(width: 6, height: max(4, 22 * Double(day.down + day.up) / Double(peak)))
                                }
                            }
                            .frame(height: 22, alignment: .bottom)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                Rectangle().fill(.white.opacity(0.1)).frame(width: 1, height: 44)
                Button { open(.protection) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Проверка утечек").font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            Image(systemName: verdict.icon).foregroundStyle(verdict.color)
                            Text(verdict.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        }
                        Text(verdict.detail).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .kGlass(in: .rect(cornerRadius: 24))
    }

    private struct Tile { let pane: Pane; let status: String; var dot: Color? = nil }

    private var tiles: [Tile] {
        var list = [
            Tile(pane: .design, status: L(themeTitle)),
            Tile(pane: .launch, status: L("Автоподключение: ") + onOff(autoConnectValue)),
            Tile(pane: .protection, status: verdict.title, dot: verdict.dot),
        ]
        #if os(macOS)
        list.append(Tile(pane: .sharing, status: lanShare ? L("Включена") : L("Выключена"), dot: lanShare ? .green : nil))
        #endif
        list.append(Tile(pane: .data, status: L("История и экспорт")))
        list.append(Tile(pane: .updates, status: "\(shortVersion) · " + L("Авто-обновления: ") + onOff(autoUpdateValue)))
        return list
    }

    private func onOff(_ on: Bool) -> String { on ? L("ВКЛ") : L("ВЫКЛ") }

    private func tileView(_ tile: Tile) -> some View {
        Button { open(tile.pane) } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: tile.pane.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 32, height: 32)
                        .background(accent.opacity(0.18), in: .rect(cornerRadius: 10))
                    Spacer()
                    if isNew(tile.pane) {
                        Text("Новое").font(.caption2.weight(.semibold)).foregroundStyle(accent)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(accent.opacity(0.16), in: .capsule)
                            .transition(.scale.combined(with: .opacity))
                    }
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(tile.pane.title).font(.subheadline.weight(.semibold))
                    HStack(spacing: 5) {
                        if let dot = tile.dot { Circle().fill(dot).frame(width: 5, height: 5) }
                        Text(tile.status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .kGlass(in: .rect(cornerRadius: 20), interactive: true)
            .contentShape(.rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }

    private var aboutFooter: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                FoxMark(color: .white.opacity(0.5)).frame(width: 12)
                Text(verbatim: "Kitsune \(shortVersion)").font(.caption).foregroundStyle(.tertiary)
            }
            HStack(spacing: 8) {
                #if os(macOS)
                chipButton(shareCopied ? "Ссылка скопирована" : "Поделиться") {
                    Clipboard.copy(L("Kitsune: VPN, который не мешает. Российские сайты напрямую, остальное через туннель.") + " https://github.com/c3RlcHVuaw/Kitsune-/releases/latest")
                    shareCopied = true
                }
                chipButton(cardCopied ? "Карточка скопирована" : "Моя карточка") { ShareCard.copy(); cardCopied = true }
                #endif
                chipButton("Что нового?") { showNews = true }
            }
        }
        .padding(.top, 6)
        .frame(maxWidth: .infinity)
    }

    private func chipButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.footnote.weight(.medium))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.white.opacity(0.08), in: .capsule)
                .contentTransition(.opacity)
        }
        .buttonStyle(.plain)
    }

    // MARK: Panes

    @ViewBuilder private func content(for pane: Pane) -> some View {
        switch pane {
        case .design: designPane
        case .launch: launchPane
        case .protection: protectionPane
        case .sharing: sharingPane
        case .data: dataPane
        case .updates: updatesPane
        case .more: morePane
        }
    }

    private var theme: ButtonTheme { ButtonTheme(rawValue: themeRaw) ?? .copper }
    private var themeTitle: String {
        switch theme { case .copper: "Медь"; case .moon: "Луна"; case .neon: "Неон" }
    }

    private var designPane: some View {
        VStack(spacing: 16) {
            // Live preview: the home button reacts to every switch below before you leave the page.
            VStack(spacing: 14) {
                HStack(spacing: 6) {
                    Circle().fill(theme.accent).frame(width: 6, height: 6)
                    Text("Пример").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                }
                ZStack {
                    Circle().stroke(theme.accent, lineWidth: 2.5).padding(-10)
                    Circle()
                        .fill(theme.accent.opacity(0.35))
                        .shadow(color: theme.accent.opacity(minimal ? 0 : 0.5), radius: 30)
                        .kGlass(in: .circle, tint: theme.accent.opacity(0.45))
                    FoxMark(color: .white).frame(width: 56).offset(y: 3)
                    if winterMode, let season = Season.current {
                        Image(systemName: season == .winter ? "snowflake" : season == .spring ? "camera.macro" : "leaf.fill")
                            .font(.title3).foregroundStyle(season.colors[0])
                            .offset(x: 52, y: -50)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: 120, height: 120)
                .padding(10)
                .animation(.smooth, value: themeRaw)
                .animation(.smooth, value: winterMode)
                .animation(.smooth, value: minimal)
                if !minimal {
                    Text("Защищено").font(.display(20, relativeTo: .title2)).transition(.opacity)
                }
                HStack(spacing: 12) {
                    ForEach(ButtonTheme.allCases, id: \.self) { item in
                        Button { withAnimation(.smooth) { themeRaw = item.rawValue } } label: {
                            Circle().fill(item.accent).frame(width: 22, height: 22)
                                .overlay(Circle().stroke(.white, lineWidth: themeRaw == item.rawValue ? 2 : 0).padding(-4))
                        }
                        .buttonStyle(.plain)
                        .help(item.title)
                        .accessibilityLabel(item.title)
                    }
                    Text(LocalizedStringKey(themeTitle)).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .kGlass(in: .rect(cornerRadius: 24))
            .animation(.smooth, value: minimal)
            ListSection(title: "Оформление", footer: "Превью меняется сразу: цвет, сезон и минимализм видно до выхода на главную.") {
                toggleRow("Сезонное оформление", $winterMode, icon: "leaf")
                toggleRow("Минимализм на главной", $minimal, icon: "eye")
                toggleRow("Цвет кнопки по стране", $countryTint, icon: "sparkles")
                #if os(macOS)
                toggleRow("Тактильный отклик", $haptics, icon: "waveform")
                #endif
            }
            ListSection(title: "Главный экран", footer: "Тяните карточки, чтобы поменять порядок. Глаз скрывает блок.") {
                HomeLayoutEditor()
            }
        }
    }

    @ViewBuilder private var launchPane: some View {
        #if os(macOS)
        ListSection(title: "При запуске") {
            toggleRow("Подключаться при запуске", $autoConnect, icon: "bolt")
            toggleRow("Запускать при входе в систему", Binding(get: { launchAtLogin }, set: setLaunchAtLogin), icon: "power")
            toggleRow("Значок в строке меню", $showMenuBar, icon: "menubar.rectangle")
            toggleRow("Горячая клавиша ⌥⌘K", Binding(get: { globalHotkey }, set: { globalHotkey = $0; Hotkey.set(enabled: $0) }), icon: "command")
        }
        ListSection(title: "Сигналы") {
            toggleRow("Звук при подключении", $sounds, icon: "speaker.wave.2")
            toggleRow("Уведомления о подписке", $notifications, icon: "bell")
        }
        ListSection(title: "Язык", footer: "Язык сменится после перезапуска приложения.") {
            ListRow {
                Label("Язык интерфейса", systemImage: "globe")
                Spacer()
                Picker("", selection: Binding(get: { language }, set: setLanguage)) {
                    Text("Как в системе").tag("system")
                    Text("Русский").tag("ru")
                    Text("English").tag("en")
                }
                .labelsHidden().fixedSize()
            }
        }
        #endif
    }

    private var protectionPane: some View {
        VStack(spacing: 16) {
            VStack(spacing: 16) {
                HStack(alignment: .top, spacing: 26) {
                    ring("IP", check: ipCheck)
                    ring("DNS", check: dnsCheck)
                    ring("IPv6", check: ipv6Check)
                }
                Text(verdict.title).font(.display(20, relativeTo: .title2)).contentTransition(.opacity)
                Text(verdictText).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 340)
                Button { Task { await leak.run() } } label: {
                    Text(isRunning ? "Проверяем…" : "Проверить сейчас").contentTransition(.opacity)
                }
                .buttonStyle(.brand)
                .disabled(isRunning)
            }
            .padding(.vertical, 22).padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .kGlass(in: .rect(cornerRadius: 24))
            .animation(.smooth, value: verdict.title)
            #if os(macOS)
            ListSection(title: "Подключение", footer: "Если туннель упал, Kitsune поднимет его сам и при необходимости перейдёт на другой сервер.") {
                toggleRow("Переподключаться при обрыве", $autoReconnect, icon: "shield")
                buttonRow("Диагностика и журнал ядра", "stethoscope", chevron: true) { showDiagnostics = true }
            }
            #endif
        }
    }

    @ViewBuilder private var sharingPane: some View {
        #if os(macOS)
        ListSection(title: "Раздача по сети", footer: lanShare
            ? "Устройства в вашей сети смогут выходить в интернет через ваш VPN по этому адресу, логину и паролю. Применяется при следующем подключении. Не включайте в чужих и общих сетях."
            : "Для телевизора или консоли: они подключаются к Kitsune как к HTTP или SOCKS5 прокси, и их трафик идёт через туннель. Защищено случайным паролем.") {
            toggleRow("Раздавать VPN по сети", $lanShare, icon: "wifi")
            if lanShare {
                ListRow { Text("Адрес"); Spacer(); Text("\(LANSharing.localAddress() ?? "—"):\(LANSharing.port)").monospacedDigit().foregroundStyle(.secondary).textSelection(.enabled) }
                ListRow { Text("Логин"); Spacer(); Text(LANSharing.username).foregroundStyle(.secondary).textSelection(.enabled) }
                ListRow { Text("Пароль"); Spacer(); Text(sharePassword).font(.body.monospaced()).foregroundStyle(.secondary).textSelection(.enabled) }
                buttonRow(passwordCopied ? "Пароль скопирован" : "Скопировать пароль", "doc.on.doc") {
                    Clipboard.copy(sharePassword); passwordCopied = true
                }
                buttonRow("Показать QR-код", "qrcode") { showQR = true }
                buttonRow("Сменить пароль", "arrow.triangle.2.circlepath") { sharePassword = LANSharing.regenerate(); passwordCopied = false }
            }
        }
        #endif
    }

    private var dataPane: some View {
        VStack(spacing: 16) {
            statsCard
            ListSection(title: "Данные", footer: transferNote ?? "Серверы и ссылки подписок в файл не попадают: в них секреты.") {
                buttonRow("История подключений", "chart.bar.fill", chevron: true) { showHistory = true }
                #if os(macOS)
                buttonRow("Экспорт настроек и маршрутов", "arrow.up") { exportSettings() }
                buttonRow("Импорт настроек и маршрутов", "arrow.down") { importSettings() }
                #endif
            }
        }
    }

    @ViewBuilder private var updatesPane: some View {
        #if os(macOS)
        ListSection(title: "Обновления", footer: updateFooter) {
            toggleRow("Проверять автоматически", $autoUpdateCheck, icon: "arrow.triangle.2.circlepath")
            buttonRow(updateTitle, "arrow.down.circle") { updateAction() }
            buttonRow("Что нового", "sparkles", chevron: true) { showNews = true }
        }
        #else
        ListSection { buttonRow("Что нового", "sparkles", chevron: true) { showNews = true } }
        #endif
    }

    private var morePane: some View {
        VStack(spacing: 16) {
            ListSection(title: "Редкое", footer: "После первого подключения пароль администратора больше не нужен. Вторая строка отменяет это разрешение.") {
                buttonRow("Показать приветствие снова", "sparkles") { withAnimation(.smooth) { onboardingDone = false } }
                #if os(macOS)
                buttonRow(forgotten ? "Готово: пароль снова нужен" : "Снова спрашивать пароль", "shield") {
                    Task { await vpn.forgetAdminAccess(); forgotten = true }
                }
                #endif
            }
            ListSection(footer: "Статистика хранится только на этом устройстве.") {
                Button {
                    TrafficStats.reset(); week = TrafficStats.last(7); statsCleared = true
                } label: {
                    ListRow { Text(statsCleared ? "Статистика сброшена" : "Сбросить статистику трафика").foregroundStyle(Color.alert); Spacer() }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Leak verdict

    private struct Verdict {
        let title: String, detail: String, icon: String, color: Color
        var dot: Color? { color == .secondary ? nil : color }
    }

    private enum Check { case unknown, running, ok(String), bad(String) }

    private var isRunning: Bool { if case .running = leak.state { true } else { false } }

    private var verdict: Verdict {
        let green = Color(red: 0.35, green: 0.85, blue: 0.50)
        switch leak.state {
        case .running: return Verdict(title: L("Проверяем…"), detail: "", icon: "hourglass", color: .secondary)
        case .failed: return Verdict(title: L("Не удалось"), detail: L("Нет сети?"), icon: "exclamationmark.triangle", color: .alert)
        case .idle: return Verdict(title: L("Не проверено"), detail: vpn.status.isActive ? L("Нажмите, чтобы проверить") : L("VPN выключен"), icon: "shield", color: .secondary)
        case .done(let r):
            if !vpn.status.isActive { return Verdict(title: L("VPN выключен"), detail: L("Сайты видят ваш адрес"), icon: "shield.slash", color: .secondary) }
            if r.country == "RU" { return Verdict(title: L("Есть утечка"), detail: L("Сайты видят российский адрес"), icon: "exclamationmark.shield.fill", color: .alert) }
            return Verdict(title: L("Утечек нет"), detail: Locale.current.localizedString(forRegionCode: r.country) ?? r.country, icon: "checkmark.shield.fill", color: green)
        }
    }

    private var verdictText: String {
        switch leak.state {
        case .done(let r) where vpn.status.isActive && r.country != "RU": L("Сайты видят адрес сервера, DNS идёт через туннель.")
        case .done where vpn.status.isActive: L("Сайты видят российский адрес: трафик идёт мимо VPN или сервер в России.")
        default: L("Показывает, какой адрес и DNS видят сайты. При включённом VPN это должен быть адрес сервера.")
        }
    }

    private var ipCheck: Check {
        switch leak.state {
        case .running: .running
        case .done(let r): vpn.status.isActive && r.country != "RU" ? .ok(Locale.current.localizedString(forRegionCode: r.country) ?? r.country) : .bad(r.ip)
        default: .unknown
        }
    }

    private var dnsCheck: Check {
        switch leak.state {
        case .running: .running
        case .done(let r): vpn.status.isActive ? .ok(r.dns ?? L("Через VPN")) : .bad(r.dns ?? L("Напрямую"))
        default: .unknown
        }
    }

    private var ipv6Check: Check {
        if case .running = leak.state { return .running }
        return library.routing.blockIPv6 ? .ok(L("Закрыт")) : .bad(L("Открыт"))
    }

    /// One check as a ring: full green with a tick, red with a cross, or an empty track before the first check.
    private func ring(_ title: String, check: Check) -> some View {
        let green = Color(red: 0.35, green: 0.85, blue: 0.50)
        let (color, value, symbol, closed): (Color, String, String?, Bool) = switch check {
        case .unknown: (.white.opacity(0.3), "—", nil, false)
        case .running: (accent, L("Проверяем…"), nil, false)
        case .ok(let v): (green, v, "checkmark", true)
        case .bad(let v): (title == "IPv6" ? .orange : .alert, v, title == "IPv6" ? "exclamationmark" : "xmark", true)
        }
        return VStack(spacing: 6) {
            ZStack {
                Circle().stroke(.white.opacity(0.1), lineWidth: 6)
                Circle().trim(from: 0, to: closed ? 1 : (isRunning ? 0.3 : 0))
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if let symbol { Image(systemName: symbol).font(.title3.weight(.semibold)).foregroundStyle(color).transition(.scale.combined(with: .opacity)) }
            }
            .frame(width: 68, height: 68)
            .padding(4)
            .animation(.smooth(duration: 0.6), value: closed)
            Text(verbatim: title).font(.subheadline.weight(.semibold))
            Text(value).font(.caption).foregroundStyle(.secondary).lineLimit(1).frame(maxWidth: 90)
        }
    }

    // MARK: Values

    private var shortVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?" }

    #if os(macOS)
    private var autoConnectValue: Bool { autoConnect }
    private var autoUpdateValue: Bool { autoUpdateCheck }
    private var updateLine: String {
        switch updater.state {
        case .available(let v, _): String(format: L("Доступна версия %@"), v)
        case .installing: L("Устанавливаем обновление")
        case .checking: L("Проверяем обновления…")
        case .failed: L("Не удалось проверить обновления")
        case .upToDate: L("Актуальная версия")
        case .idle: String(format: L("Версия %@"), version)
        }
    }
    private var updateDot: Color {
        switch updater.state {
        case .available: accent
        case .failed: .alert
        case .upToDate: Color(red: 0.35, green: 0.85, blue: 0.50)
        default: .secondary
        }
    }
    #else
    private var autoConnectValue: Bool { false }
    private var autoUpdateValue: Bool { false }
    private var updateLine: String { String(format: L("Версия %@"), version) }
    private var updateDot: Color { .secondary }
    #endif

    private var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    private let accent = Color(red: 1.0, green: 0.50, blue: 0.10)
    private let muted = Color.white.opacity(0.28)

    #if os(macOS)
    private func setLaunchAtLogin(_ on: Bool) {
        // Unsigned builds can be refused; the toggle then falls back to the real state.
        _ = on ? try? SMAppService.mainApp.register() : try? SMAppService.mainApp.unregister()
        launchAtLogin = SMAppService.mainApp.status == .enabled
        if on && SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    }

    private static let prefKeys = ["autoConnect", "autoReconnect", "sounds", "showMenuBar", "notifications", "autoUpdateCheck", "globalHotkey", "compactServers", "hideSilent"]

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Kitsune-settings.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var prefs: [String: Bool] = [:]
        for key in Self.prefKeys { if let value = UserDefaults.standard.object(forKey: key) as? Bool { prefs[key] = value } }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(Backup(routing: library.routing, prefs: prefs)).write(to: url)
            transferNote = "Настройки сохранены."
        } catch { transferNote = "Не удалось сохранить файл." }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url), let backup = try? JSONDecoder().decode(Backup.self, from: data) else {
            transferNote = "Это не файл настроек Kitsune."
            return
        }
        library.routing = backup.routing
        for (key, value) in backup.prefs where Self.prefKeys.contains(key) { UserDefaults.standard.set(value, forKey: key) }
        Hotkey.set(enabled: UserDefaults.standard.object(forKey: "globalHotkey") as? Bool ?? true)
        transferNote = "Настройки загружены. Маршруты применятся при следующем подключении."
    }

    private struct Backup: Codable { var routing: RoutingSettings; var prefs: [String: Bool] }

    private func setLanguage(_ code: String) {
        language = code
        if code == "system" { UserDefaults.standard.removeObject(forKey: "AppleLanguages") } else { UserDefaults.standard.set([code], forKey: "AppleLanguages") }
    }

    private var updateTitle: LocalizedStringKey {
        switch updater.state {
        case .available(let version, _): "Обновить до \(version)"
        case .installing: "Устанавливаем…"
        case .checking: "Проверяем…"
        default: "Проверить обновления"
        }
    }

    private var updateFooter: LocalizedStringKey {
        return switch updater.state {
        case .upToDate: "Установлена последняя версия."
        case .failed: "Не удалось проверить обновления."
        default: "Ядро sing-box обновляется вместе с приложением."
        }
    }

    private func updateAction() {
        if case .available = updater.state { Task { await updater.install() } } else { Task { await updater.check() } }
    }
    #endif

    private func bytes(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .binary) }

    /// Weekly traffic: stacked bars (download / upload) on a darker inset panel, a split bar and a per-day summary.
    private var statsCard: some View {
        let down = week.reduce(Int64(0)) { $0 + $1.down }
        let up = week.reduce(Int64(0)) { $0 + $1.up }
        let total = max(down + up, 1)
        let downShare = Double(down) / Double(total)
        let today = week.last.map { $0.down + $0.up } ?? 0
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("За 7 дней").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    legend("Загрузка", accent)
                    legend("Отдача", muted)
                }
                Chart(week) { day in
                    BarMark(x: .value("День", day.date, unit: .day), y: .value("МБ", Double(day.down) / 1_048_576), width: .ratio(0.55))
                        .foregroundStyle(by: .value("Тип", "down"))
                    BarMark(x: .value("День", day.date, unit: .day), y: .value("МБ", Double(day.up) / 1_048_576), width: .ratio(0.55))
                        .foregroundStyle(by: .value("Тип", "up"))
                }
                .chartForegroundStyleScale(["down": accent, "up": muted])
                .chartLegend(.hidden)
                .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.abbreviated)).foregroundStyle(.secondary) } }
                .chartYAxis(.hidden)
                .frame(height: 110)
            }
            .padding(14)
            .background(.black.opacity(0.28), in: .rect(cornerRadius: 18))

            GeometryReader { geo in
                HStack(spacing: 3) {
                    Capsule().fill(accent).frame(width: max(6, (geo.size.width - 3) * downShare))
                    Capsule().fill(muted)
                }
            }
            .frame(height: 6)
            .padding(.horizontal, 4)

            HStack(alignment: .firstTextBaseline) {
                stat("Загрузка", bytes(down), accent)
                Spacer()
                stat("Отдача", bytes(up), muted)
                Spacer()
                stat("Сегодня", bytes(today), .white)
            }
            .padding(.horizontal, 4)
        }
        .padding(14)
        .kGlass(in: .rect(cornerRadius: 24))
    }

    private func legend(_ title: LocalizedStringKey, _ color: Color) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func stat(_ title: LocalizedStringKey, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Text(value).font(.system(.body, design: .rounded).weight(.medium)).monospacedDigit()
        }
    }

    private func toggleRow(_ title: LocalizedStringKey, _ isOn: Binding<Bool>, icon: String? = nil) -> some View {
        ListRow {
            if let icon { Label(title, systemImage: icon) } else { Text(title) }
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().toggleStyle(.switch).tint(accent)
        }
    }

    private func buttonRow(_ title: LocalizedStringKey, _ icon: String, chevron: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ListRow {
                Label(title, systemImage: icon)
                Spacer()
                if chevron { Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary) }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
