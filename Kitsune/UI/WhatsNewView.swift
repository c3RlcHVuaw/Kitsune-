import SwiftUI

/// Shown once after an update (never on the very first launch) and from Settings.
struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss

    private let items: [(icon: String, color: Color, title: String, text: String)] = [
        ("arrow.down.circle.fill", .orange, "Обновление в один клик", "Плашка на главной сама находит новую версию и переустанавливает Kitsune."),
        ("arrow.up.and.down.text.horizontal", .blue, "Главная прокручивается", "Если всё не помещается в окно, экран плавно скроллится."),
        ("macbook", .teal, "Работает на macOS 15", "Старые Маки, в том числе с Intel, теперь тоже поддерживаются."),
        ("rectangle.3.group.fill", .purple, "Главная под себя", "В настройках блоки можно скрывать и перетаскивать местами."),
        ("chart.bar.fill", .green, "Новый вид скорости", "Две колонки с числами и тонкие столбики вместо линий."),
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
