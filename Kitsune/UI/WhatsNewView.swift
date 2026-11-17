import SwiftUI

/// Shown once after an update (never on the very first launch) and from Settings.
struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss

    private let items: [(icon: String, color: Color, title: String, text: String)] = [
        ("point.3.connected.trianglepath.dotted", .orange, "Цепочка на главной", "С двойным прыжком под статусом видно оба сервера: вход → выход."),
        ("pawprint.fill", .blue, "Звание в настройках", "В паспорте видно ваше звание и сколько осталось до следующего."),
        ("moon.zzz.fill", .purple, "Прятать неотвечающие", "Серверы, которые не отвечают, уходят в свёрнутую группу внизу списка."),
        ("sparkle", .green, "Метки «Новое»", "Плитки настроек подсказывают, где после обновления появилось новое."),
        ("speedometer", .pink, "Скорость в одну строку", "Загрузка, отдача и график за минуту в компактной карточке."),
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
