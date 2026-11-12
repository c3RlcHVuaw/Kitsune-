# Kitsune design system (Figma)

File: https://www.figma.com/design/QeLz7bcvblAeYTYIFETlBN/Kitsune  
Access: only the owner's main Figma account has edit rights. If a Figma tool says “no edit access”,
check `whoami`: a second Figma connector may be signed in to a different account — use the one that can edit.

## Pages

| Page | Content |
|---|---|
| Cover | File cover 1920×1080 |
| Foundations | All colour tokens with values, type ramp, glass/effects, spacing and radius |
| Components | Four columns: Основа, Навигация, Главная, Списки и настройки. Every component has a description |
| Screens | Sections: Первый запуск, Главная, Разделы, Дополнительно, Шторки и окна. Each screen has a caption |

Screens are macOS windows **490 × 836**, corner radius 26, built as vertical auto layout:
`TitleBar` instance → `Content` (padding 16, Home uses 20). Scrolling pages put everything below `PageHeader`
into a `Scroll` frame with `paddingRight 18` and an absolute `Scroll thumb` at x 477 — cards are 440 wide, like the app.

## Tokens (variables)

- **Color** (mode Dark): `bg/base`, `text/{primary,secondary,tertiary}`, `border/{subtle,strong,faint}`,
  `glass/{tint,tint-strong}`, `brand/{orange,deep,alarm}`, `status/{connected,warning,alert}`,
  `theme/{copper,moon,neon}/{accent,soft,glow}`, `chip/copper-{bg,stroke}`, `toggle/{track,knob}`,
  `button/disc-copper`, `control/selected`, `chart/well`, `scroll/thumb`, `halo`, `titlebar/dot`, `surface/*`.
- **Spacing**: `space/xs…3xl` (4–32). **Radius**: `radius/sm…full` (12–999).
- Translucent colours are separate tokens with alpha. Do not put opacity on a variable-bound paint: Figma drops it.

Code ↔ token: `Color.brand` = `brand/orange`, `ButtonTheme.accent/soft/glow` = `theme/*/…`,
`KitsuneBackground` base = `bg/base`, `.white.opacity(0.07–0.1)` fills = `glass/tint`.

## Text and effect styles

- Display (Unbounded **Regular**): `Display/Hero` 96, `Display/Title` 26, `Display/Status` 20, `Display/Number` 20,
  `Display/Headline` 15, `Rounded/Metric` 20 — `Font.display(size)` in code.
- Interface (SF Pro): `Body/Large` 14 Semibold, `Body/Regular|Medium|Semibold` 13, `Callout` 12, `Footnote` 11,
  `Caption` 10, `Caption/Medium` 10.
- Effects: `Glass/Surface` (cards, lists — `.glassEffect(.regular)`), `Glass/Control` (buttons, capsules, tab bar),
  `Card/Shadow`.

## Components (name → node id → code)

| Component | Id | Code |
|---|---|---|
| Fox/Mark | 20:8 | `FoxMark` / `FoxHead` |
| Icon/* (SF Symbols look-alikes) | row next to 20:15 | `Image(systemName:)` |
| Flag/* | 20:215… | flag emoji |
| Toggle (On) | 20:128 | `Toggle` |
| TabBar (Tab) | 20:207 | toolbar segmented picker |
| TitleBar (exposes TabBar) | 25:47 | window chrome |
| ConnectButton (State: Idle, Connecting, Connected, Error) | 25:94 | `ConnectButton` |
| StatusCaption | 25:97 | `StatusCaption` |
| ConnectionInfo | 25:108 | `ConnectionInfo` |
| ProfileChip (On) | 25:133 | `ProfileChip` |
| SpeedColumn / SpeedCard | 26:90 / 26:91 | `SpeedRow` |
| AppRow / TopAppsCard | 26:152 / 26:153 | `TopApps` |
| SearchField | 26:165 | servers search |
| Chip | 26:172 | link and recent capsules |
| SegmentedControl (Selected) | 26:199 | routing profile picker |
| PageHeader | 26:202 | page titles |
| ListRow (Trailing: None, Toggle, Value, Picker, Chevron, Check) | 28:142 | `ListRow` inside `ListSection` |
| ServerRow (Selected) | 28:171 | server list row |
| ThemeDots (Selected) | 28:198 | button colour picker |
| TrafficCard | 28:201 | settings traffic card |
| BlockCard (Visible) | 28:291 | `HomeLayoutEditor` |
| BrandButton | 52:536 | `.buttonStyle(.brand)` |
| PageDots (Step) | 52:552 | onboarding dots |
| QRCode | 52:555 | `ShareQRView` (placeholder pattern) |

Ids are hints; find components by name if one moved.

## Windows (Fluent) — page “Windows”

Design-only for now (no Windows build). Windows 11 look with the Kitsune brand: Mica window, layered content,
Fluent controls, copper accent. Window **1000 × 680**, radius 8, `Win/TitleBar` (48) → body: navigation pane 280
(`Win/NavItem`, Settings pinned to the bottom) + content layer (`win/layer`, top-left radius 8, padding 40/32).

- Tokens: collection **Windows** (`win/mica`, `win/layer`, `win/card`, `win/control`, `win/text{,-2,-3}`,
  `win/accent` (copper), `win/on-accent`, `win/success`, `win/critical`, `win/acrylic`, …).
- Type: `Win/Caption 12`, `Win/Body 14`, `Win/Body Strong 14`, `Win/Subtitle 20`, `Win/Title 28`, `Win/Title Large 40`,
  `Win/Display 68`. Inter stands in for Segoe UI Variable (not in Figma). Brand numbers and the status title stay Unbounded.
- Effects: `Win/Elevation Window`, `Win/Elevation Flyout` (acrylic blur), `Win/Elevation Card`.
- Components: `Win/TitleBar`, `Win/NavItem` (State), `Win/Toggle` (On, with “Вкл./Откл.” label), `Win/Button`
  (Style: Accent/Standard), `Win/ComboBox`, `Win/SearchBox`, `Win/SelectorBar` (Selected), `Win/SettingsCard`
  (Trailing: None/Toggle/Combo/Chevron/Button; stack with 4 px gaps under a `Win/Body Strong` group title),
  `Win/ServerRow` (Selected), `Win/InfoBar` (Severity).
- Screens: Главная (подключено/отключено, two columns: hero card + 300 px right column), Серверы, Маршруты,
  Настройки, tray flyout (360, acrylic) instead of the macOS menu bar.

## Working with the file through the Figma API (agents)

- Load `figma-use` + `figma-generate-library`/`figma-generate-design` skills before `use_figma`.
- **SF Pro quirk:** in this file SF Pro is a variable font that the plugin API treats as “missing”. Editing a text
  property on an instance (`setProperties`) or creating SF Pro text fails. Workaround used everywhere: at the start of
  the script switch every SF Pro text style to Inter (`Semibold` → `Semi Bold`), do the work, and switch them back to
  SF Pro in a `finally`-style block. Unbounded and Inter load normally.
- Emoji cannot be inserted through the API (no emoji font). Leave them for manual edits.
- A failed `use_figma` call is rolled back as a whole; fix and rerun.
- New screen recipe: auto-layout window frame (see above) → `TitleBar` instance (`Tab` on its nested TabBar) →
  `PageHeader` → groups `Group / <title>` = label (`Footnote`, padding-left 16) + glass card (radius 24, `glass/tint`,
  `Glass/Surface`, clip) of `ListRow` instances (last one `Divider=false`) + optional note (`Caption`, `text/secondary`).
  Section gap 22, label→card 7.
- After building, screenshot the frame and compare with the running app (window 490×836, `screencapture -l <id>`).
