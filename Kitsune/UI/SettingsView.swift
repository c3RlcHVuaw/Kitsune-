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

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                ScreenHeader(title: "Настройки") { EmptyView() }
                ScrollView {
                    VStack(spacing: 22) {
                        statsCard.appear(0)
                        ListSection(title: "Проверка утечек", footer: leakFooter) {
                            leakRows
                            buttonRow("Проверить сейчас", "checkmark.shield") { Task { await leak.run() } }
                        }
                        .appear(1)
                        ListSection(title: "Оформление", footer: "Зимой на кнопке снег, весной лепестки, осенью листья.") {
                            ListRow {
                                Text("Цвет кнопки")
                                Spacer()
                                HStack(spacing: 12) {
                                    ForEach(ButtonTheme.allCases, id: \.self) { theme in
                                        Button { withAnimation(.smooth) { themeRaw = theme.rawValue } } label: {
                                            Circle().fill(theme.accent).frame(width: 22, height: 22)
                                                .overlay(Circle().stroke(.white, lineWidth: themeRaw == theme.rawValue ? 2 : 0).padding(-4))
                                        }
                                        .buttonStyle(.plain)
                                        .help(theme.title)
                                        .accessibilityLabel(theme.title)
                                    }
                                }
                            }
                            toggleRow("Сезонное оформление", $winterMode)
                            toggleRow("Минимализм на главной", $minimal)
                            toggleRow("Цвет кнопки по стране", $countryTint)
                            #if os(macOS)
                            toggleRow("Тактильный отклик", $haptics)
                            #endif
                        }
                        .appear(1)
                        ListSection(title: "Главный экран", footer: "Тяните карточки, чтобы поменять порядок. Глаз скрывает блок.") {
                            HomeLayoutEditor()
                        }
                        .appear(1)
                        #if os(macOS)
                        ListSection(title: "Запуск") {
                            toggleRow("Подключаться при запуске", $autoConnect)
                            toggleRow("Переподключаться при обрыве", $autoReconnect)
                            toggleRow("Звук при подключении", $sounds)
                            toggleRow("Запускать при входе в систему", Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                            toggleRow("Значок в строке меню", $showMenuBar)
                            toggleRow("Горячая клавиша ⌥⌘K", Binding(get: { globalHotkey }, set: { globalHotkey = $0; Hotkey.set(enabled: $0) }))
                            toggleRow("Уведомления о подписке", $notifications)
                        }
                        .appear(1)
                        ListSection(title: "Раздача по сети", footer: lanShare
                            ? "Устройства в вашей сети смогут выходить в интернет через ваш VPN по этому адресу, логину и паролю. Применяется при следующем подключении. Не включайте в чужих и общих сетях."
                            : "Для телевизора или консоли: они подключаются к Kitsune как к HTTP или SOCKS5 прокси, и их трафик идёт через туннель. Защищено случайным паролем.") {
                            toggleRow("Раздавать VPN по сети", $lanShare)
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
                        .appear(2)
                        ListSection(title: "Обновления", footer: updateFooter) {
                            toggleRow("Проверять автоматически", $autoUpdateCheck)
                            buttonRow(updateTitle, "arrow.down.circle") { updateAction() }
                        }
                        .appear(2)
                        ListSection(title: "Язык", footer: "Язык сменится после перезапуска приложения.") {
                            ListRow {
                                Text("Язык интерфейса")
                                Spacer()
                                Picker("", selection: Binding(get: { language }, set: setLanguage)) {
                                    Text("Как в системе").tag("system")
                                    Text("Русский").tag("ru")
                                    Text("English").tag("en")
                                }
                                .labelsHidden().fixedSize()
                            }
                        }
                        .appear(2)
                        ListSection(title: "Доступ", footer: "После первого подключения пароль администратора больше не нужен. Эта кнопка отменяет разрешение.") {
                            buttonRow("Диагностика и журнал ядра", "stethoscope") { showDiagnostics = true }
                            buttonRow(forgotten ? "Готово: пароль снова нужен" : "Снова спрашивать пароль", "key") {
                                Task { await vpn.forgetAdminAccess(); forgotten = true }
                            }
                        }
                        .appear(2)
                        #endif
                        ListSection(footer: transferNote ?? "Серверы и ссылки подписок в файл не попадают: в них секреты.") {
                            buttonRow("История подключений", "clock.arrow.circlepath") { showHistory = true }
                            buttonRow("Что нового", "sparkles") { showNews = true }
                            #if os(macOS)
                            buttonRow("Экспорт настроек и маршрутов", "square.and.arrow.up") { exportSettings() }
                            buttonRow("Импорт настроек и маршрутов", "square.and.arrow.down") { importSettings() }
                            #endif
                        }
                        .appear(3)
                        ListSection(footer: "Статистика хранится только на этом устройстве.") {
                            buttonRow(statsCleared ? "Статистика сброшена" : "Сбросить статистику трафика", "trash") {
                                TrafficStats.reset(); week = TrafficStats.last(7); statsCleared = true
                            }
                        }
                        .appear(3)
                        ListSection {
                            buttonRow("Показать приветствие снова", "sparkles") { withAnimation(.smooth) { onboardingDone = false } }
                        }
                        .appear(3)
                        ListSection(footer: "Kitsune не собирает данные и не видит, какие сайты вы открываете.") {
                            buttonRow(cardCopied ? "Карточка скопирована" : "Карточка «мой Kitsune»", "photo") {
                                ShareCard.copy()
                                cardCopied = true
                            }
                            buttonRow(shareCopied ? "Ссылка скопирована" : "Поделиться Kitsune", "square.and.arrow.up") {
                                Clipboard.copy(L("Kitsune: VPN, который не мешает. Российские сайты напрямую, остальное через туннель.") + " https://github.com/c3RlcHVuaw/Kitsune-/releases/latest")
                                shareCopied = true
                            }
                            ListRow { Text("Версия"); Spacer(); Text(version).foregroundStyle(.secondary) }
                            ListRow { Text("Ядро"); Spacer(); Text("sing-box").foregroundStyle(.secondary) }
                        }
                        .appear(4)
                    }
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
            #if os(macOS)
            .sheet(isPresented: $showHistory) { HistoryView() }
            .sheet(isPresented: $showNews) { WhatsNewView() }
            .sheet(isPresented: $showQR) { ShareQRView(address: "\(LANSharing.localAddress() ?? "—"):\(LANSharing.port)", password: sharePassword) }
            .sheet(isPresented: $showDiagnostics) { DiagnosticsView(vpn: vpn, server: nil) }
            #endif
        }
    }

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

    private static let prefKeys = ["autoConnect", "autoReconnect", "sounds", "showMenuBar", "notifications", "autoUpdateCheck", "globalHotkey"]

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
        case .available(let version, _): "Скачать версию \(version)"
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
        if case .available(_, let url) = updater.state { NSWorkspace.shared.open(url) } else { Task { await updater.check() } }
    }
    #endif

    @ViewBuilder private var leakRows: some View {
        switch leak.state {
        case .running: ListRow { ProgressView().controlSize(.small); Text("Проверяем…") }
        case .failed: ListRow { Text("Не удалось проверить: нет сети?").foregroundStyle(.secondary) }
        case .done(let r):
            ListRow { Text("IP-адрес"); Spacer(); Text(r.ip).monospacedDigit().foregroundStyle(.secondary) }
            ListRow { Text("Страна"); Spacer(); Text(Locale.current.localizedString(forRegionCode: r.country) ?? r.country).foregroundStyle(.secondary) }
            ListRow { Text("DNS"); Spacer(); Text(r.dns ?? "—").foregroundStyle(.secondary).lineLimit(1) }
        case .idle: EmptyView()
        }
    }

    private var leakFooter: LocalizedStringKey {
        if case .done(let r) = leak.state, vpn.status.isActive, r.country == "RU" { return "Сайты видят российский адрес: трафик идёт мимо VPN или сервер в России." }
        return "Показывает, какой адрес и DNS видят сайты. При включённом VPN это должен быть адрес сервера."
    }

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

    private func toggleRow(_ title: LocalizedStringKey, _ isOn: Binding<Bool>) -> some View {
        ListRow {
            Text(title)
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().toggleStyle(.switch).tint(accent)
        }
    }

    private func buttonRow(_ title: LocalizedStringKey, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ListRow {
                Label(title, systemImage: icon)
                Spacer()
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
