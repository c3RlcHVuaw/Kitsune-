import Charts
import Shared
import SwiftUI

/// Average ping of one server for every hour of the day, built from the live samples taken while connected.
struct PingHeatmapView: View {
    let server: ServerConfig
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let values = PingStats.averages(server.id)
        let known = values.compactMap { $0 }
        let best = values.enumerated().filter { $0.element != nil }.min { $0.element! < $1.element! }
        VStack(alignment: .leading, spacing: 14) {
            Text(server.displayName).font(.display(17, relativeTo: .headline))
            if known.isEmpty {
                Text("Пока нет данных. Пинг записывается, пока вы подключены.").foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(0..<24, id: \.self) { hour in
                        if let ms = values[hour] {
                            BarMark(x: .value("Час", hour), y: .value("мс", ms))
                                .foregroundStyle(hour == best?.offset ? Color.green : Color.orange.opacity(0.75))
                                .cornerRadius(3)
                        }
                    }
                }
                .chartXScale(domain: -0.5...23.5)
                .chartXAxis { AxisMarks(values: [0, 6, 12, 18, 23]) { AxisValueLabel() } }
                .frame(height: 160)
                if let best {
                    Label(String(format: L("Быстрее всего около %lld:00 — в среднем %lld мс"), best.offset, best.element!), systemImage: "clock")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Button("Готово") { dismiss() }.buttonStyle(.brand).frame(maxWidth: .infinity)
        }
        .padding(20)
        .frame(minWidth: 360, minHeight: 300)
        .presentationDetents([.medium])
    }
}
