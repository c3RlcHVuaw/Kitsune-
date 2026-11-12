import Shared
import SwiftUI
import UniformTypeIdentifiers

/// Routing profile, one-tap sets, per-app rules and the user's own site lists, as native-style grouped lists.
struct RoutingView: View {
    let library: Library

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                ScreenHeader(title: "Маршруты") { EmptyView() }
                ScrollView {
                    VStack(spacing: 22) {
                        profilePicker.appear(0)
                        ProtectionSection(dns: binding(\.dns), blockAds: binding(\.blockAds)).appear(1)
                        if library.routing.profile == .russiaDirect { RussianListsSection().appear(1) }
                        if library.routing.usesUserLists {
                            PresetsSection(presets: binding(\.presets)).appear(2)
                            #if os(macOS)
                            AppsSection(title: "Приложения — всегда напрямую", apps: binding(\.directApps), footer: nil)
                            AppsSection(title: "Приложения — всегда через VPN", apps: binding(\.proxyApps), footer: "Применяется при следующем подключении.")
                            AppServersSection(library: library)
                            #endif
                            SitesSection(title: "Сайты — всегда напрямую", footer: "Эти сайты и адреса всегда открываются без VPN.",
                                         entries: binding(\.direct))
                            SitesSection(title: "Сайты — всегда через VPN", footer: "Идут через VPN, даже если сайт российский.",
                                         entries: binding(\.proxy))
                        }
                        CheckSiteSection(routing: library.routing)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .iOSNavigation(title: "Маршруты") { EmptyView() }
        }
    }

    private var profilePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Профиль", selection: binding(\.profile)) {
                ForEach(RoutingSettings.Profile.allCases, id: \.self) { Text($0.shortTitle).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(library.routing.profile.subtitle).font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 4)
        }
    }

    private func binding<T>(_ keyPath: WritableKeyPath<RoutingSettings, T>) -> Binding<T> {
        Binding(get: { library.routing[keyPath: keyPath] }, set: { library.routing[keyPath: keyPath] = $0 })
    }
}

private let accent = Color(red: 1.0, green: 0.50, blue: 0.10)

/// Resolver for tunnelled traffic and ad blocking.
private struct ProtectionSection: View {
    @Binding var dns: RoutingSettings.DNSProvider
    @Binding var blockAds: Bool

    var body: some View {
        ListSection(title: "DNS и реклама", footer: "Применяется при следующем подключении. Список рекламы обновляется раз в сутки.") {
            ListRow {
                Text("DNS через VPN")
                Spacer()
                Picker("DNS через VPN", selection: $dns) {
                    ForEach(RoutingSettings.DNSProvider.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
            }
            ListRow {
                Text("Блокировать рекламу и трекеры")
                Spacer()
                Toggle("", isOn: $blockAds).labelsHidden().toggleStyle(.switch).tint(accent)
            }
        }
    }
}

private struct RussianListsSection: View {
    private let lists = [
        ("globe.europe.africa", "Все сайты .ru, .рф и .su"),
        ("cart", "Российские сервисы: банки, маркетплейсы, такси, доставка"),
        ("building.columns", "Госуслуги и сайты .gov.ru"),
        ("lock.shield", "Сервисы, доступные только из России"),
        ("number", "Российские IP-адреса"),
    ]

    var body: some View {
        ListSection(title: "Напрямую, без VPN", footer: "Списки обновляются автоматически раз в сутки.") {
            ForEach(lists, id: \.1) { icon, title in
                ListRow {
                    Image(systemName: icon).foregroundStyle(.secondary).frame(width: 22)
                    Text(LocalizedStringKey(title))
                }
            }
        }
    }
}

private struct PresetsSection: View {
    @Binding var presets: Set<RoutePreset>

    private func info(_ preset: RoutePreset) -> (LocalizedStringKey, String) {
        switch preset {
        case .streaming: ("Стриминг", "play.rectangle")
        case .games: ("Игры", "gamecontroller")
        case .messengers: ("Мессенджеры", "paperplane")
        }
    }

    var body: some View {
        ListSection(title: "Быстрые наборы", footer: "Всегда через VPN, даже если сервис российский.") {
            ForEach(RoutePreset.allCases, id: \.self) { preset in
                ListRow {
                    Label(info(preset).0, systemImage: info(preset).1)
                    Spacer()
                    Toggle("", isOn: Binding(get: { presets.contains(preset) }, set: { on in
                        if on { presets.insert(preset) } else { presets.remove(preset) }
                    }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(accent)
                }
            }
        }
    }
}

#if os(macOS)
import AppKit

/// Process names for one rule list; the picker reads the executable name from the chosen .app.
private struct AppsSection: View {
    let title: LocalizedStringKey
    @Binding var apps: [String]
    let footer: LocalizedStringKey?

    var body: some View {
        ListSection(title: title, footer: footer) {
            ForEach(apps, id: \.self) { name in
                ListRow {
                    Text(name).lineLimit(1)
                    Spacer()
                    Button("Удалить \(name)", systemImage: "minus.circle") { withAnimation(.smooth) { apps.removeAll { $0 == name } } }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
            ListRow {
                Button("Добавить приложение…", systemImage: "plus", action: pick)
                    .buttonStyle(.plain)
                    .foregroundStyle(accent)
            }
        }
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(filePath: "/Applications")
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url),
              let name = bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String else { return }
        withAnimation(.smooth) { if !apps.contains(name) { apps.append(name) } }
    }
}

/// Apps pinned to a specific server, e.g. one browser through Netherlands while everything else uses the selected server.
private struct AppServersSection: View {
    let library: Library

    private var pinned: [(app: String, server: ServerConfig?)] {
        library.routing.appServers.sorted { $0.key < $1.key }.map { app, id in (app, library.allServers.first { $0.id == id }) }
    }

    var body: some View {
        ListSection(title: "Приложения — через свой сервер", footer: "Приложение всегда выходит через выбранный сервер, остальное через основной. Применяется при следующем подключении.") {
            ForEach(pinned, id: \.app) { item in
                ListRow {
                    Text(item.app).lineLimit(1)
                    Spacer()
                    Menu {
                        ForEach(library.allServers) { server in
                            Button(server.displayName) { library.routing.appServers[item.app] = server.id }
                        }
                    } label: {
                        Text(item.server?.displayName ?? L("сервер удалён")).lineLimit(1).foregroundStyle(.secondary)
                    }
                    .menuStyle(.button).buttonStyle(.plain).fixedSize()
                    Button("Удалить \(item.app)", systemImage: "minus.circle") { withAnimation(.smooth) { _ = library.routing.appServers.removeValue(forKey: item.app) } }
                        .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            ListRow {
                Button("Добавить приложение…", systemImage: "plus", action: pick)
                    .buttonStyle(.plain)
                    .foregroundStyle(accent)
            }
        }
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(filePath: "/Applications")
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url),
              let name = bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String,
              let server = library.selected ?? library.allServers.first else { return }
        withAnimation(.smooth) { library.routing.appServers[name] = server.id }
    }
}
#endif

private struct SitesSection: View {
    let title: LocalizedStringKey
    let footer: LocalizedStringKey
    @Binding var entries: [String]

    @State private var draft = ""
    @State private var error: String?

    var body: some View {
        ListSection(title: title, footer: footer) {
            ForEach(entries, id: \.self) { entry in
                ListRow {
                    Text(entry).font(.body.monospaced()).lineLimit(1)
                    Spacer()
                    Button("Удалить \(entry)", systemImage: "minus.circle") { withAnimation(.smooth) { entries.removeAll { $0 == entry } } }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
            ListRow {
                TextField("example.com или 1.2.3.0/24", text: $draft)
                    .textFieldStyle(.plain)
                    .technicalTextEntry()
                    .submitLabel(.done)
                    .onSubmit(add)
                    .onChange(of: draft) { error = nil }
                Button("Добавить", systemImage: "plus", action: add)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(accent)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let error {
                ListRow { Label(error, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(Color.alert) }
            }
        }
    }

    private func add() {
        do {
            let entry = try RouteEntry(draft).display
            if !entries.contains(entry) { withAnimation(.smooth) { entries.append(entry) } }
            draft = ""
        } catch {
            self.error = switch error {
            case .empty: L("Введите адрес сайта или IP.")
            case .nonASCII: L("Кириллические домены пока не поддерживаются.")
            case .invalid: L("Это не похоже на адрес сайта или IP.")
            }
        }
    }
}

/// "Where will this site go?" Answers from the user's lists and the .ru rule; the core's big Russian lists aren't visible here.
private struct CheckSiteSection: View {
    let routing: RoutingSettings

    @State private var input = ""
    @State private var result: Result<RouteDecision, RouteEntry.ParseError>?

    var body: some View {
        ListSection(title: "Куда пойдёт сайт", footer: "Правила работают по сайтам и IP-адресам.") {
            ListRow {
                TextField("example.com или 1.2.3.4", text: $input)
                    .textFieldStyle(.plain)
                    .technicalTextEntry()
                    .submitLabel(.search)
                    .onSubmit(check)
                    .onChange(of: input) { result = nil }
                Button("Проверить", action: check)
                    .buttonStyle(.plain)
                    .foregroundStyle(accent)
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let result {
                ListRow { answer(result).transition(.blurReplace) }
            }
        }
        .animation(.smooth, value: result.map { "\($0)" })
    }

    private func check() {
        result = Result { () throws(RouteEntry.ParseError) in try routing.decide(input) }
    }

    @ViewBuilder private func answer(_ result: Result<RouteDecision, RouteEntry.ParseError>) -> some View {
        switch result {
        case .failure(let error):
            Label(error == .nonASCII ? L("Кириллические домены пока не поддерживаются.") : L("Это не похоже на адрес сайта или IP."),
                  systemImage: "exclamationmark.triangle.fill").font(.subheadline).foregroundStyle(Color.alert)
        case .success(let decision):
            VStack(alignment: .leading, spacing: 4) {
                Label(decision.direct ? L("Напрямую, без VPN") : L("Через VPN"), systemImage: decision.direct ? "arrow.right" : "lock.fill")
                    .fontWeight(.medium)
                Text(LocalizedStringKey(explanation(decision))).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func explanation(_ decision: RouteDecision) -> String {
        switch decision.reason {
        case .localNetwork: "Локальная сеть всегда идёт напрямую."
        case .userDirect: "Совпало с вашим списком «Всегда напрямую»."
        case .userProxy: "Совпало с вашим списком «Всегда через VPN»."
        case .russianDomain: "Российский домен (.ru, .рф, .su)."
        case .allThroughVPN: "Выбран профиль «Всё через VPN»."
        case .otherwise: "Нет в ваших списках. Крупные российские сервисы из встроенных списков (банки, маркетплейсы) всё равно пойдут напрямую: здесь они не проверяются."
        }
    }
}
