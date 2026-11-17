import SwiftUI

/// Shown once after an update (never on the very first launch) and from Settings.
struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss

    private let items: [(icon: String, color: Color, title: String, text: String)] = [
        ("rectangle.compress.vertical", .orange, "Главная без прокрутки", "Когда появляются карточки, кнопка с лисой плавно уменьшается, и всё помещается в окно."),
        ("gearshape.fill", .blue, "Новые настройки", "Сверху паспорт: версия, трафик за неделю и итог проверки утечек."),
        ("square.grid.2x2.fill", .purple, "Плитки вместо ленты", "Каждый раздел открывается отдельно, а на плитке видно, что включено."),
        ("paintpalette.fill", .pink, "Живое превью", "В «Дизайне» кнопка меняется сразу, пока вы выбираете цвет и сезон."),
        ("checkmark.shield.fill", .green, "Защита в трёх кольцах", "IP, DNS и IPv6: сразу видно, всё ли в порядке."),
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
