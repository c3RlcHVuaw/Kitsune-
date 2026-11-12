#if os(macOS)
import AppKit
import SwiftUI

/// A shareable picture of your numbers: no addresses, servers or sites, only totals.
@MainActor enum ShareCard {
    static func copy() {
        let renderer = ImageRenderer(content: ShareCardView())
        renderer.scale = 2
        guard let image = renderer.nsImage else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }
}

private struct ShareCardView: View {
    var body: some View {
        let rank = History.rank
        let countries = Set(History.sessions.compactMap(\.country)).count
        VStack(spacing: 28) {
            HStack(spacing: 12) {
                FoxMark(color: .brand).frame(width: 44, height: 44)
                Text("kitsune").font(.display(26, relativeTo: .title))
                Spacer()
            }
            Spacer(minLength: 0)
            VStack(spacing: 6) {
                Text("\(History.totalHours)").font(.display(120, relativeTo: .largeTitle)).foregroundStyle(Color.brand)
                Text("часов под защитой").font(.title3).foregroundStyle(.white.opacity(0.7))
            }
            HStack(spacing: 40) {
                stat("\(History.streak)", "дней подряд")
                stat("\(countries)", "стран")
            }
            Text(rank.title).font(.display(30, relativeTo: .title)).padding(.horizontal, 26).padding(.vertical, 10)
                .background(.white.opacity(0.1), in: .capsule)
            HStack(spacing: 10) {
                ForEach(History.badges, id: \.title) { badge in
                    Image(systemName: badge.icon).font(.title2).foregroundStyle(Color.brand)
                        .frame(width: 46, height: 46).background(.white.opacity(0.08), in: .circle)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(36)
        .frame(width: 480, height: 600)
        .background(LinearGradient(colors: [Color(red: 0.17, green: 0.09, blue: 0.06), Color(red: 0.05, green: 0.05, blue: 0.06)], startPoint: .top, endPoint: .bottom))
        .environment(\.colorScheme, .dark)
    }

    private func stat(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 34, weight: .semibold, design: .rounded))
            Text(label).font(.footnote).foregroundStyle(.white.opacity(0.6))
        }
    }
}

/// Menu bar fox: ears droop when off, wag while traffic flows, twitch now and then.
@MainActor @Observable final class MenuFox {
    static let shared = MenuFox()
    private(set) var sway: CGFloat = 0
    private(set) var twitch: CGFloat = 0
    @ObservationIgnored private weak var vpn: VPNManager?
    @ObservationIgnored private var started = false
    private var step = 0

    /// Called from the menu bar label (idempotent): remembers the manager and starts the heartbeat once.
    func bind(_ vpn: VPNManager) {
        self.vpn = vpn
        guard !started else { return }
        started = true
        Task { [self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(400))
                step += 1
                let wag: CGFloat = (self.vpn?.status == .connected && self.vpn?.topApps.isEmpty == false) ? (step.isMultiple(of: 2) ? 0.6 : -0.6) : 0
                let flick: CGFloat = step % 17 < 2 ? 1 : 0
                if wag != sway { sway = wag }
                if flick != twitch { twitch = flick }
            }
        }
    }

    func icon(connected: Bool, theme: ButtonTheme) -> NSImage {
        let fox = FoxMark(color: connected ? theme.accent : .black, droop: connected ? 0 : 0.7, sway: sway, twitch: twitch).frame(width: 18, height: 18)
        let renderer = ImageRenderer(content: fox)
        renderer.scale = 3
        let image = renderer.nsImage ?? NSImage()
        image.isTemplate = !connected
        return image
    }
}
#endif
