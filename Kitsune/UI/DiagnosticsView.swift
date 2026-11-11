#if os(macOS)
import SwiftUI

/// Live core log, to see why a connection fails and to copy it for support.
struct DiagnosticsView: View {
    let vpn: VPNManager
    let server: String?

    @Environment(\.dismiss) private var dismiss
    @State private var log = ""
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Диагностика").font(.display(20, relativeTo: .title2))
                Spacer()
                Button("Готово") { dismiss() }.buttonStyle(.brand)
            }
            Label(vpn.status.title + (server.map { " · \($0)" } ?? ""), systemImage: "waveform.path.ecg")
                .font(.subheadline)
            if let error = vpn.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote).foregroundStyle(Color.alert).textSelection(.enabled)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    Text(log.isEmpty ? L("Журнал пуст. Он появится после подключения.") : log)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    Color.clear.frame(height: 1).id("end")
                }
                .background(.black.opacity(0.25), in: .rect(cornerRadius: 14))
                .onChange(of: log) { proxy.scrollTo("end") }
            }
            Button(copied ? L("Скопировано") : L("Копировать журнал"), systemImage: copied ? "checkmark" : "doc.on.doc") {
                Clipboard.copy(log)
                copied = true
                Task { try? await Task.sleep(for: .seconds(2)); copied = false }
            }
            .disabled(log.isEmpty)
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(minWidth: 460, minHeight: 520)
        .background(Color(red: 0.06, green: 0.02, blue: 0.015))
        .task {
            while !Task.isCancelled {
                log = vpn.coreLogTail()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}
#endif
