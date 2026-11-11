#if os(macOS)
import AppKit
import Foundation

/// Checks a JSON feed ({"version": "1.2", "url": "https://…/Kitsune-mac.dmg", "notes": "…"}) once a day.
/// The feed address comes from the KitsuneUpdateFeed key in Info.plist. The app is unsigned, so it only opens the download.
@MainActor @Observable final class Updater {
    static let shared = Updater()
    enum State: Equatable { case idle, checking, upToDate, available(version: String, url: URL), failed }

    private(set) var state = State.idle
    static var feed: URL? { (Bundle.main.object(forInfoDictionaryKey: "KitsuneUpdateFeed") as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) } }

    func checkIfDue() async {
        guard UserDefaults.standard.object(forKey: "autoUpdateCheck") as? Bool ?? true else { return }
        let last = UserDefaults.standard.double(forKey: "updateChecked")
        if Date.now.timeIntervalSince1970 - last > 86_400 { await check() }
    }

    func check() async {
        guard let feed = Self.feed else { return }
        state = .checking
        struct Feed: Decodable { let version: String; let url: URL }
        do {
            let (data, _) = try await URLSession.shared.data(from: feed)
            let latest = try JSONDecoder().decode(Feed.self, from: data)
            let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
            UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: "updateChecked")
            state = latest.version.compare(current, options: .numeric) == .orderedDescending ? .available(version: latest.version, url: latest.url) : .upToDate
        } catch {
            state = .failed
        }
    }
}
#endif
