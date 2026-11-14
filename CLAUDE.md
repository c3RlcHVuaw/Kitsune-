# Kitsune — notes for agents

Native macOS VPN client (SwiftUI, Liquid Glass) on the sing-box core: VLESS+Reality, Hysteria2 and friends,
with “Russia direct” routing. The iOS target exists but is not maintained; work on macOS unless asked.
The owner writes in Russian: answer in Russian, keep UI copy in Russian (English goes to `en.lproj`).

## Layout

| Path | What lives there |
|---|---|
| `Kitsune/` | macOS app. `VPNManager` (tunnel, Clash API, speeds, top apps), `Library` (servers, subscriptions, routing, pings), `History`, `AppTraffic`, `PingStats`, `LANSharing`, `ShareCard` (+ menu bar fox), `NotificationRouter`, `Updater` |
| `Kitsune/UI/` | Screens: `HomeView`, `ServersView`, `RoutingView`, `SettingsView`, `HistoryView`, `OnboardingView`, `DiagnosticsView`, `PingHeatmapView`, `WhatsNewView`, `HomeLayout` (home block editor). Shared look in `Theme.swift` |
| `Shared/` | Swift package with no UI: `ConfigBuilder` (sing-box JSON), `RoutingSettings`, `ServerConfig`, `Subscription`, link parsers, `ErrorHint`. Unit tests live here |
| `PacketTunnel/` | iOS/NE extension and bundled rule sets (`RuleSets/*.srs`, refreshed by `scripts/update-rule-snapshot.sh`) |
| `windows/` | Native Windows app (WinUI 3, C#): `Kitsune.Core` (port of `Shared`: link parsers, `ConfigBuilder`, routing; xunit tests in `Kitsune.Core.Tests`, run on any OS with `dotnet test`), `Kitsune.App` (UI per the Figma Windows page, `Tunnel` runs `core\sing-box.exe` as admin). Built only by CI (`.github/workflows/windows.yml` → artifact `Kitsune-win-x64`); not runnable on macOS |
| `scripts/` | `build-mac.sh` (release build + dmg/zip), `build-libbox.sh`, icon and dmg helpers |
| `project.yml` | XcodeGen spec. Version = `MARKETING_VERSION`. The `.xcodeproj` is generated, never edit it |

On macOS the app does not use a Network Extension: it runs the bundled `sing-box` binary as root
(one admin-password prompt via osascript, then sudo for `/Library/Kitsune/sing-box`). Control API: `127.0.0.1:19090`
(`/traffic`, `/connections`, `PUT /proxies/proxy` for a live server switch through `vpn.reload`).

## Build, test, run

```sh
cd Shared && swift test                 # unit tests (Swift Testing), must stay green
scripts/build-mac.sh                    # Release build → dist/Kitsune-mac.dmg + .zip
```
App bundle: `.build/dd-mac-release/Build/Products/Release/Kitsune.app`.
Check a generated sing-box config: `<app>/Contents/Resources/sing-box check -c file.json` (Reality needs a valid 43-char base64 `pbk`).

Install the fresh build (restarts the app, the VPN drops for a second, auto-connect brings it back):
```sh
pkill -x Kitsune; ditto .build/dd-mac-release/Build/Products/Release/Kitsune.app /Applications/Kitsune.app && open /Applications/Kitsune.app
```

## Hard rules

- Swift 6, strict concurrency, **warnings are errors**. Deprecated APIs fail the build.
- Every new user-visible string: Russian literal in code + English line in `Kitsune/en.lproj/Localizable.strings`.
  No duplicate keys: `plutil -lint Kitsune/en.lproj/Localizable.strings` and
  `grep -oE '^"([^"\\]|\\.)*" =' Kitsune/en.lproj/Localizable.strings | sort | uniq -d` must print nothing.
- `ConfigBuilder` changes keep defaults backward compatible (golden test in `Shared/Tests/SharedTests/Golden`), and new
  `RoutingSettings` fields decode with defaults so old saved settings still load.
- Keep `windows/Kitsune.Core` in step with `Shared` when link parsing, `ConfigBuilder` or `RoutingSettings` change.
- Never toggle the user's VPN while testing (no clicks on the connect button). Ask before installing or restarting the app.
- Commit, push and release only when the owner asks. When asked for ideas, only propose; implement after they pick numbers,
  and never repeat ideas already offered.
- Screenshots for README/docs must hide personal data (IP, subscription name/ID, server list of the owner).

## Release (“залей на гит и выпусти релиз X”)

1. Bump `MARKETING_VERSION` in `project.yml`.
2. Update `WhatsNewView.items` (5 short items) and their English strings.
3. `cd Shared && swift test`, then `scripts/build-mac.sh`.
4. Commit, `git push origin main`, then
   `gh release create vX dist/Kitsune-mac.dmg dist/Kitsune-mac.zip --title "Kitsune X" --notes "…"` (notes in Russian).

## UI conventions

- Look: near-black background (`KitsuneBackground`), one copper accent (theme: copper/moon/neon), glass surfaces
  (`.glassEffect`, `ListSection`/`ListRow` for grouped lists), Unbounded for titles and numbers (`Font.display`), system font for the rest.
- Restrained and native: no gradients-for-decoration, no emoji in UI chrome, no layout jumps (fixed slots, `.contentTransition`).
- Settings use `@AppStorage`; keys are listed in `SettingsView.prefKeys` for export/import — add new ones there.
- Design source of truth is Figma, see `docs/DESIGN.md`. New screens: build them from the existing components there first.
