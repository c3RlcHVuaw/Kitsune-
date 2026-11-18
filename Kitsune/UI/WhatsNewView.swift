import SwiftUI

/// Shown once after an update (never on the very first launch) and from Settings.
struct WhatsNewView: View {
    @Environment(\.kitsuneTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    private let items: [(icon: String, color: Color, title: String, text: String)] = [
        ("point.topleft.down.curvedto.point.bottomright.up.fill", .orange, "Маршруты по-новому", "Крупные карточки профилей, сводка правил и цветные иконки у каждого пункта."),
        ("capsule.fill", .blue, "Сайты чипами", "Сайты в списках теперь плашки с крестиком, а не длинный столбец строк."),
        ("square.and.arrow.down.fill", .green, "Перетаскивание", "Бросьте приложение из Finder или ссылку на сайт на нужную секцию, и правило добавится."),
        ("questionmark.circle.fill", .purple, "Спокойный экран", "Длинные пояснения спрятаны за значок «?» рядом с заголовком секции."),
        ("pawprint.fill", .pink, "Лиса в пустых списках", "Пустые списки приложений и сайтов подсказывают, что делать, и на главной видно активный профиль."),
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
