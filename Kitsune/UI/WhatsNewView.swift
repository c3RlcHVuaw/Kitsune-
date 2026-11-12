import SwiftUI

/// Shown once after an update (never on the very first launch) and from Settings.
struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss

    private let items: [(icon: String, color: Color, title: String, text: String)] = [
        ("rectangle.3.group.fill", .orange, "Главная под себя", "В настройках блоки можно скрывать и перетаскивать местами."),
        ("chart.bar.fill", .blue, "Новый вид скорости", "Две колонки с числами и тонкие столбики вместо линий."),
        ("square.grid.3x3.fill", .green, "Кто потребляет", "Спокойная карточка с иконками и полосками, без прыжков."),
        ("photo.fill", .pink, "Карточка «мой Kitsune»", "Часы защиты, серии и значки одной картинкой, без личных данных."),
        ("sparkles", .purple, "Лиса в меню-баре", "Спит при выключенном VPN и виляет ушами, пока идёт трафик."),
    ]

    var body: some View {
        VStack(spacing: 18) {
            FoxMark(color: .brand).frame(width: 52)
            Text("Что нового").font(.display(22, relativeTo: .title))
            VStack(alignment: .leading, spacing: 14) {
                ForEach(items, id: \.title) { item in
                    HStack(spacing: 14) {
                        Image(systemName: item.icon)
                            .font(.title3).foregroundStyle(item.color)
                            .frame(width: 42, height: 42)
                            .background(item.color.opacity(0.16), in: .rect(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(LocalizedStringKey(item.title)).font(.subheadline.weight(.semibold))
                            Text(LocalizedStringKey(item.text)).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Button("Понятно") { dismiss() }.buttonStyle(.brand).frame(maxWidth: .infinity)
        }
        .padding(24)
        .frame(minWidth: 380)
    }
}

/// Presents the sheet when the app version differs from the one seen last.
struct WhatsNewModifier: ViewModifier {
    @AppStorage("lastSeenVersion") private var lastSeen = ""
    @AppStorage("onboardingDone") private var onboardingDone = false
    @State private var show = false

    func body(content: Content) -> some View {
        content
            .task {
                let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
                defer { lastSeen = current }
                show = onboardingDone && !lastSeen.isEmpty && lastSeen != current
            }
            .sheet(isPresented: $show) { WhatsNewView() }
    }
}
