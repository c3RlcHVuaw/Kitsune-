#if os(macOS)
import AppKit
import Foundation

/// Checks the latest GitHub release once a day. The app is unsigned, so it only opens the download.
@MainActor @Observable final class Updater {
    static let shared = Updater()
    enum State: Equatable { case idle, checking, upToDate, available(version: String, url: URL), failed }

    private(set) var state = State.idle
    static let feed: URL? = URL(string: "https://api.github.com/repos/c3RlcHVuaw/Kitsune-/releases/latest")

    func checkIfDue() async {
        guard UserDefaults.standard.object(forKey: "autoUpdateCheck") as? Bool ?? true else { return }
        let last = UserDefaults.standard.double(forKey: "updateChecked")
        if Date.now.timeIntervalSince1970 - last > 86_400 { await check() }
    }

    func check() async {
        guard let feed = Self.feed else { return }
        state = .checking
        struct Asset: Decodable { let name: String; let browser_download_url: URL }
        struct Feed: Decodable { let tag_name: String; let html_url: URL; let assets: [Asset] }
        do {
            let (data, _) = try await URLSession.shared.data(from: feed)
            let latest = try JSONDecoder().decode(Feed.self, from: data)
            let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
            UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: "updateChecked")
            let version = latest.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            let url = latest.assets.first { $0.name.hasSuffix(".dmg") }?.browser_download_url ?? latest.html_url
            state = version.compare(current, options: .numeric) == .orderedDescending ? .available(version: version, url: url) : .upToDate
        } catch {
            state = .failed
        }
    }
}
#endif
