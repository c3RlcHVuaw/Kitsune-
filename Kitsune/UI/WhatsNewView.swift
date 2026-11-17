import SwiftUI

/// Shown once after an update (never on the very first launch) and from Settings.
struct WhatsNewView: View {
    @Environment(\.kitsuneTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    private let items: [(icon: String, color: Color, title: String, text: String)] = [
        ("paintpalette.fill", .pink, "Тема красит всё", "Выбранный цвет теперь везде: переключатели, списки, графики, плашки, а не только кнопка подключения."),
        ("map.fill", .blue, "Карта серверов", "На «Серверах» кнопка «Карта»: метки стран по цвету лучшего пинга, тап приближает и показывает серверы страны."),
        ("hand.draw.fill", .orange, "Свайп по строке", "Вправо закрепить сервер, влево удалить (свои серверы, с подтверждением)."),
        ("sun.haze.fill", .purple, "Фон оживает", "В покое холодное свечение, при подключении оно плавно теплеет до цвета темы."),
        ("speaker.wave.2.fill", .green, "Тихие звуки и пустые экраны", "Тик при выборе сервера, нота при ошибке, живая лиса на пустых экранах и в пустом поиске."),
    ]

    var body: some View {
        VStack(spacing: 18) {
            FoxMark(color: theme.accent).frame(width: 52)
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
