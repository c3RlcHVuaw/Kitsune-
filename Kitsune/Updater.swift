#if os(macOS)
import AppKit
import Foundation

/// Checks the latest GitHub release every few hours and can replace the installed app with it (the app is unsigned,
/// so it downloads the zip itself and swaps the bundle after quitting).
@MainActor @Observable final class Updater {
    static let shared = Updater()
    enum State: Equatable { case idle, checking, upToDate, available(version: String, url: URL), installing, failed }

    private(set) var state = State.idle
    static let feed: URL? = URL(string: "https://api.github.com/repos/c3RlcHVuaw/Kitsune-/releases/latest")

    /// Direct link to the zip of the newest release, filled in by `check()`.
    private var zipURL: URL?
    private var started = false

    /// Checks now if the last check is older than 6 hours, then keeps checking while the app runs.
    func start() {
        guard !started else { return }
        started = true
        Task {
            while !Task.isCancelled {
                await checkIfDue()
                try? await Task.sleep(for: .seconds(3600))
            }
        }
    }

    func checkIfDue() async {
        guard UserDefaults.standard.object(forKey: "autoUpdateCheck") as? Bool ?? true else { return }
        let last = UserDefaults.standard.double(forKey: "updateChecked")
        if Date.now.timeIntervalSince1970 - last > 21_600 { await check() }
    }

    /// Downloads the new build, quits, swaps the bundle and reopens the app.
    func install() async {
        guard case .available(_, let page) = state else { return }
        let destination = Bundle.main.bundleURL
        guard let zipURL, FileManager.default.isWritableFile(atPath: destination.deletingLastPathComponent().path) else {
            NSWorkspace.shared.open(page) // can't replace in place (read-only location): fall back to the download page
            return
        }
        state = .installing
        do {
            let (file, _) = try await URLSession.shared.download(from: zipURL)
            let work = FileManager.default.temporaryDirectory.appendingPathComponent("kitsune-update-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            let zip = work.appendingPathComponent("update.zip")
            try FileManager.default.moveItem(at: file, to: zip)
            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            unzip.arguments = ["-x", "-k", zip.path, work.path]
            try unzip.run(); unzip.waitUntilExit()
            let fresh = work.appendingPathComponent("Kitsune.app")
            guard unzip.terminationStatus == 0, FileManager.default.fileExists(atPath: fresh.appendingPathComponent("Contents/MacOS/Kitsune").path) else { throw CocoaError(.fileReadCorruptFile) }
            // A detached shell waits for this process to exit, then swaps the bundle and relaunches.
            let script = "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.3; done; rm -rf '\(destination.path)' && /usr/bin/ditto '\(fresh.path)' '\(destination.path)' && /usr/bin/xattr -cr '\(destination.path)'; /usr/bin/open '\(destination.path)'; rm -rf '\(work.path)'"
            let relauncher = Process()
            relauncher.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
            relauncher.arguments = ["/bin/sh", "-c", script]
            relauncher.standardOutput = FileHandle.nullDevice
            relauncher.standardError = FileHandle.nullDevice
            try relauncher.run()
            NSApp.terminate(nil)
        } catch {
            state = .failed
        }
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
            zipURL = latest.assets.first { $0.name == "Kitsune-mac.zip" }?.browser_download_url
            state = version.compare(current, options: .numeric) == .orderedDescending ? .available(version: version, url: url) : .upToDate
        } catch {
            state = .failed
        }
    }
}
#endif
