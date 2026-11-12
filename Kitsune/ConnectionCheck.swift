import Foundation

/// After connecting: did the address change, and does DNS go through the tunnel? The "before" look is taken while connecting.
@MainActor @Observable final class ConnectionCheck {
    enum State: Equatable { case idle, running, ok(String), warn(String) }
    private(set) var state = State.idle
    private var before: LeakCheck.Result?
    private var beforeTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?

    /// Called when the tunnel starts coming up, while traffic still leaves directly.
    func prepare() {
        reset()
        beforeTask = Task { before = await LeakCheck.probe() }
    }

    func verify() async {
        await beforeTask?.value
        hideTask?.cancel()
        state = .running
        try? await Task.sleep(for: .seconds(3)) // routes need a moment to settle
        // Right after connecting the routes are still switching, so one failed look is not a verdict.
        var seen: LeakCheck.Result?
        for attempt in 0..<3 where seen == nil && !Task.isCancelled {
            if attempt > 0 { try? await Task.sleep(for: .seconds(2)) }
            seen = await LeakCheck.probe()
        }
        guard !Task.isCancelled else { return }
        guard let after = seen else { finish(.warn(L("Не удалось проверить соединение."))); return }
        if let before, before.ip == after.ip {
            finish(.warn(L("Адрес не изменился: трафик идёт мимо VPN.")))
            return
        }
        let dnsClean = after.dns != nil && after.dns != before?.dns
        finish(.ok(dnsClean ? L("Всё работает: IP сменился, DNS чистый") : L("Всё работает: IP сменился")))
    }

    func reset() {
        beforeTask?.cancel(); hideTask?.cancel()
        before = nil
        state = .idle
    }

    private func finish(_ result: State) {
        state = result
        hideTask = Task {
            try? await Task.sleep(for: .seconds(result == .idle ? 0 : 9))
            if !Task.isCancelled { state = .idle }
        }
    }
}
