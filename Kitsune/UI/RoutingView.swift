import Shared
import SwiftUI
import UniformTypeIdentifiers

/// Routing profile, one-tap sets, per-app rules and the user's own site lists, as native-style grouped lists.
struct RoutingView: View {
    @Environment(\.kitsuneTheme) private var theme
    private var accent: Color { theme.accent }
    let library: Library

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                ScreenHeader(title: "Маршруты") { EmptyView() }
                ScrollView {
                    VStack(spacing: 24) {
                        profilePicker.appear(0)
                        ProtectionSection(dns: binding(\.dns), blockAds: binding(\.blockAds), blockIPv6: binding(\.blockIPv6)).appear(1)
                        #if os(macOS)
                        DoubleHopSection(library: library).appear(2)
                        #endif
                        if library.routing.profile == .russiaDirect { RussianListsSection().appear(3) }
                        if library.routing.usesUserLists {
                            PresetsSection(presets: binding(\.presets)).appear(4)
                            #if os(macOS)
                            AppsSection(title: "Приложения — всегда напрямую", apps: binding(\.directApps), footer: nil).appear(5)
                            AppsSection(title: "Приложения — всегда через VPN", apps: binding(\.proxyApps), footer: "Применяется при следующем подключении.")
                            AppServersSection(library: library)
                            #endif
                            SitesSection(title: "Сайты — всегда напрямую", footer: "Эти сайты и адреса всегда открываются без VPN.",
                                         entries: binding(\.direct), examples: ["apple.com", "icloud.com", "microsoft.com"])
                            SitesSection(title: "Сайты — всегда через VPN", footer: "Идут через VPN, даже если сайт российский.",
                                         entries: binding(\.proxy), examples: ["chatgpt.com", "youtube.com", "instagram.com"])
                        }
                        CheckSiteSection(routing: library.routing)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
                .rememberScroll("routing")
            }
            .readableWidth()
            .iOSNavigation(title: "Маршруты") { EmptyView() }
        }
    }

    private var profilePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(RoutingSettings.Profile.allCases, id: \.self) { profile in
                    let on = library.routing.profile == profile
                    Button {
                        Feedback.tap()
                        withAnimation(.smooth(duration: 0.35)) { library.routing.profile = profile }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: Self.icon(profile)).font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(on ? accent : .secondary)
                                .frame(width: 44, height: 44)
                                .background((on ? accent : Color.white).opacity(on ? 0.2 : 0.06), in: .circle)
                                .symbolEffect(.bounce, value: on)
                            Text(profile.shortTitle).font(.footnote.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .shadow(color: accent.opacity(on ? 0.3 : 0), radius: 14)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: 16).fill(accent.opacity(0.16))
                                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(accent.opacity(0.7), lineWidth: 1))
                                    .matchedGeometryEffect(id: "profile", in: profileSpace)
                            }
                        }
                        .background(.white.opacity(on ? 0 : 0.06), in: .rect(cornerRadius: 16))
                        .contentShape(.rect)
                    }
                    .buttonStyle(PressScale())
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            Text(library.routing.profile.subtitle).font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 4)
                .contentTransition(.opacity).animation(.smooth, value: library.routing.profile)
            if library.routing.usesUserLists { summary }
        }
    }

    /// How much the user's own rules cover, at a glance.
    private var summary: some View {
        let r = library.routing
        let chips = [
            ("arrow.right", String(format: L("Напрямую: %lld"), r.direct.count + r.directApps.count)),
            ("lock.fill", String(format: L("Через VPN: %lld"), r.proxy.count + r.proxyApps.count)),
        ]
        return HStack(spacing: 8) {
            ForEach(chips, id: \.1) { icon, text in
                Label(text, systemImage: icon).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.white.opacity(0.07), in: .capsule)
                    .contentTransition(.numericText())
            }
        }
        .animation(.smooth, value: r.direct.count + r.directApps.count + r.proxy.count + r.proxyApps.count)
    }

    @Namespace private var profileSpace

    private static func icon(_ profile: RoutingSettings.Profile) -> String {
        switch profile {
        case .russiaDirect: "globe.europe.africa.fill"
        case .allVPN: "lock.shield.fill"
        case .custom: "slider.horizontal.3"
        }
    }

    private func binding<T>(_ keyPath: WritableKeyPath<RoutingSettings, T>) -> Binding<T> {
        Binding(get: { library.routing[keyPath: keyPath] }, set: { library.routing[keyPath: keyPath] = $0 })
    }
}

/// Small tinted square with an SF Symbol: the leading icon of every row on this screen.
private struct RowIcon: View {
    @Environment(\.kitsuneTheme) private var theme
    let symbol: String
    var on = true
    var body: some View {
        Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
            .foregroundStyle(on ? theme.accent : .secondary)
            .frame(width: 28, height: 28)
            .background((on ? theme.accent : Color.white).opacity(on ? 0.16 : 0.08), in: .rect(cornerRadius: 8))
            .animation(.smooth, value: on)
    }
}

/// Resolver for tunnelled traffic and ad blocking.
private struct ProtectionSection: View {
    @Environment(\.kitsuneTheme) private var theme
    private var accent: Color { theme.accent }
    @Binding var dns: RoutingSettings.DNSProvider
    @Binding var blockAds: Bool
    @Binding var blockIPv6: Bool

    var body: some View {
        ListSection(title: "DNS и реклама", symbol: "shield.lefthalf.filled", footer: "Применяется при следующем подключении. Список рекламы обновляется раз в сутки. IPv6 стоит закрыть, если сервер его не поддерживает: иначе он может идти мимо туннеля.", footerAsHelp: true) {
            ListRow {
                RowIcon(symbol: "network")
                Text("DNS через VPN")
                Spacer()
                Picker("DNS через VPN", selection: $dns) {
                    ForEach(RoutingSettings.DNSProvider.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
            }
            ListRow {
                RowIcon(symbol: "hand.raised.fill", on: blockAds)
                Text("Блокировать рекламу и трекеры")
                Spacer()
                Toggle("", isOn: $blockAds).labelsHidden().toggleStyle(.switch).tint(accent)
            }
            ListRow {
                RowIcon(symbol: "6.circle.fill", on: blockIPv6)
                Text("Блокировать IPv6")
                HelpButton(text: "Не у всех серверов есть IPv6. Тогда такие запросы могут уйти мимо туннеля, и сайт увидит ваш настоящий адрес. Блокировка закрывает эту дыру; на скорость не влияет.")
                Spacer()
                Toggle("", isOn: $blockIPv6).labelsHidden().toggleStyle(.switch).tint(accent)
            }
        }
    }
}

private struct RussianListsSection: View {
    @Environment(\.kitsuneTheme) private var theme
    private var accent: Color { theme.accent }
    private let lists = [
        ("globe.europe.africa", "Все сайты .ru, .рф и .su"),
        ("cart", "Российские сервисы: банки, маркетплейсы, такси, доставка"),
        ("building.columns", "Госуслуги и сайты .gov.ru"),
        ("lock.shield", "Сервисы, доступные только из России"),
        ("number", "Российские IP-адреса"),
    ]

    var body: some View {
        ListSection(title: "Напрямую, без VPN", symbol: "arrow.right", footer: "Списки обновляются автоматически раз в сутки.", footerAsHelp: true) {
            ForEach(lists, id: \.1) { icon, title in
                ListRow {
                    RowIcon(symbol: icon)
                    Text(LocalizedStringKey(title))
                }
            }
        }
    }
}

private struct PresetsSection: View {
    @Environment(\.kitsuneTheme) private var theme
    private var accent: Color { theme.accent }
    @Binding var presets: Set<RoutePreset>

    private func info(_ preset: RoutePreset) -> (LocalizedStringKey, String) {
        switch preset {
        case .streaming: ("Стриминг", "play.rectangle")
        case .games: ("Игры", "gamecontroller")
        case .messengers: ("Мессенджеры", "paperplane")
        }
    }

    var body: some View {
        ListSection(title: "Быстрые наборы", symbol: "bolt.fill", footer: "Всегда через VPN, даже если сервис российский.", footerAsHelp: true) {
            ForEach(RoutePreset.allCases, id: \.self) { preset in
                ListRow {
                    RowIcon(symbol: info(preset).1, on: presets.contains(preset))
                    Text(info(preset).0)
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

/// Icon of a running app by executable name, remembered once found; stopped apps get a placeholder.
@MainActor private enum AppIcons {
    private static var cache: [String: NSImage] = [:]
    static func icon(_ name: String) -> NSImage? {
        if let hit = cache[name] { return hit }
        let found = NSWorkspace.shared.runningApplications.first { $0.executableURL?.lastPathComponent == name }?.icon
        if let found { cache[name] = found }
        return found
    }
}

/// Process names for one rule list; the picker reads the executable name from the chosen .app.
private struct AppsSection: View {
    @Environment(\.kitsuneTheme) private var theme
    private var accent: Color { theme.accent }
    let title: LocalizedStringKey
    @Binding var apps: [String]
    let footer: LocalizedStringKey?

    @State private var justAdded: String?
    @State private var targeted = false

    var body: some View {
        ListSection(title: title, symbol: footer == nil ? "arrow.right" : "lock.fill", footer: footer, footerAsHelp: true) {
            ForEach(apps, id: \.self) { name in
                ListRow {
                    if let icon = AppIcons.icon(name) { Image(nsImage: icon).resizable().frame(width: 28, height: 28) }
                    else { RowIcon(symbol: "app.dashed") }
                    Text(name).lineLimit(1)
                    Spacer()
                    Button("Удалить \(name)", systemImage: "minus.circle") { withAnimation(.smooth) { apps.removeAll { $0 == name } } }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                .background(accent.opacity(justAdded == name ? 0.22 : 0))
                .animation(.smooth(duration: 0.6), value: justAdded)
            }
            if apps.isEmpty {
                ListRow { MiniEmpty(title: "Пока пусто", hint: "Перетащите приложение сюда или нажмите «Добавить»") }
            }
            ListRow {
                Button("Добавить приложение…", systemImage: "plus", action: pick)
                    .buttonStyle(.plain)
                    .foregroundStyle(accent)
            }
        }
        .dropTarget(targeted: $targeted, accent: accent) { urls in urls.reduce(false) { add($1) || $0 } }
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(filePath: "/Applications")
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = add(url)
    }

    /// Takes an .app bundle (picked or dropped) and remembers its executable name.
    private func add(_ url: URL) -> Bool {
        guard url.pathExtension == "app", let bundle = Bundle(url: url),
              let name = bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String else { return false }
        Feedback.tap()
        withAnimation(.smooth) { if !apps.contains(name) { apps.append(name) } }
        justAdded = name
        Task { try? await Task.sleep(for: .seconds(1.4)); if justAdded == name { justAdded = nil } }
        return true
    }
}

/// Apps pinned to a specific server, e.g. one browser through Netherlands while everything else uses the selected server.
/// Double hop: traffic goes to the entry server first and leaves through the one chosen on "Серверы".
private struct DoubleHopSection: View {
    @Environment(\.kitsuneTheme) private var theme
    private var accent: Color { theme.accent }
    let library: Library

    private var entry: ServerConfig? { library.allServers.first { $0.id == library.routing.entryServerID } }

    var body: some View {
        ListSection(title: "Двойной прыжок", symbol: "arrow.triangle.branch", footer: "Трафик идёт через два сервера: входной не видит, куда вы заходите, а выходной не знает, кто вы. Скорость ниже, чем с одним сервером. Применяется при следующем подключении.", footerAsHelp: true) {
            ListRow {
                RowIcon(symbol: "arrow.triangle.branch", on: library.routing.entryServerID != nil)
                Text("Через входной сервер")
                HelpButton(text: "Сначала трафик идёт на входной сервер, оттуда на выходной и только потом на сайт. Входной знает, кто вы, но не видит, куда вы заходите. Выходной видит сайты, но не знает, кто вы.", route: ["laptopcomputer", "server.rack", "server.rack", "globe"])
                Spacer()
                Toggle("", isOn: Binding(
                    get: { library.routing.entryServerID != nil },
                    set: { on in
                        let others = library.allServers.filter { $0.id != library.selected?.id }
                        library.routing.entryServerID = on ? others.first?.id : nil
                    }
                ))
                .labelsHidden().toggleStyle(.switch).tint(accent)
                .disabled(library.allServers.count < 2)
            }
            if library.routing.entryServerID != nil {
                ListRow {
                    RowIcon(symbol: "server.rack")
                    Text("Входной сервер")
                    Spacer()
                    Menu {
                        ForEach(library.allServers) { server in
                            Button(server.displayName) { library.routing.entryServerID = server.id }
                        }
                    } label: {
                        Text(entry?.displayName ?? L("сервер удалён")).lineLimit(1).foregroundStyle(.secondary)
                    }
                    .menuStyle(.button).buttonStyle(.plain).fixedSize()
                }
            }
        }
    }
}

private struct AppServersSection: View {
    @Environment(\.kitsuneTheme) private var theme
    private var accent: Color { theme.accent }
    let library: Library

    private var pinned: [(app: String, server: ServerConfig?)] {
        library.routing.appServers.sorted { $0.key < $1.key }.map { app, id in (app, library.allServers.first { $0.id == id }) }
    }

    var body: some View {
        ListSection(title: "Приложения — через свой сервер", symbol: "app.badge", footer: "Приложение всегда выходит через выбранный сервер, остальное через основной. Применяется при следующем подключении.", footerAsHelp: true) {
            ForEach(pinned, id: \.app) { item in
                ListRow {
                    if let icon = AppIcons.icon(item.app) { Image(nsImage: icon).resizable().frame(width: 28, height: 28) }
                    else { RowIcon(symbol: "app.dashed") }
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
    @Environment(\.kitsuneTheme) private var theme
    private var accent: Color { theme.accent }
    let title: LocalizedStringKey
    let footer: LocalizedStringKey
    @Binding var entries: [String]

    /// One-tap suggestions shown while the list is empty.
    var examples: [String] = []
    @State private var draft = ""
    @State private var error: String?
    @State private var justAdded: String?
    @State private var targeted = false

    var body: some View {
        ListSection(title: title, symbol: examples.first == "apple.com" ? "arrow.right" : "lock.fill", footer: footer, footerAsHelp: true) {
            if entries.isEmpty {
                ListRow { MiniEmpty(title: "Пока пусто", hint: "Введите адрес или перетащите сайт сюда") }
            } else {
                ListRow {
                    FlowLayout(spacing: 8) {
                        ForEach(entries, id: \.self) { chip($0) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                    .animation(.smooth, value: entries)
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
            if entries.isEmpty, !examples.isEmpty {
                ListRow {
                    FlowLayout(spacing: 8) {
                    Text("Например:").font(.footnote).foregroundStyle(.secondary).padding(.vertical, 5)
                    ForEach(examples, id: \.self) { example in
                        Button {
                            withAnimation(.smooth) { entries.append(example) }
                            flash(example)
                        } label: {
                            Label(example, systemImage: "plus").font(.footnote.weight(.medium))
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(.white.opacity(0.08), in: .capsule)
                        }
                        .buttonStyle(.plain)
                    }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .dropTarget(targeted: $targeted, accent: accent) { strings in strings.reduce(false) { insert($1) || $0 } }
    }

    private func chip(_ entry: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: entry.first?.isNumber == true || entry.contains(":") ? "number" : "globe")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(accent)
            Text(entry).font(.footnote.monospaced()).lineLimit(1)
            Button { withAnimation(.smooth) { entries.removeAll { $0 == entry } } } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .accessibilityLabel("Удалить \(entry)")
        }
        .padding(.leading, 10).padding(.trailing, 8).padding(.vertical, 6)
        .background(accent.opacity(justAdded == entry ? 0.3 : 0.12), in: .capsule)
        .animation(.smooth(duration: 0.6), value: justAdded)
        .transition(.scale.combined(with: .opacity))
        .contextMenu {
            Button("Копировать", systemImage: "doc.on.doc") { Clipboard.copy(entry) }
            Button("Изменить", systemImage: "pencil") { draft = entry; entries.removeAll { $0 == entry } }
            Button("Удалить", systemImage: "trash", role: .destructive) { withAnimation(.smooth) { entries.removeAll { $0 == entry } } }
        }
    }

    /// A dropped link or text: a link gives its host, anything else must look like a site or IP.
    private func insert(_ raw: String) -> Bool {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let entry = try? RouteEntry(URL(string: text)?.host ?? text).display else { return false }
        Feedback.tap()
        if !entries.contains(entry) { withAnimation(.smooth) { entries.append(entry) }; flash(entry) }
        return true
    }

    /// The new row glows copper for a moment, so you see where it landed.
    private func flash(_ entry: String) {
        justAdded = entry
        Task { try? await Task.sleep(for: .seconds(1.4)); if justAdded == entry { justAdded = nil } }
    }

    private func add() {
        do {
            let entry = try RouteEntry(draft).display
            if !entries.contains(entry) { withAnimation(.smooth) { entries.append(entry) }; flash(entry) }
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
    @Environment(\.kitsuneTheme) private var theme
    private var accent: Color { theme.accent }
    let routing: RoutingSettings

    @State private var input = ""
    @State private var result: Result<RouteDecision, RouteEntry.ParseError>?

    var body: some View {
        ListSection(title: "Куда пойдёт сайт", symbol: "magnifyingglass", footer: "Правила работают по сайтам и IP-адресам.", footerAsHelp: true) {
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
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: decision.direct ? "arrow.right" : "lock.fill").font(.system(size: 14, weight: .bold))
                    .foregroundStyle(decision.direct ? .white : accent)
                    .frame(width: 34, height: 34).background((decision.direct ? Color.white : accent).opacity(0.16), in: .circle)
                    .symbolEffect(.bounce, value: input)
                VStack(alignment: .leading, spacing: 4) {
                    Text(decision.direct ? L("Напрямую, без VPN") : L("Через VPN")).fontWeight(.semibold)
                    Text(LocalizedStringKey(explanation(decision))).font(.footnote).foregroundStyle(.secondary)
                }
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


private extension View {
    /// Accepts a drop, outlining the section with a dashed line while something hovers over it.
    func dropTarget<T: Transferable>(targeted: Binding<Bool>, accent: Color, handle: @escaping ([T]) -> Bool) -> some View {
        dropDestination(for: T.self) { items, _ in handle(items) } isTargeted: { targeted.wrappedValue = $0 }
            .overlay {
                RoundedRectangle(cornerRadius: 20).stroke(accent, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .opacity(targeted.wrappedValue ? 1 : 0).allowsHitTesting(false)
            }
            .animation(.smooth(duration: 0.2), value: targeted.wrappedValue)
    }
}
