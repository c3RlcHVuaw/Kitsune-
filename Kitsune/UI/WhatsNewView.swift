import SwiftUI

/// Shown once after an update (never on the very first launch) and from Settings.
struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss

    private let items: [(icon: String, color: Color, title: String, text: String)] = [
        ("paintpalette.fill", .orange, "Темы за звания", "Северное сияние, Закат, Кицунэби и Золото ёкая открываются по мере того, как растёт ваше звание."),
        ("exclamationmark.bubble.fill", .blue, "Ошибка с выходом", "Под ошибкой сразу кнопки: другой сервер, повторить, диагностика. А если сервер сменил ключи, подписка обновится сама."),
        ("rectangle.split.2x1.fill", .purple, "Два столбца", "В широком окне рядом с главной виден список серверов."),
        ("tray.full.fill", .green, "Подписка до добавления", "Перед добавлением видно, что внутри: серверы, страны, трафик и срок."),
        ("questionmark.circle.fill", .pink, "Подсказки и примеры", "Значок «?» у сложных настроек, примеры сайтов в маршрутах и понятный таймер сессии."),
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
                // Remembered for the "Новое" marks in Settings: what the person had before this update.
                if !lastSeen.isEmpty, lastSeen != current { UserDefaults.standard.set(lastSeen, forKey: "previousVersion") }
                show = onboardingDone && !lastSeen.isEmpty && lastSeen != current
            }
            .sheet(isPresented: $show) { WhatsNewView() }
    }
}
