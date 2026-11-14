import Shared
import SwiftUI

/// Three glass cards: what Kitsune is → "Russia direct" routing → VPN permission and first server.
struct OnboardingView: View {
    let vpn: VPNManager
    let library: Library
    var onFinish: () -> Void

    @State private var page = 0
    @State private var forward = true
    @State private var link = ""
    @State private var linkError: String?
    @State private var permissionGranted = false
    @State private var askingPermission = false
    @State private var adding = false

    var body: some View {
        ZStack {
            KitsuneBackground(mood: .idle)
                .foregroundStyle(.white)
            VStack(spacing: 24) {
                #if os(iOS)
                TabView(selection: $page) {
                    welcome.tag(0)
                    routing.tag(1)
                    setup.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .interactive))
                #else
                // macOS has no paging TabView: one card at a time, sliding in the direction of travel.
                Group {
                    switch page {
                    case 0: welcome
                    case 1: routing
                    default: setup
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
                .id(page)
                HStack(spacing: 10) {
                    ForEach(0..<3) { index in
                        Button { go(to: index) } label: {
                            Capsule()
                                .fill(index == page ? Color.white : Color.white.opacity(0.4))
                                .frame(width: index == page ? 22 : 7, height: 7)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Шаг \(index + 1)")
                    }
                }
                .animation(.smooth, value: page)
                #endif

                HStack(spacing: 12) {
                    #if os(macOS)
                    if page > 0 {
                        Button("Назад") { go(to: page - 1) }
                            .buttonStyle(.brand)
                            .keyboardShortcut(.leftArrow, modifiers: [])
                            .transition(.opacity)
                    }
                    #endif
                    Button { advance() } label: {
                        if adding { ProgressView() } else { Text(page < 2 ? L("Далее") : L("Готово")) }
                    }
                    .buttonStyle(.brand)
                    .keyboardShortcut(.defaultAction)
                    .disabled(page == 2 && (!canFinish || adding))
                }
                .animation(.smooth, value: page)
                .padding(.bottom, 8)
            }
        }
        .sensoryFeedback(.selection, trigger: page)
    }

    // MARK: Pages

    private var welcome: some View {
        Page {
            FoxMark(color: Color(red: 0.96, green: 0.80, blue: 0.62))
                .frame(width: 64)
            Text("Kitsune").font(.display(30, relativeTo: .largeTitle))
            Text("VPN, который не мешает. Российские сайты открываются как обычно, всё остальное идёт через защищённый туннель.")
                .foregroundStyle(.secondary)
        }
    }

    private var routing: some View {
        Page {
            Text("Что работает без VPN").font(.display(22))
            Text("Банки, маркетплейсы, Госуслуги и другие российские сервисы. Настраивать ничего не нужно, список можно изменить позже на вкладке «Маршруты».")
                .foregroundStyle(.secondary)
            GlassGroup(spacing: 8) {
                FlowChips(items: ["Банки", "Ozon", "Wildberries", "Госуслуги", "Яндекс", "VK", "Такси", "Доставка"])
            }
        }
    }

    private var setup: some View {
        Page {
            Text("Добавьте сервер").font(.display(22))
            #if os(macOS)
            Text("Вставьте ссылку на сервер или подписку. При первом подключении macOS один раз попросит пароль администратора: он нужен для создания туннеля. Kitsune его не видит и не хранит.")
                .foregroundStyle(.secondary)
            #else
            Text("Вставьте ссылку на сервер или подписку. \(systemName) попросит разрешить добавить VPN-конфигурацию. Kitsune не видит, какие сайты вы открываете.")
                .foregroundStyle(.secondary)
            Button {
                Task { await requestPermission() }
            } label: {
                Label(permissionGranted ? L("VPN разрешён") : L("Разрешить VPN"), systemImage: permissionGranted ? "checkmark" : "network.badge.shield.half.filled")
            }
            .buttonStyle(.glass)
            .disabled(permissionGranted || askingPermission)
            if !permissionGranted, let error = vpn.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(Color.alert)
            }
            #endif
            LinkField(link: $link, error: linkError)
                .onChange(of: link) { linkError = nil }
        }
    }

    // MARK: Actions

    // Permission is not required here: connecting asks again if the user skipped or declined.
    private var canFinish: Bool { !link.isEmpty }

    private func go(to target: Int) {
        guard target != page else { return }
        forward = target > page
        withAnimation(.smooth) { page = target }
    }

    private func advance() {
        guard page == 2 else {
            go(to: page + 1)
            return
        }
        adding = true
        Task {
            defer { adding = false }
            do {
                try await library.add(any: link)
                onFinish()
            } catch {
                linkError = error.localizedDescription
            }
        }
    }

    private func requestPermission() async {
        askingPermission = true
        defer { askingPermission = false }
        if await vpn.installProfile() {
            withAnimation(.smooth) { permissionGranted = true }
        }
    }
}

private var systemName: String {
    #if os(macOS)
    "macOS"
    #else
    "iOS"
    #endif
}


/// One onboarding page: left-aligned text on the background, no panel.
private struct Page<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) { content }
                .frame(maxWidth: 440, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .defaultScrollAnchor(.center)
    }
}

/// Glass chips that wrap onto new lines.
private struct FlowChips: View {
    let items: [String]

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { item in
                Text(LocalizedStringKey(item))
                    .font(.subheadline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .kGlass(in: .capsule)
            }
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(width: proposal.width ?? .infinity, subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(width: bounds.width, subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func rows(width: CGFloat, _ subviews: Subviews) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if let last = rows.last, last.width + spacing + size.width <= width {
                rows[rows.count - 1].indices.append(index)
                rows[rows.count - 1].width += spacing + size.width
                rows[rows.count - 1].height = max(last.height, size.height)
            } else {
                rows.append(([index], size.width, size.height))
            }
        }
        return rows
    }
}
