import SwiftUI

/// Blocks under the connect button that the user can hide and reorder.
enum HomeBlock: String, CaseIterable, Identifiable {
    case status, info, speed, apps
    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .status: "Проверка и сводка"
        case .info: "IP и страна"
        case .speed: "График скорости"
        case .apps: "Кто потребляет"
        }
    }
    var icon: String {
        switch self {
        case .status: "checkmark.shield"
        case .info: "globe"
        case .speed: "waveform.path.ecg"
        case .apps: "square.grid.3x3"
        }
    }

    static let orderKey = "homeOrder", hiddenKey = "homeHidden"

    static func order(_ raw: String) -> [HomeBlock] {
        let saved = raw.split(separator: ",").compactMap { HomeBlock(rawValue: String($0)) }
        return saved + allCases.filter { !saved.contains($0) }
    }
    static func store(_ blocks: [HomeBlock]) -> String { blocks.map(\.rawValue).joined(separator: ",") }
}

extension HomeBlock {
    var subtitle: LocalizedStringKey {
        switch self {
        case .status: "Защита, сводка дня, звания"
        case .info: "Внешний IP и страна выхода"
        case .speed: "Живой график загрузки и отдачи"
        case .apps: "Три самых активных приложения"
        }
    }
}

/// Big rows: tap the eye to hide, drag a row onto another to reorder.
struct HomeLayoutEditor: View {
    @AppStorage(HomeBlock.orderKey) private var orderRaw = ""
    @AppStorage(HomeBlock.hiddenKey) private var hiddenRaw = ""
    @State private var targeted: HomeBlock?

    private func isOn(_ block: HomeBlock) -> Bool { !hiddenRaw.split(separator: ",").contains(Substring(block.rawValue)) }

    private func toggle(_ block: HomeBlock) {
        var hidden = Set(hiddenRaw.split(separator: ",").map(String.init))
        if isOn(block) { hidden.insert(block.rawValue) } else { hidden.remove(block.rawValue) }
        withAnimation(.smooth) { hiddenRaw = hidden.sorted().joined(separator: ",") }
    }

    private func move(_ id: String, before target: HomeBlock) {
        guard let moved = HomeBlock(rawValue: id), moved != target else { return }
        var list = HomeBlock.order(orderRaw)
        list.removeAll { $0 == moved }
        list.insert(moved, at: list.firstIndex(of: target) ?? list.endIndex)
        withAnimation(.smooth) { orderRaw = HomeBlock.store(list) }
    }

    var body: some View {
        VStack(spacing: 10) {
            ForEach(HomeBlock.order(orderRaw)) { block in
                let on = isOn(block)
                HStack(spacing: 14) {
                    Image(systemName: block.icon)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(on ? Color.brand : .secondary)
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.07), in: .rect(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(block.title).font(.headline)
                        Text(block.subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Button { toggle(block) } label: {
                        Image(systemName: on ? "eye" : "eye.slash")
                            .font(.title3)
                            .foregroundStyle(on ? .primary : .tertiary)
                            .frame(width: 36, height: 36)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .help(on ? "Скрыть" : "Показать")
                    Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary).font(.title3)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .frame(height: 68)
                .background(.white.opacity(targeted == block ? 0.14 : 0.05), in: .rect(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(targeted == block ? 0.35 : 0.08)))
                .opacity(on ? 1 : 0.6)
                .draggable(block.rawValue)
                .dropDestination(for: String.self) { items, _ in
                    if let id = items.first { move(id, before: block) }
                    return true
                } isTargeted: { targeted = $0 ? block : (targeted == block ? nil : targeted) }
            }
        }
        .padding(12)
    }
}
