import MapKit
import Shared
import SwiftUI
import TipKit

extension EnvironmentValues {
    @Entry var serverQuery = ""
}

/// Whether the selected server's row is on screen; when it scrolls away, a pinned copy appears at the top.
@MainActor @Observable final class SelectedRowVisibility { var visible = true }

/// Subscriptions and manual servers: refresh, traffic, expiry, announcements, ping, selection.
struct ServersView: View {
    @Environment(\.kitsuneTheme) private var theme
    let library: Library
    let tunnelUp: Bool

    @State var adding = false
    @State private var editing: ServerConfig?
    @State private var query = ""
    @State var pinging = false
    @AppStorage("serverSort") var sort = "default"
    @AppStorage("compactServers") var compact = false
    @AppStorage("hideSilent") var hideSilent = false
    @AppStorage("serversMap") var showMap = false
    @State private var pasteError: String?
    @State private var scroll = ScrollPosition(edge: .top)
    @State private var offset: CGFloat = 0
    @State private var selectedRow = SelectedRowVisibility()

    /// Adds whatever link is on the clipboard; without one, opens the manual form.
    private func pasteFromClipboard() {
        guard let text = Clipboard.read()?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { adding = true; return }
        Task {
            do { try await library.add(any: text); pasteError = nil }
            catch { pasteError = L("В буфере нет подходящей ссылки.") }
        }
    }

    /// The daily check found a server that is clearly faster than the selected one.
    private func betterRow(_ hint: (server: ServerConfig, saved: Int)) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "bolt.fill").foregroundStyle(.yellow)
            Text(String(format: L("Есть быстрее: %@, на %lld мс"), hint.server.displayName, hint.saved)).font(.footnote).lineLimit(1)
            Spacer(minLength: 4)
            Button("Выбрать") { withAnimation(.smooth) { library.selectedID = hint.server.id; library.betterHint = nil } }
                .buttonStyle(.plain).font(.footnote.weight(.semibold))
            Button("Скрыть", systemImage: "xmark") { withAnimation(.smooth) { library.betterHint = nil } }
                .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .kGlass(in: .capsule)
        .transition(.blurReplace)
    }

    /// The last servers you actually used, one tap away.
    private var recentRow: some View {
        let servers = library.recent.compactMap { id in library.allServers.first { $0.id == id } }
        return ScrollView(.horizontal) {
            HStack(spacing: 8) {
                Text("Недавно").font(.footnote).foregroundStyle(.secondary)
                ForEach(servers) { server in
                    Button { withAnimation(.smooth) { library.selectedID = server.id } } label: {
                        HStack(spacing: 5) {
                            Text(server.flag ?? "🌐")
                            Text(server.displayName).lineLimit(1)
                        }
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(.white.opacity(library.selected?.id == server.id ? 0.16 : 0.08), in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Поиск по серверам", text: $query).textFieldStyle(.plain)
            if !query.isEmpty {
                Button("Очистить", systemImage: "xmark.circle.fill") { query = "" }
                    .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .kGlass(in: .capsule)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 12) {
                ScreenHeader(title: "Серверы", subtitle: pingSubtitle) { toolbarActions }
                if library.isEmpty {
                    EmptyState(title: "Пока нет серверов", text: "Скопируйте ссылку на подписку или сервер от провайдера и вставьте её сюда.", symbol: "tray") {
                        VStack(spacing: 10) {
                            Button("Вставить из буфера", systemImage: "doc.on.clipboard") { pasteFromClipboard() }
                                .buttonStyle(.brand)
                            Button("Ввести вручную") { adding = true }
                                .buttonStyle(.plain).foregroundStyle(.secondary).font(.subheadline)
                            if let pasteError { Text(pasteError).font(.footnote).foregroundStyle(Color.alert).multilineTextAlignment(.center) }
                        }
                    }
                } else if showMap {
                    ServersMap(library: library).transition(.opacity)
                } else {
                    ScrollViewReader { proxy in
                    ScrollView {
                        Group {
                            LazyVStack(spacing: 22) {
                                Color.clear.frame(height: 0).id("top")
                                if library.allServers.count > 12 { searchField }
                                TipView(ServerActionsTip()).tipBackground(.clear).kGlass(in: .rect(cornerRadius: 20))
                                if let hint = library.betterHint { betterRow(hint) }
                                if library.allServers.count > 12, query.isEmpty, !library.recent.isEmpty { recentRow }
                                if !query.isEmpty, !library.allServers.contains(where: { $0.displayName.localizedCaseInsensitiveContains(query) || $0.summary.localizedCaseInsensitiveContains(query) }) {
                                    EmptyState(title: "Ничего не нашлось", text: "Попробуйте другое название, страну или адрес.", symbol: "magnifyingglass") {
                                        Button("Очистить поиск") { withAnimation(.smooth) { query = "" } }.buttonStyle(.brand)
                                    }
                                    .frame(height: 280)
                                    .transition(.opacity)
                                }
                                ForEach(Array(library.subscriptions.enumerated()), id: \.element.id) { index, subscription in
                                    SubscriptionCard(library: library, subscription: subscription).appear(index)
                                }
                                if !library.manual.isEmpty {
                                    ManualCard(library: library, editing: $editing).appear(library.subscriptions.count)
                                }
                            }
                            .environment(\.serverQuery, query)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 24)
                        }
                    }
                    .refreshable {
                        for subscription in library.subscriptions { await library.refresh(subscription.id) }
                    }
                    .rememberScroll("servers", position: $scroll) { offset = $0 }
                    .environment(selectedRow)
                    .onChange(of: library.selected?.id) { selectedRow.visible = true }
                    .overlay(alignment: .top) {
                        // The chosen server scrolled out of sight: a pinned copy, a click brings the list back to it.
                        if !selectedRow.visible, let selected = library.selected {
                            Button { withAnimation(.smooth) { proxy.scrollTo(selected.id, anchor: .center) } } label: {
                                HStack(spacing: 8) {
                                    Text(selected.flag ?? "🌐")
                                    Text(selected.displayName).font(.subheadline.weight(.medium)).lineLimit(1)
                                    PingLabel(ping: library.pings[selected.id])
                                    Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(theme.accent)
                                }
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .kGlass(in: .capsule, interactive: true)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 6)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if offset > 500 {
                            Button { withAnimation(.smooth) { proxy.scrollTo("top", anchor: .top) } } label: {
                                Image(systemName: "arrow.up").font(.body.weight(.semibold))
                                    .frame(width: 38, height: 38)
                                    .kGlass(in: .circle, interactive: true)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Наверх")
                            .padding(.trailing, 20).padding(.bottom, 16)
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .animation(.smooth, value: offset > 500)
                    .animation(.smooth, value: selectedRow.visible)
                    }
                }
                }
                .readableWidth()
            }
            .iOSNavigation(title: "Серверы", subtitle: pingSubtitle) { toolbarActions }
            .sheet(isPresented: $adding) { AddSheet(library: library) }
            .frame(maxHeight: .infinity, alignment: .top)
            .sheet(item: $editing) { server in EditServerSheet(library: library, server: server) }
        }
    }
}

extension ServersView {
    var pingSubtitle: String {
        tunnelUp ? L("Пинг — реальная задержка через сервер") : L("Пинг — до сервера, точнее при подключении")
    }

    @ViewBuilder var toolbarActions: some View {
        Button("Проверить пинг", systemImage: "speedometer") {
            pinging = true
            Task {
                await library.ping(library.allServers)
                pinging = false
            }
        }
        .disabled(library.isEmpty || pinging)
        .symbolEffect(.pulse, isActive: pinging)
        Button(showMap ? "Список" : "Карта", systemImage: showMap ? "list.bullet" : "map") {
            withAnimation(.smooth) { showMap.toggle() }
        }
        .disabled(library.isEmpty)
        Menu("Сортировка", systemImage: "arrow.up.arrow.down") {
            Picker("Сортировка", selection: $sort) {
                Text("Как в подписке").tag("default")
                Text("По пингу").tag("ping")
                Text("По стране").tag("country")
            }
            .pickerStyle(.inline)
            Toggle("Компактный список", isOn: $compact)
            Toggle("Прятать неотвечающие", isOn: $hideSilent)
        }
        .menuIndicator(.hidden)
        Button("Добавить", systemImage: "plus") { adding = true }
    }
}

// MARK: - Subscription section

/// One glass surface for a group of rows (rows themselves stay flat, so long lists don't stutter).
private struct Surface<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .kGlass(in: .rect(cornerRadius: 20))
    }
}

private struct SubscriptionCard: View {
    @Environment(\.kitsuneTheme) private var theme
    let library: Library
    let subscription: Subscription

    @Environment(\.openURL) private var openURL
    @State private var announceExpanded = false
    @State private var confirmDelete = false
    private var updating: Bool { library.updating.contains(subscription.id) }
    private var announce: String? { subscription.info.announce.flatMap { $0.isEmpty ? nil : $0 } }
    private var links: [URL] { subscription.info.links }
    private var hasInfoRows: Bool { hasUsage || !links.isEmpty || announce != nil || subscription.lastError != nil }
    private var hasUsage: Bool { subscription.info.used != nil || subscription.info.expire != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header.padding(.horizontal, 6)
            if hasInfoRows || !subscription.collapsed {
                Surface {
                    if hasUsage { usage }
                    if !links.isEmpty {
                        if hasUsage { divider }
                        linkButtons
                    }
                    if let announce {
                        if hasUsage || !links.isEmpty { divider }
                        Button {
                            withAnimation(.smooth) { announceExpanded.toggle() }
                        } label: {
                            Label(announce, systemImage: "megaphone")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(announceExpanded ? nil : 1)
                                .multilineTextAlignment(.leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(announceExpanded ? L("Свернуть") : L("Показать полностью"))
                    }
                    if let error = subscription.lastError {
                        divider
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(String(format: L("Не обновилась: %@"), error)).lineLimit(1)
                            Spacer(minLength: 4)
                            Button("Повторить") { Task { await library.refresh(subscription.id) } }
                                .buttonStyle(.plain)
                                .fontWeight(.medium)
                                .disabled(updating)
                        }
                        .font(.footnote)
                        .foregroundStyle(Color.alert)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    if !subscription.collapsed {
                        if hasInfoRows { divider }
                        if subscription.servers.isEmpty && updating {
                            // First download: placeholder rows instead of an empty card.
                            VStack(spacing: 0) {
                                ForEach(0..<4, id: \.self) { _ in
                                    HStack(spacing: 12) {
                                        RoundedRectangle(cornerRadius: 4).frame(width: 24, height: 18)
                                        VStack(alignment: .leading, spacing: 5) {
                                            RoundedRectangle(cornerRadius: 3).frame(width: 150, height: 10)
                                            RoundedRectangle(cornerRadius: 3).frame(width: 90, height: 8)
                                        }
                                        Spacer()
                                    }
                                    .foregroundStyle(.white.opacity(0.08))
                                    .padding(.horizontal, 20).frame(height: 48)
                                }
                            }
                            .shimmer()
                        } else {
                            ServerRows(library: library, servers: subscription.servers)
                        }
                    }
                }
            }
        }
    }

    private var divider: some View { Divider().opacity(0.5).padding(.leading, 16) }

    /// Support, site and Telegram links the provider put into the subscription.
    private var linkButtons: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(links, id: \.self) { url in
                    let item = Self.describe(url, support: url == subscription.info.supportURL, site: url == subscription.info.webPageURL)
                    Button { openURL(url) } label: {
                        Label(item.title, systemImage: item.icon).font(.footnote.weight(.medium)).lineLimit(1)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(.white.opacity(0.08), in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .help(url.absoluteString)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .scrollIndicators(.hidden)
    }

    private static func describe(_ url: URL, support: Bool, site: Bool) -> (title: String, icon: String) {
        let host = url.host?.lowercased() ?? ""
        let telegram = url.scheme == "tg" || host == "t.me" || host.hasSuffix("telegram.me") || host.hasSuffix("telegram.org")
        if telegram { return (support ? L("Поддержка") : L("Telegram"), "paperplane.fill") }
        if support { return (L("Поддержка"), "questionmark.bubble.fill") }
        if site { return (L("Сайт"), "globe") }
        return (host.replacingOccurrences(of: "www.", with: ""), "link")
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.smooth) { library.toggleCollapsed(subscription.id) }
            } label: {
                HStack(spacing: 6) {
                    Text(subscription.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(subscription.collapsed ? -90 : 0))
                    if updating { ProgressView().controlSize(.mini) }
                    Text(subtitle).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue(subscription.collapsed ? L("Свёрнуто") : L("Развёрнуто"))

            Menu {
                Section(String(format: L("Автообновление каждые %lld ч"), subscription.intervalHours) + (subscription.skipped > 0 ? String(format: L(" · пропущено неподдерживаемых: %lld"), subscription.skipped) : "")) {
                    Button("Обновить сейчас", systemImage: "arrow.clockwise") { Task { await library.refresh(subscription.id) } }
                        .disabled(updating)
                }
                Section {
                    Button("Проверить пинг", systemImage: "speedometer") { Task { await library.ping(subscription.servers) } }
                    Button("Самый быстрый", systemImage: "bolt.fill") {
                        Task {
                            await library.ping(subscription.servers)
                            library.selectFastest(in: subscription.servers)
                        }
                    }
                }
                Section {
                    Button("Копировать ссылку", systemImage: "doc.on.doc") { Clipboard.copy(subscription.url.absoluteString) }
                    if let support = subscription.info.supportURL {
                        Button("Поддержка", systemImage: "questionmark.bubble") { openURL(support) }
                    }
                    Button("Удалить подписку", systemImage: "trash", role: .destructive) { confirmDelete = true }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.medium))
                    .frame(width: 32, height: 28)
                    .contentShape(.rect)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Действия с подпиской")
        }
        .confirmationDialog(String(format: L("Удалить «%@»?"), subscription.name), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { withAnimation(.smooth) { library.remove(subscription) }; Toaster.shared.show(L("Подписка удалена")) }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text(String(format: L("%lld %@ пропадут из списка. Подписку можно добавить снова по ссылке."), subscription.servers.count, serversWord(subscription.servers.count)))
        }
    }

    private var subtitle: String {
        var parts = ["\(subscription.servers.count) \(serversWord(subscription.servers.count))"]
        if let date = subscription.updatedAt { parts.append(date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))) }
        return "· " + parts.joined(separator: " · ")
    }

    private var usage: some View {
        let info = subscription.info
        let limited = (info.total ?? 0) > 0
        let fraction = limited ? Double(info.used ?? 0) / Double(info.total ?? 1) : 0
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let used = info.used {
                    Text(limited ? String(format: L("%@ из %@"), bytes(used), bytes(info.total ?? 0)) : String(format: L("%@ · безлимит"), bytes(used)))
                        .foregroundStyle(fraction > 0.9 ? Color.alert : .primary)
                }
                Spacer()
                if let expire = info.expire {
                    let days = Int((expire.timeIntervalSinceNow / 86400).rounded(.up))
                    Text(expire < .now ? L("Истекла") : String(format: L("%lld дн. · до %@"), days, expire.formatted(.dateTime.day().month(.abbreviated))))
                        .foregroundStyle(expire < .now || days <= 3 ? Color.alert : .secondary)
                }
            }
            .font(.subheadline.monospacedDigit())
            if limited {
                ProgressView(value: min(fraction, 1)).tint(fraction > 0.9 ? Color.alert : theme.accent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .binary)
    }
}

// MARK: - Manual servers

private struct ManualCard: View {
    let library: Library
    @Binding var editing: ServerConfig?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Мои серверы").font(.subheadline.weight(.semibold)).padding(.horizontal, 6)
            Surface { ServerRows(library: library, servers: library.manual, editing: $editing) }
            Text("Удерживайте сервер, чтобы изменить").font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 6)
        }
    }
}

// MARK: - Server rows

private struct ServerRows: View {
    @Environment(\.kitsuneTheme) private var theme
    let library: Library
    let servers: [ServerConfig]
    var editing: Binding<ServerConfig?>?
    @AppStorage("serverSort") private var sort = "default"
    @AppStorage("compactServers") private var compact = false
    @AppStorage("hideSilent") private var hideSilent = false
    @State private var heat: ServerConfig?
    @State private var folded: Set<String> = []
    @State private var showSilent = false
    @State private var deleting: ServerConfig?
    @Environment(SelectedRowVisibility.self) private var selectedRow: SelectedRowVisibility?

    /// Servers that failed three checks in a row go to a folded "Не отвечают" group at the bottom (never the selected one).
    private var silentOnes: [ServerConfig] {
        guard hideSilent, query.isEmpty else { return [] }
        return ordered.filter { library.silent.contains($0.id) && $0.id != library.selected?.id }
    }
    private var visible: [ServerConfig] {
        let hidden = Set(silentOnes.map(\.id))
        return hidden.isEmpty ? ordered : ordered.filter { !hidden.contains($0.id) }
    }

    @Environment(\.serverQuery) private var query

    private var ordered: [ServerConfig] {
        let servers = query.isEmpty ? servers : servers.filter { $0.displayName.localizedCaseInsensitiveContains(query) || $0.summary.localizedCaseInsensitiveContains(query) }
        let sorted: [ServerConfig] = switch sort {
        case "ping": servers.sorted { (library.pings[$0.id]?.milliseconds ?? .max) < (library.pings[$1.id]?.milliseconds ?? .max) }
        case "country": servers.sorted { ($0.flag ?? "\u{10FFFF}", $0.displayName) < ($1.flag ?? "\u{10FFFF}", $1.displayName) }
        default: servers
        }
        // Pinned first; the sort is stable, so the chosen order holds inside both groups.
        return sorted.filter { library.pinned.contains($0.id) } + sorted.filter { !library.pinned.contains($0.id) }
    }

    /// "По стране": servers grouped by country, each group folds; nil = a flat list.
    private var groups: [(code: String, servers: [ServerConfig])]? {
        guard sort == "country", query.isEmpty else { return nil }
        var order: [String] = [], byCode: [String: [ServerConfig]] = [:]
        for server in visible {
            let code = server.countryCode ?? "—"
            if byCode[code] == nil { order.append(code) }
            byCode[code, default: []].append(server)
        }
        return order.count > 1 ? order.map { ($0, byCode[$0]!) } : nil
    }

    var body: some View {
        // Lazy: a subscription can hold dozens of servers, and building every row at once made the tab stutter.
        LazyVStack(spacing: 0) {
            if let groups {
                ForEach(groups, id: \.code) { group in
                    countryHeader(group.code, servers: group.servers)
                    if !folded.contains(group.code) { rows(group.servers) }
                    if group.code != groups.last?.code { Divider().opacity(0.5) }
                }
            } else {
                rows(visible)
            }
            let silent = silentOnes
            if !silent.isEmpty {
                if !visible.isEmpty { Divider().opacity(0.5) }
                Button { withAnimation(.smooth(duration: 0.25)) { showSilent.toggle() } } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "moon.zzz").foregroundStyle(.secondary).frame(width: 32)
                        Text("Не отвечают").font(.subheadline.weight(.semibold))
                        Text("\(silent.count)").font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.down").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                            .rotationEffect(.degrees(showSilent ? 0 : -90))
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                if showSilent { rows(silent) }
            }
        }
        .sensoryFeedback(.selection, trigger: library.selected?.id)
        .onChange(of: library.selected?.id) { Feedback.sound("Tink", volume: 0.3) }
        .sheet(item: $heat) { PingHeatmapView(server: $0) }
        .confirmationDialog(String(format: L("Удалить «%@»?"), deleting?.displayName ?? ""), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { if let deleting { withAnimation(.smooth) { library.remove(deleting) } } }
        }
    }

    /// Country line: flag, name, how many servers and the best ping among them; tap folds the group.
    private func countryHeader(_ code: String, servers: [ServerConfig]) -> some View {
        let best = servers.min { (library.pings[$0.id]?.milliseconds ?? .max) < (library.pings[$1.id]?.milliseconds ?? .max) }
        let hasSelected = servers.contains { $0.id == library.selected?.id }
        return Button {
            withAnimation(.smooth(duration: 0.25)) { if folded.contains(code) { folded.remove(code) } else { folded.insert(code) } }
        } label: {
            HStack(spacing: 10) {
                Text(servers.first?.flag ?? "🌐").font(.title3).frame(width: 32)
                Text(Locale.current.localizedString(forRegionCode: code) ?? L("Без страны")).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text("\(servers.count)").font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                if hasSelected { Circle().fill(theme.accent).frame(width: 6, height: 6) }
                Spacer(minLength: 8)
                if folded.contains(code), let best { PingLabel(ping: library.pings[best.id]) }
                Image(systemName: "chevron.down").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    .rotationEffect(.degrees(folded.contains(code) ? -90 : 0))
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityValue(folded.contains(code) ? L("Свёрнуто") : L("Развёрнуто"))
    }

    @ViewBuilder private func rows(_ list: [ServerConfig]) -> some View {
            ForEach(list) { server in
                ServerRow(server: server, selected: library.selected?.id == server.id, pinned: library.pinned.contains(server.id), dimmed: library.silent.contains(server.id) && library.selected?.id != server.id, ping: library.pings[server.id], history: library.pingHistory[server.id] ?? [], compact: compact) {
                    withAnimation(.smooth(duration: 0.25)) { library.selectedID = server.id }
                }
                .rowSwipe(
                    leading: (library.pinned.contains(server.id) ? "pin.slash.fill" : "pin.fill", theme.accent),
                    trailing: editing == nil ? nil : ("trash.fill", Color(red: 0.86, green: 0.25, blue: 0.22)),
                    onLeading: { withAnimation(.smooth) { if library.pinned.contains(server.id) { library.pinned.remove(server.id) } else { library.pinned.insert(server.id) } } },
                    onTrailing: { deleting = server })
                .id(server.id)
                .onScrollVisibilityChange(threshold: 0.3) { visible in
                    if library.selected?.id == server.id { selectedRow?.visible = visible }
                }
                .contextMenu {
                    Button("Выбрать", systemImage: "checkmark.circle") { withAnimation(.smooth(duration: 0.25)) { library.selectedID = server.id } }
                        .disabled(library.selected?.id == server.id)
                    #if os(macOS)
                    Button(library.routing.entryServerID == server.id ? L("Не использовать как входной") : L("Сделать входным (двойной прыжок)"), systemImage: "point.3.connected.trianglepath.dotted") {
                        library.routing.entryServerID = library.routing.entryServerID == server.id ? nil : server.id
                    }
                    #endif
                    Divider()
                    Button(library.pinned.contains(server.id) ? L("Открепить") : L("Закрепить"), systemImage: library.pinned.contains(server.id) ? "pin.slash" : "pin") {
                        withAnimation(.smooth) { if library.pinned.contains(server.id) { library.pinned.remove(server.id) } else { library.pinned.insert(server.id) } }
                    }
                    Button("Проверить пинг", systemImage: "speedometer") { Task { await library.ping([server]) } }
                    Button("Пинг по часам", systemImage: "chart.bar.xaxis") { heat = server }
                    if let link = server.link { Button("Копировать ссылку", systemImage: "doc.on.doc") { Clipboard.copy(link) } }
                    if let editing {
                        Button("Изменить", systemImage: "pencil") { editing.wrappedValue = server }
                        Button("Удалить", systemImage: "trash", role: .destructive) { library.remove(server) }
                    }
                }
                if server.id != list.last?.id { Divider().opacity(0.5).padding(.leading, 60) }
            }
    }
}

private struct ServerRow: View {
    @Environment(\.kitsuneTheme) private var theme
    let server: ServerConfig
    let selected: Bool
    var pinned = false
    var dimmed = false
    let ping: Ping?
    var history: [Int] = []
    var compact = false
    var onSelect: () -> Void
    @State private var flipped = false

    /// Back of the card: country, endpoint and what the hourly stats say.
    private var back: some View {
        let hours = PingStats.averages(server.id)
        let best = hours.enumerated().compactMap { h in h.element.map { (h.offset, $0) } }.min { $0.1 < $1.1 }
        let country = server.countryCode.flatMap { Locale.current.localizedString(forRegionCode: $0) } ?? server.summary
        return HStack(spacing: 12) {
            Image(systemName: "arrow.uturn.backward").foregroundStyle(.secondary).frame(width: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(country) · \(server.host):\(server.port)").font(.subheadline).lineLimit(1)
                Text(best.map { String(format: L("Быстрее всего около %lld:00, в среднем %lld мс"), $0.0, $0.1) } ?? L("Пока нет статистики по часам"))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
        }
    }

    var body: some View {
        // A flipped card turns back on any tap; only the front selects the server.
        Button { if flipped { withAnimation(.spring(duration: 0.5, bounce: 0.2)) { flipped = false } } else { onSelect() } } label: {
            ZStack {
            back.opacity(flipped ? 1 : 0).rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
            HStack(spacing: 12) {
                Group {
                    if let flag = server.flag {
                        Text(flag).font(.title3)
                    } else {
                        Image(systemName: "globe").foregroundStyle(.secondary)
                    }
                }
                .frame(width: 32)
                .contentShape(.rect)
                .onTapGesture { withAnimation(.spring(duration: 0.5, bounce: 0.2)) { flipped.toggle() } }

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(server.displayName).font(.body).lineLimit(1)
                        if pinned { Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.secondary) }
                    }
                    if !compact { Text(server.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer(minLength: 8)
                if selected, history.count >= 3 { PingSpark(values: history, color: PingLabel.color(for: ping)).transition(.opacity) }
                PingLabel(ping: ping)
                Image(systemName: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.accent)
                    .opacity(selected ? 1 : 0)
                    .scaleEffect(selected ? 1 : 0.6)
            }
            .opacity(flipped ? 0 : 1)
            .opacity(dimmed ? 0.45 : 1)
            }
            .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
            .overlay(alignment: .leading) { // outside the rotation, so the tick stays on the left of a flipped card
                Capsule().fill(CountryColor.of(server.countryCode)).frame(width: 3, height: 26).offset(x: -10).opacity(0.85)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, compact ? 4 : 10)
            .frame(minHeight: compact ? 34 : 48)
            .animation(.smooth(duration: 0.25), value: compact)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue(ping?.accessibilityText ?? "")
    }
}

/// Signal-strength style bars: how good the connection to the server is, in colour instead of digits.
private struct PingLabel: View {
    let ping: Ping?

    /// 1 (bad) ... 4 (excellent). A full request through the server is slower than a handshake, so the scales differ.
    static func level(for ping: Ping?) -> Int? {
        switch ping {
        case .tunnel(let ms): ms < 250 ? 4 : ms < 600 ? 3 : ms < 1500 ? 2 : 1
        case .ms(let ms): ms < 80 ? 4 : ms < 150 ? 3 : ms < 400 ? 2 : 1
        case .failed: 0
        default: nil
        }
    }

    static func color(for ping: Ping?) -> Color {
        switch level(for: ping) {
        case 4: Color(red: 0.35, green: 0.85, blue: 0.50)
        case 3: Color(red: 0.70, green: 0.86, blue: 0.32)
        case 2: Color(red: 1.0, green: 0.70, blue: 0.20)
        default: Color.alert
        }
    }

    var body: some View {
        switch ping {
        case .none, .unavailable: EmptyView()
        case .measuring: ProgressView().controlSize(.mini).tint(.white)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(Color.alert).help("нет связи")
        case .ms(let ms), .tunnel(let ms):
            let level = Self.level(for: ping) ?? 1
            HStack(alignment: .bottom, spacing: 2.5) {
                ForEach(1...4, id: \.self) { bar in
                    Capsule()
                        .fill(bar <= level ? Self.color(for: ping) : .white.opacity(0.14))
                        .frame(width: 4, height: CGFloat(4 + bar * 3))
                }
            }
            .frame(height: 16)
            .animation(.smooth, value: level)
            .help(String(format: L("%lld мс"), ms))
        }
    }
}

/// Last measurements of the active server as a tiny line.
private struct PingSpark: View {
    let values: [Int]
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let low = Double(values.min() ?? 0), high = Double(values.max() ?? 1)
            let span = max(high - low, 20)
            let step = proxy.size.width / CGFloat(max(values.count - 1, 1))
            Path { path in
                for (index, value) in values.enumerated() {
                    let point = CGPoint(x: CGFloat(index) * step, y: proxy.size.height * (1 - CGFloat((Double(value) - low) / span)) * 0.8 + proxy.size.height * 0.1)
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
            }
            .stroke(color.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 44, height: 16)
        .accessibilityHidden(true)
    }
}

extension Ping {
    var accessibilityText: String {
        switch self {
        case .measuring: L("Измеряется пинг")
        case .ms(let ms): String(format: L("Пинг до сервера %lld миллисекунд"), ms)
        case .tunnel(let ms): String(format: L("Задержка через сервер %lld миллисекунд"), ms)
        case .failed: L("Сервер не отвечает")
        case .unavailable: ""
        }
    }
}

private func serversWord(_ n: Int) -> String {
    let mod10 = n % 10, mod100 = n % 100
    if mod10 == 1 && mod100 != 11 { return L("сервер") }
    if (2...4).contains(mod10) && !(12...14).contains(mod100) { return L("сервера") }
    return L("серверов")
}

// MARK: - Sheets

private struct AddSheet: View {
    let library: Library
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var error: String?
    @State private var busy = false
    /// A subscription is shown before it is added: what is inside, how much is left, until when.
    @State private var preview: (url: URL, data: Library.Fetched)?

    private var subscriptionURL: URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), ["http", "https"].contains(url.scheme?.lowercased()) else { return nil }
        return url
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Ссылка на подписку (https://…) или на сервер (vless://, hysteria2://).")
                        .font(.footnote)
                        .opacity(0.8)
                    LinkField(link: $text, error: error)
                        .onChange(of: text) { error = nil; preview = nil }
                    if let preview { PreviewCard(url: preview.url, data: preview.data).transition(.blurReplace) }
                }
                .animation(.smooth, value: preview?.url)
                .padding(20)
            }
            .navigationTitle("Добавить")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if busy {
                        ProgressView()
                    } else {
                        Button(subscriptionURL != nil && preview == nil ? L("Проверить") : L("Добавить"), systemImage: "checkmark") { save() }
                            .disabled(text.isEmpty)
                    }
                }
            }
        }
        .adaptiveSheet()
        .interactiveDismissDisabled(busy)
    }

    private func save() {
        busy = true
        Task {
            defer { busy = false }
            do {
                if let url = subscriptionURL {
                    guard let preview, preview.url == url else {
                        preview = (url, try await Library.fetch(url)) // first press: look inside
                        return
                    }
                    try await library.addSubscription(url, prefetched: preview.data)
                } else {
                    try await library.add(any: text)
                }
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// What a subscription holds, shown before adding it.
struct PreviewCard: View {
    @Environment(\.kitsuneTheme) private var theme
    let url: URL
    let data: Library.Fetched

    var body: some View {
        let info = data.info
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "tray.full.fill").foregroundStyle(theme.accent)
                    .frame(width: 32, height: 32)
                    .background(theme.accent.opacity(0.18), in: .rect(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.title ?? url.host() ?? L("Подписка")).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text("\(data.servers.count) \(serversWord(data.servers.count))" + (data.skipped > 0 ? String(format: L(" · пропущено неподдерживаемых: %lld"), data.skipped) : ""))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if !data.countries.isEmpty {
                Text(data.countries.prefix(16).joined(separator: " ") + (data.countries.count > 16 ? " +\(data.countries.count - 16)" : ""))
                    .font(.title3)
            }
            if info.used != nil || info.expire != nil {
                HStack {
                    if let used = info.used {
                        Text((info.total ?? 0) > 0
                             ? String(format: L("%@ из %@"), bytes(used), bytes(info.total ?? 0))
                             : String(format: L("%@ · безлимит"), bytes(used)))
                    }
                    Spacer()
                    if let expire = info.expire {
                        Text(expire < .now ? L("Истекла") : String(format: L("до %@"), expire.formatted(.dateTime.day().month(.abbreviated).year())))
                            .foregroundStyle(expire < .now ? Color.alert : .secondary)
                    }
                }
                .font(.footnote.monospacedDigit())
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kGlass(in: .rect(cornerRadius: 20))
    }

    private func bytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .binary) }
}

private struct EditServerSheet: View {
    let library: Library
    let server: ServerConfig
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                LinkField(link: $text, error: error, placeholder: "Ссылка на сервер")
                    .onChange(of: text) { error = nil }
                    .padding(20)
            }
            .navigationTitle(server.displayName)
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить", systemImage: "checkmark") {
                        do {
                            try library.replace(server, link: text)
                            dismiss()
                        } catch {
                            self.error = VPNManager.describe(error)
                        }
                    }
                    .disabled(text.isEmpty)
                }
            }
        }
        .adaptiveSheet()
        .onAppear { text = server.link ?? "" }
    }
}

// MARK: - Row swipe

/// Drag a row sideways: right pins, left deletes (when allowed). Past the threshold the action fires on release.
/// List's own swipeActions need a List; these rows live in a lazy stack, so the gesture is built by hand.
private struct RowSwipe: ViewModifier {
    typealias Action = (icon: String, tint: Color)
    let leading: Action?
    let trailing: Action?
    let onLeading: () -> Void
    let onTrailing: () -> Void
    @State private var dx: CGFloat = 0
    private let threshold: CGFloat = 76

    private var armed: Bool { abs(dx) >= threshold }

    func body(content: Content) -> some View {
        content
            .offset(x: dx)
            .background {
                HStack(spacing: 0) {
                    reveal(leading, width: max(dx, 0))
                    Spacer(minLength: 0)
                    reveal(trailing, width: max(-dx, 0))
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 18)
                    .onChanged { value in
                        let w = value.translation.width
                        // Mostly vertical drags belong to scrolling.
                        guard abs(w) > abs(value.translation.height) * 1.6 else { return }
                        let allowed = w > 0 ? leading != nil : trailing != nil
                        dx = allowed ? w * 0.8 : w * 0.12
                    }
                    .onEnded { _ in
                        let fired = dx
                        withAnimation(.spring(duration: 0.35, bounce: 0.25)) { dx = 0 }
                        if abs(fired) >= threshold { Feedback.sound("Pop", volume: 0.3) }
                        if fired >= threshold, leading != nil { onLeading() }
                        else if fired <= -threshold, trailing != nil { onTrailing() }
                    }
            )
            .sensoryFeedback(.impact(weight: .light), trigger: armed) { _, new in new }
            .onChange(of: armed) { _, new in if new { Feedback.tap() } }
    }

    @ViewBuilder private func reveal(_ action: Action?, width: CGFloat) -> some View {
        if let action, width > 0 {
            ZStack {
                action.tint.opacity(0.28)
                Image(systemName: action.icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(action.tint)
                    .scaleEffect(width >= threshold ? 1.15 : 0.85)
                    .opacity(min(1, Double(width) / 40))
            }
            .frame(width: width)
        }
    }
}

private extension View {
    func rowSwipe(leading: (icon: String, tint: Color)?, trailing: (icon: String, tint: Color)?, onLeading: @escaping () -> Void, onTrailing: @escaping () -> Void) -> some View {
        modifier(RowSwipe(leading: leading, trailing: trailing, onLeading: onLeading, onTrailing: onTrailing))
    }
}

// MARK: - Map

/// Servers on a world map: a pin per country, coloured by its best ping; a tap lists that country's servers below.
private struct ServersMap: View {
    @Environment(\.kitsuneTheme) private var theme
    let library: Library
    @State private var focus: String?
    @State private var camera = MapCameraPosition.automatic

    private struct Pin: Identifiable {
        let code: String
        let coordinate: CLLocationCoordinate2D
        let servers: [ServerConfig]
        var id: String { code }
    }

    private var pins: [Pin] {
        Dictionary(grouping: library.allServers, by: { $0.countryCode?.uppercased() ?? "" })
            .compactMap { code, servers in CountryGeo.coordinate(code).map { Pin(code: code, coordinate: $0, servers: servers) } }
            .sorted { $0.code < $1.code }
    }

    private func best(_ pin: Pin) -> Ping? {
        pin.servers.compactMap { library.pings[$0.id] }.min { ($0.milliseconds ?? .max) < ($1.milliseconds ?? .max) }
    }

    private var unplaced: Int { library.allServers.count - pins.reduce(0) { $0 + $1.servers.count } }

    var body: some View {
        let pins = pins
        VStack(spacing: 10) {
            Map(position: $camera) {
                ForEach(pins) { pin in
                    Annotation(Locale.current.localizedString(forRegionCode: pin.code) ?? pin.code, coordinate: pin.coordinate, anchor: .center) {
                        let isSelected = pin.servers.contains { $0.id == library.selected?.id }
                        Button {
                            withAnimation(.smooth) {
                                focus = focus == pin.code ? nil : pin.code
                                camera = focus == nil ? .automatic : .region(MKCoordinateRegion(center: pin.coordinate, span: MKCoordinateSpan(latitudeDelta: 28, longitudeDelta: 28)))
                            }
                        } label: {
                            Text("\(pin.servers.count)")
                                .font(.caption2.weight(.bold).monospacedDigit())
                                .foregroundStyle(.black.opacity(0.8))
                                .frame(minWidth: 22, minHeight: 22)
                                .background(PingLabel.color(for: best(pin)), in: .circle)
                                .overlay(Circle().stroke(isSelected ? theme.accent : .white.opacity(0.7), lineWidth: isSelected ? 3 : 1.5))
                                .scaleEffect(focus == pin.code ? 1.3 : 1)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Locale.current.localizedString(forRegionCode: pin.code) ?? pin.code)
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
            .mapControlVisibility(.hidden)
            .colorScheme(.dark)
            .clipShape(.rect(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.1), lineWidth: 0.6))
            .padding(.horizontal, 16)

            if let focus, let pin = pins.first(where: { $0.code == focus }) {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(pin.servers) { server in
                            ServerRow(server: server, selected: library.selected?.id == server.id, pinned: library.pinned.contains(server.id), ping: library.pings[server.id], history: library.pingHistory[server.id] ?? [], compact: true) {
                                withAnimation(.smooth(duration: 0.25)) { library.selectedID = server.id }
                            }
                        }
                    }
                }
                .frame(maxHeight: 170)
                .kGlass(in: .rect(cornerRadius: 22))
                .padding(.horizontal, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                Text(unplaced > 0 ? String(format: L("Нажмите на метку страны. Серверов без страны: %lld"), unplaced) : L("Нажмите на метку страны, чтобы увидеть её серверы"))
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(minHeight: 28)
            }
        }
        .padding(.bottom, 16)
        .sensoryFeedback(.selection, trigger: focus)
    }
}
