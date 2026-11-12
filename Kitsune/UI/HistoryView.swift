import Charts
import SwiftUI

/// Past connections: a period switch, a bar chart of time per day and the session list.
struct HistoryView: View {
    enum Period: String, CaseIterable { case day, week, all
        var title: LocalizedStringKey { switch self { case .day: "Сегодня"; case .week: "Неделя"; case .all: "Всё время" } }
        var days: Int? { switch self { case .day: 1; case .week: 7; case .all: nil } }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var period = Period.week
    @State private var sessions = History.sessions
    private let accent = Color(red: 1.0, green: 0.50, blue: 0.10)

    private var shown: [History.Session] {
        guard let days = period.days, let from = Calendar.current.date(byAdding: .day, value: -(days - 1), to: Calendar.current.startOfDay(for: .now)) else { return sessions }
        return sessions.filter { $0.end >= from }
    }

    private var perDay: [(date: Date, hours: Double)] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: shown) { cal.startOfDay(for: $0.start) }
        let count = period.days ?? 7
        return (0..<count).reversed().compactMap { offset in
            guard let day = cal.date(byAdding: .day, value: -offset, to: cal.startOfDay(for: .now)) else { return nil }
            return (day, (grouped[day] ?? []).reduce(0) { $0 + $1.duration } / 3600)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("История подключений").font(.display(20))
                Spacer()
                Button("Готово") { dismiss() }.buttonStyle(.brand)
            }
            .padding(20)
            ScrollView {
                VStack(spacing: 18) {
                    summaryCard
                    ListSection(title: "Период") {
                        ForEach(Period.allCases, id: \.self) { item in
                            Button { withAnimation(.smooth) { period = item } } label: {
                                ListRow { Text(item.title); Spacer(); if period == item { Image(systemName: "checkmark").foregroundStyle(accent) } }
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if shown.isEmpty {
                        Text("Пока нет подключений за этот период.").font(.footnote).foregroundStyle(.secondary).padding(.top, 8)
                    } else {
                        ListSection(title: "Подключения") {
                            ForEach(shown.reversed().prefix(60)) { session in
                                ListRow {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(session.server).lineLimit(1)
                                        Text(session.start.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(duration(session.duration)).monospacedDigit()
                                        Text("↓ \(bytes(session.down)) ↑ \(bytes(session.up))").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                                    }
                                }
                            }
                        }
                    }
                    if !sessions.isEmpty {
                        Button("Очистить историю", role: .destructive) { History.clear(); sessions = [] }
                            .buttonStyle(.plain).foregroundStyle(.secondary).font(.footnote)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .frame(minWidth: 420, minHeight: 560)
        .background(Color(red: 0.028, green: 0.026, blue: 0.030))
        .preferredColorScheme(.dark)
    }

    private var summaryCard: some View {
        let total = shown.reduce(0) { $0 + $1.duration }
        let down = shown.reduce(Int64(0)) { $0 + $1.down }, up = shown.reduce(Int64(0)) { $0 + $1.up }
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Время под защитой").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Text(duration(total)).font(.system(.title3, design: .rounded).weight(.medium)).monospacedDigit()
                }
                Chart(perDay, id: \.date) { item in
                    BarMark(x: .value("День", item.date, unit: .day), y: .value("Часы", item.hours), width: .ratio(0.55))
                        .foregroundStyle(accent)
                        .cornerRadius(3)
                }
                .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.abbreviated)).foregroundStyle(.secondary) } }
                .chartYAxis(.hidden)
                .frame(height: 90)
            }
            .padding(14)
            .background(.black.opacity(0.28), in: .rect(cornerRadius: 18))
            HStack {
                stat("Подключений", "\(shown.count)")
                Spacer()
                stat("Загрузка", bytes(down))
                Spacer()
                stat("Отдача", bytes(up))
            }
            .padding(.horizontal, 4)
            let rank = History.rank
            HStack(spacing: 10) {
                Image(systemName: "sparkles").foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(rank.title).font(.subheadline.weight(.medium))
                    Text(rank.hint).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    private func stat(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(.body, design: .rounded).weight(.medium)).monospacedDigit()
        }
    }

    private func bytes(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .binary) }

    private func duration(_ t: TimeInterval) -> String {
        let s = Int(t), h = s / 3600, m = s % 3600 / 60
        return h > 0 ? String(format: L("%lld ч %lld мин"), h, m) : String(format: L("%lld мин"), max(m, s > 0 ? 1 : 0))
    }
}
