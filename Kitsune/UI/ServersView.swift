import Shared
import SwiftUI

extension EnvironmentValues {
    @Entry var serverQuery = ""
}

/// Subscriptions and manual servers: refresh, traffic, expiry, announcements, ping, selection.
struct ServersView: View {
    let library: Library
    let tunnelUp: Bool

    @State var adding = false
    @State private var editing: ServerConfig?
    @State private var query = ""
    @State var pinging = false
    @AppStorage("serverSort") var sort = "default"

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
        .glassEffect(.regular, in: .capsule)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 12) {
                ScreenHeader(title: "Серверы", subtitle: pingSubtitle) { toolbarActions }
                if library.isEmpty {
                    ContentUnavailableView {
                        Label("Нет серверов", systemImage: "server.rack")
                    } description: {
                        Text("Добавьте ссылку на подписку или на сервер.")
                    } actions: {
                        Button("Добавить", systemImage: "plus") { adding = true }
                            .buttonStyle(.brand)
                    }
                } else {
                    ScrollView {
                        Group {
                            LazyVStack(spacing: 22) {
                                if library.allServers.count > 12 { searchField }
                                if library.allServers.count > 12, query.isEmpty, !library.recent.isEmpty { recentRow }
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
                }
                }
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
        Menu("Сортировка", systemImage: "arrow.up.arrow.down") {
            Picker("Сортировка", selection: $sort) {
                Text("Как в подписке").tag("default")
                Text("По пингу").tag("ping")
                Text("По стране").tag("country")
            }
            .pickerStyle(.inline)
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
            .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
}

private struct SubscriptionCard: View {
    let library: Library
    let subscription: Subscription

    @Environment(\.openURL) private var openURL
    @State private var announceExpanded = false
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
                        ServerRows(library: library, servers: subscription.servers)
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
                    Button("Удалить подписку", systemImage: "trash", role: .destructive) { library.remove(subscription) }
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
                ProgressView(value: min(fraction, 1)).tint(fraction > 0.9 ? Color.alert : Color(red: 1.0, green: 0.50, blue: 0.10))
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
    let library: Library
    let servers: [ServerConfig]
    var editing: Binding<ServerConfig?>?
    @AppStorage("serverSort") private var sort = "default"
    @State private var heat: ServerConfig?

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

    var body: some View {
        // Lazy: a subscription can hold dozens of servers, and building every row at once made the tab stutter.
        LazyVStack(spacing: 0) {
            ForEach(ordered) { server in
                ServerRow(server: server, selected: library.selected?.id == server.id, pinned: library.pinned.contains(server.id), ping: library.pings[server.id], history: library.pingHistory[server.id] ?? []) {
                    withAnimation(.smooth(duration: 0.25)) { library.selectedID = server.id }
                }
                .contextMenu {
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
                if server.id != ordered.last?.id { Divider().opacity(0.5).padding(.leading, 60) }
            }
        }
        .sensoryFeedback(.selection, trigger: library.selected?.id)
        .sheet(item: $heat) { PingHeatmapView(server: $0) }
    }
}

private struct ServerRow: View {
    let server: ServerConfig
    let selected: Bool
    var pinned = false
    let ping: Ping?
    var history: [Int] = []
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
                    Text(server.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                if selected, history.count >= 3 { PingSpark(values: history, color: PingLabel.color(for: ping)).transition(.opacity) }
                PingLabel(ping: ping)
                Image(systemName: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(red: 1.0, green: 0.50, blue: 0.10))
                    .opacity(selected ? 1 : 0)
                    .scaleEffect(selected ? 1 : 0.6)
            }
            .opacity(flipped ? 0 : 1)
            }
            .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
            .overlay(alignment: .leading) { // outside the rotation, so the tick stays on the left of a flipped card
                Capsule().fill(CountryColor.of(server.countryCode)).frame(width: 3, height: 26).offset(x: -10).opacity(0.85)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 48)
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Ссылка на подписку (https://…) или на сервер (vless://, hysteria2://).")
                        .font(.footnote)
                        .opacity(0.8)
                    LinkField(link: $text, error: error)
                        .onChange(of: text) { error = nil }
                }
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
                        Button("Добавить", systemImage: "checkmark") { save() }
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
                try await library.add(any: text)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
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
