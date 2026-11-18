import CoreText
import SwiftUI

/// Unbounded (OFL): a wide display face for titles, buttons and numbers; body text stays system.
extension Font {
    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        .custom("Unbounded", size: size, relativeTo: style).weight(.regular)
    }
}

/// Runtime lookup for strings that aren't SwiftUI literals (computed titles, errors).
func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

enum BrandFont {
    static func register() {
        guard let url = Bundle.main.url(forResource: "Unbounded", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

/// Kitsune "bright brand" palette: fox orange background, white as the accent, orange only on white surfaces.
extension Color {
    /// The fox orange used for the whole background.
    static let brand = Color(red: 0.91, green: 0.39, blue: 0.16)
    /// Connected: a deeper, calmer orange.
    static let brandDeep = Color(red: 0.74, green: 0.27, blue: 0.09)
    /// Error: orange pushed towards red.
    static let brandAlarm = Color(red: 0.72, green: 0.18, blue: 0.14)
    /// Accent on the orange background.
    static let kitsuneAccent = Color.white
    /// Warnings on orange: red disappears there, pale yellow stays readable.
    static let alert = Color(red: 1.0, green: 0.92, blue: 0.55)
}

private struct ThemeKey: EnvironmentKey { static let defaultValue = ButtonTheme.copper }

extension EnvironmentValues {
    /// The chosen colour theme: set once at the root so every screen takes its accent from it.
    var kitsuneTheme: ButtonTheme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

/// Solid white capsule with orange text: the one primary action per screen.
struct BrandButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .kGlass(in: .capsule, interactive: true)
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == BrandButtonStyle {
    static var brand: BrandButtonStyle { BrandButtonStyle() }
}

extension View {
    /// Flat translucent white for elements inside a glass card (glass inside glass renders muddy).
    func brandFill(in shape: some Shape) -> some View {
        background(.white.opacity(0.1), in: shape)
    }

    /// Card surface on the orange background: a flat translucent fill with a light edge. Much cheaper to render
    /// than a glass effect per card, which made tab switches and scrolling stutter.
    func brandCard(in shape: some Shape) -> some View {
        background(LinearGradient(colors: [.white.opacity(0.075), .white.opacity(0.03)], startPoint: .top, endPoint: .bottom), in: shape)
            .overlay(shape.stroke(LinearGradient(colors: [.white.opacity(0.20), .white.opacity(0.04), Color.brand.opacity(0.10)], startPoint: .top, endPoint: .bottom), lineWidth: 0.6))
            .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
    }

    /// Glass only for the few small interactive controls.
    func brandGlass(in shape: some Shape, interactive: Bool = false) -> some View {
        // The clear variant keeps the orange showing through; .regular turns muddy brown on it.
        kGlass(in: shape, interactive: interactive, clear: true, tint: .white.opacity(0.2))
    }
}

/// Cards rise and fade in one after another when a screen opens (or scrolls into view).
private struct Appear: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 16)
            .onAppear {
                withAnimation(.smooth(duration: 0.5).delay(Double(min(index, 6)) * 0.07)) { shown = true }
            }
    }
}

extension View {
    func appear(_ index: Int) -> some View { modifier(Appear(index: index)) }
}

/// Native-style grouped list: a small caption above, rows inside ONE glass surface separated by hairlines, a footnote below.
/// Replaces stacks of separate cards, which read as generic.
struct ListSection<Content: View>: View {
    @Environment(\.kitsuneTheme) private var theme
    var title: LocalizedStringKey?
    /// Optional symbol before the title, in the theme colour.
    var symbol: String?
    var footer: LocalizedStringKey?
    /// Put the footer behind a "?" next to the title instead of under the list.
    var footerAsHelp = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                HStack(spacing: 6) {
                    if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .bold)).foregroundStyle(theme.accent) }
                    Text(title).font(.footnote.weight(symbol == nil ? .regular : .semibold)).foregroundStyle(.secondary)
                    if footerAsHelp, let footer { HelpButton(text: footer).font(.footnote) }
                }
                .padding(.leading, 16)
            }
            VStack(spacing: 0) {
                Group(subviews: content) { rows in
                    ForEach(rows.indices, id: \.self) { index in
                        rows[index]
                        if index < rows.count - 1 { Divider().opacity(0.5).padding(.leading, 16) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .kGlass(in: .rect(cornerRadius: 20))
            if let footer, !(footerAsHelp && title != nil) { Text(footer).font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 16) }
        }
    }
}

/// One row of a `ListSection`: consistent padding and minimum height.
struct ListRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 12) { content }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }
}

/// Colour of the connect button, its ring, the home glow and the speed chart.
/// The last four are rewards: each opens at a rank (see `History.rankLevel`) and stays open for good.
enum ButtonTheme: Hashable, RawRepresentable {
    case copper, moon, neon, aurora, sunset, foxfire, gold
    /// Own colour for the top rank: packed 0xRRGGBB, kept in the same preference as "custom:RRGGBB".
    case custom(UInt32)

    static let presets: [ButtonTheme] = [.copper, .moon, .neon, .aurora, .sunset, .foxfire, .gold]
    private static let names: [String: ButtonTheme] = ["copper": .copper, "moon": .moon, "neon": .neon, "aurora": .aurora, "sunset": .sunset, "foxfire": .foxfire, "gold": .gold]

    init?(rawValue: String) {
        if let known = Self.names[rawValue] { self = known }
        else if rawValue.hasPrefix("custom:"), let rgb = UInt32(rawValue.dropFirst(7), radix: 16) { self = .custom(rgb) }
        else { return nil }
    }

    var rawValue: String {
        switch self {
        case .copper: "copper"
        case .moon: "moon"
        case .neon: "neon"
        case .aurora: "aurora"
        case .sunset: "sunset"
        case .foxfire: "foxfire"
        case .gold: "gold"
        case .custom(let rgb): "custom:" + String(format: "%06X", rgb)
        }
    }

    /// Animated themes: the ring and the disc slowly swirl through these colours.
    var gradient: [Color]? {
        switch self {
        // Two neighbouring tones each: light and deep. Distant hues next to each other looked like a muddy rainbow.
        case .aurora: [Color(red: 0.45, green: 0.98, blue: 0.80), Color(red: 0.18, green: 0.62, blue: 0.82)]
        case .sunset: [Color(red: 1.0, green: 0.70, blue: 0.42), Color(red: 0.95, green: 0.36, blue: 0.48)]
        case .foxfire: [Color(red: 0.62, green: 0.90, blue: 1.0), Color(red: 0.28, green: 0.42, blue: 1.0)]
        case .gold: [Color(red: 1.0, green: 0.92, blue: 0.62), Color(red: 0.92, green: 0.62, blue: 0.16)]
        default: nil
        }
    }

    /// Rank needed to use the theme: 0 is open to everyone.
    var unlockLevel: Int {
        switch self { case .aurora: 1; case .sunset: 2; case .foxfire: 3; case .gold, .custom: 4; default: 0 }
    }

    @MainActor var isUnlocked: Bool { History.bestRankLevel >= unlockLevel }

    /// What the swatch shows: a gradient for the reward themes, the plain colour otherwise.
    var swatch: AnyShapeStyle {
        if let gradient { AnyShapeStyle(LinearGradient(colors: gradient, startPoint: .top, endPoint: .bottom)) } else { AnyShapeStyle(accent) }
    }

    var accent: Color {
        switch self {
        case .copper: Color(red: 1.0, green: 0.50, blue: 0.10)
        case .moon: Color(red: 0.55, green: 0.70, blue: 1.0)
        case .neon: Color(red: 0.12, green: 0.95, blue: 0.62)
        case .aurora: Color(red: 0.25, green: 0.88, blue: 0.75)
        case .sunset: Color(red: 1.0, green: 0.45, blue: 0.40)
        case .foxfire: Color(red: 0.40, green: 0.72, blue: 1.0)
        case .gold: Color(red: 1.0, green: 0.78, blue: 0.28)
        case .custom(let rgb): Color(red: Double(rgb >> 16 & 0xFF) / 255, green: Double(rgb >> 8 & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255)
        }
    }

    /// The idle fox and soft highlights.
    var soft: Color {
        switch self {
        case .copper: Color(red: 0.96, green: 0.80, blue: 0.62)
        case .moon: Color(red: 0.84, green: 0.90, blue: 1.0)
        case .neon: Color(red: 0.74, green: 1.0, blue: 0.90)
        case .aurora: Color(red: 0.78, green: 1.0, blue: 0.92)
        case .sunset: Color(red: 1.0, green: 0.84, blue: 0.80)
        case .foxfire: Color(red: 0.84, green: 0.93, blue: 1.0)
        case .gold: Color(red: 1.0, green: 0.95, blue: 0.78)
        case .custom: accent.mix(with: .white, by: 0.55)
        }
    }

    /// Slightly deeper tone for the background glow.
    var glow: Color {
        switch self {
        case .copper: Color(red: 0.85, green: 0.42, blue: 0.18)
        case .moon: Color(red: 0.40, green: 0.52, blue: 0.92)
        case .neon: Color(red: 0.08, green: 0.75, blue: 0.50)
        case .aurora: Color(red: 0.20, green: 0.60, blue: 0.70)
        case .sunset: Color(red: 0.85, green: 0.30, blue: 0.40)
        case .foxfire: Color(red: 0.25, green: 0.40, blue: 0.95)
        case .gold: Color(red: 0.85, green: 0.62, blue: 0.20)
        case .custom: accent.mix(with: .black, by: 0.2)
        }
    }

    /// System sounds for connecting and for a user-driven disconnect: each theme sounds a little different.
    var sounds: (connect: String, disconnect: String) {
        switch self {
        case .copper: ("Glass", "Pop")
        case .moon: ("Ping", "Tink")
        case .neon: ("Hero", "Bottle")
        case .aurora: ("Purr", "Tink")
        case .sunset: ("Glass", "Bottle")
        case .foxfire: ("Submarine", "Pop")
        case .gold, .custom: ("Hero", "Glass")
        }
    }

    var name: String {
        switch self {
        case .copper: L("Медь")
        case .moon: L("Луна")
        case .neon: L("Неон")
        case .aurora: L("Северное сияние")
        case .sunset: L("Закат")
        case .foxfire: L("Кицунэби")
        case .gold: L("Золото ёкая")
        case .custom: L("Свой цвет")
        }
    }

    var title: LocalizedStringKey { LocalizedStringKey(name) }
}

/// A short burst of sparks from the middle of the connect button.
struct SparkBurst: View {
    let start: Date?
    let colors: [Color]
    private let duration = 2.2

    var body: some View {
        if let start {
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSince(start)
                Canvas { ctx, size in
                    guard t >= 0, t < duration else { return }
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let progress = t / duration
                    let eased = 1 - pow(1 - progress, 3)
                    for i in 0..<40 {
                        let angle = Double(i) * 2.399963 // golden angle: an even fan
                        let speed = 70.0 + Double((i * 37) % 90)
                        let x = center.x + cos(angle) * speed * eased
                        let y = center.y + sin(angle) * speed * eased + 40 * progress * progress
                        let r = 1.5 + Double(i % 3)
                        ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                                 with: .color(colors[i % colors.count].opacity((1 - progress) * 0.9)))
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// Snowfall plus a snow cap on the connect button: December to mid-January.
struct Snow: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                for i in 0..<36 {
                    let speed = 14.0 + Double((i * 7) % 16)
                    let x = Double((i * 53) % 100) / 100 * size.width + sin(t * 0.7 + Double(i)) * 8
                    let y = (t * speed + Double(i * 41)).truncatingRemainder(dividingBy: size.height + 20) - 10
                    let r = 1.2 + Double(i % 3) * 0.7
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.35 + Double(i % 4) * 0.12)))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    static var isSeason: Bool {
        if UserDefaults.standard.bool(forKey: "winterPreview") { return true }
        let c = Calendar.current.dateComponents([.month, .day], from: .now)
        return c.month == 12 || (c.month == 1 && (c.day ?? 99) <= 15)
    }
}

/// Soft white cap along the top edge of the disc.
/// The time of year decides what drifts around the button: snow, petals or leaves. Summer stays clean.
enum Season {
    case winter, spring, autumn

    static var current: Season? {
        if UserDefaults.standard.bool(forKey: "winterPreview") { return .winter }
        let c = Calendar.current.dateComponents([.month, .day], from: .now)
        switch c.month ?? 0 {
        case 12: return .winter
        case 1: return (c.day ?? 99) <= 15 ? .winter : nil
        case 3, 4, 5: return .spring
        case 9, 10, 11: return .autumn
        default: return nil
        }
    }

    var colors: [Color] {
        switch self {
        case .winter: [.white]
        case .spring: [Color(red: 1.0, green: 0.74, blue: 0.82), Color(red: 1.0, green: 0.86, blue: 0.90)]
        case .autumn: [Color(red: 0.95, green: 0.55, blue: 0.18), Color(red: 0.80, green: 0.32, blue: 0.14), Color(red: 0.93, green: 0.74, blue: 0.25)]
        }
    }
}

/// Petals or leaves slowly turning as they fall.
struct FallingBits: View {
    let season: Season

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                for i in 0..<18 {
                    let speed = 16.0 + Double((i * 5) % 12)
                    let x = Double((i * 47) % 100) / 100 * size.width + sin(t * 0.8 + Double(i)) * 14
                    let y = (t * speed + Double(i * 37)).truncatingRemainder(dividingBy: size.height + 24) - 12
                    let w = 5.0 + Double(i % 3) * 1.6
                    var piece = ctx
                    piece.translateBy(x: x, y: y)
                    piece.rotate(by: .radians(t * 1.2 + Double(i)))
                    piece.fill(Path(ellipseIn: CGRect(x: -w, y: -w / 2.2, width: w * 2, height: w * 0.9)),
                               with: .color(season.colors[i % season.colors.count].opacity(0.75)))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct SnowCap: View {
    var body: some View {
        Circle()
            .trim(from: 0.63, to: 0.87)
            .stroke(LinearGradient(colors: [.white, .white.opacity(0.85)], startPoint: .top, endPoint: .bottom),
                    style: StrokeStyle(lineWidth: 9, lineCap: .round))
            .shadow(color: .white.opacity(0.35), radius: 6)
            .accessibilityHidden(true)
    }
}

/// Liquid Glass exists only on macOS/iOS 26; older systems get a plain blurred material.
struct GlassSurface: ViewModifier {
    let shape: AnyShape
    var interactive = false
    var clear = false
    var tint: Color?

    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26, iOS 26, *) {
            content.glassEffect(glass, in: shape)
        } else {
            content.background(clear ? .ultraThinMaterial : .regularMaterial, in: shape)
                .overlay(shape.stroke(.white.opacity(0.12), lineWidth: 0.5))
        }
    }

    @available(macOS 26, iOS 26, *)
    private var glass: Glass {
        var base: Glass = clear ? .clear : .regular
        if let tint { base = base.tint(tint) }
        return interactive ? base.interactive() : base
    }
}

extension View {
    func kGlass(in shape: some Shape, interactive: Bool = false, clear: Bool = false, tint: Color? = nil) -> some View {
        modifier(GlassSurface(shape: AnyShape(shape), interactive: interactive, clear: clear, tint: tint))
    }
}

/// `GlassEffectContainer` where available, a plain group otherwise.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26, iOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

/// Empty screen: the fox, one line on what will be here, one main action. An optional symbol says what is missing.
struct EmptyState<Actions: View>: View {
    @Environment(\.kitsuneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: LocalizedStringKey
    let text: LocalizedStringKey
    var symbol: String?
    @ViewBuilder var actions: Actions
    @State private var float = false

    var body: some View {
        VStack(spacing: 12) {
            FoxMark(color: theme.soft.opacity(0.8)).frame(width: 60)
                .overlay(alignment: .topTrailing) {
                    if let symbol {
                        Image(systemName: symbol)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(theme.accent)
                            .frame(width: 28, height: 28)
                            .kGlass(in: .circle)
                            .offset(x: 18, y: -10)
                    }
                }
                .offset(y: float ? -3 : 3)
                .padding(.top, 6)
            Text(title).font(.display(18, relativeTo: .title3)).padding(.top, 6)
            Text(text).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 300)
            actions.padding(.top, 8)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { float = true }
        }
    }
}

/// One short confirmation for every "copied / saved" action, at the bottom of the window.
@MainActor @Observable final class Toaster {
    static let shared = Toaster()
    private(set) var message: String?
    private var hide: Task<Void, Never>?

    func show(_ text: String) {
        withAnimation(.smooth(duration: 0.3)) { message = text }
        hide?.cancel()
        hide = Task {
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.3)) { message = nil }
        }
    }
}

struct ToastOverlay: View {
    var body: some View {
        if let message = Toaster.shared.message {
            Label(message, systemImage: "checkmark.circle.fill")
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 14).padding(.vertical, 9)
                .kGlass(in: .capsule)
                .padding(.bottom, 64)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .allowsHitTesting(false)
                .id(message)
        }
    }
}

/// A small "?" next to a setting that needs a sentence of explanation; the popover can show the route as icons.
struct HelpButton: View {
    @Environment(\.kitsuneTheme) private var theme
    let text: LocalizedStringKey
    var route: [String] = []
    @State private var shown = false

    var body: some View {
        Button { shown.toggle() } label: {
            Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Что это?")
        .popover(isPresented: $shown, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                if !route.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(Array(route.enumerated()), id: \.offset) { index, symbol in
                            if index > 0 { Image(systemName: "arrow.right").font(.caption2.weight(.bold)).foregroundStyle(.tertiary) }
                            Image(systemName: symbol).font(.title3).foregroundStyle(theme.accent)
                        }
                    }
                }
                Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(width: 280, alignment: .leading)
        }
    }
}

/// A soft light sweeping over placeholders while something loads, instead of an empty space.
struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -0.6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, .white.opacity(0.14), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.5)
                        .offset(x: phase * geo.size.width)
                }
                .mask(content)
                .opacity(reduceMotion ? 0 : 1)
            }
            .onAppear { withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1.1 } }
    }
}

extension View {
    func shimmer() -> some View { modifier(Shimmer()) }
}

/// The connect button's ring: the theme colour, or for the reward themes a gradient that slowly turns around.
/// `color` overrides it (the amber/red latency warning).
struct ThemeStroke: View {
    let theme: ButtonTheme
    var color: Color?
    var trim: Double = 1
    var lineWidth: CGFloat = 2.5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var turn = false

    var body: some View {
        if let gradient = theme.gradient, color == nil {
            // A calm rim in the deep tone with one bright comet slowly running around it.
            let comet = AngularGradient(stops: [
                .init(color: gradient[1].opacity(0), location: 0.45),
                .init(color: gradient[1], location: 0.8),
                .init(color: gradient[0], location: 0.97),
                .init(color: gradient[0].opacity(0), location: 0.975),
            ], center: .center)
            ZStack {
                Circle().trim(from: 0, to: trim).stroke(gradient[1].opacity(0.35), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                Circle().trim(from: 0, to: trim).stroke(comet, style: StrokeStyle(lineWidth: lineWidth + 0.5, lineCap: .round))
                    .shadow(color: gradient[0].opacity(0.8), radius: 4)
                    .rotationEffect(.degrees(turn ? 360 : 0))
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) { turn = true }
            }
        } else {
            Circle().trim(from: 0, to: trim).stroke(color ?? theme.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        }
    }
}

extension ButtonTheme {
    /// The disc behind the fox when connected.
    func discFill(opacity: Double) -> AnyShapeStyle {
        guard let gradient else { return AnyShapeStyle(accent.opacity(opacity)) }
        // Soft light from the upper left into the deep tone: volume without seams.
        return AnyShapeStyle(RadialGradient(colors: [gradient[0].opacity(opacity * 1.5), gradient[1].opacity(opacity * 1.2)],
                                            center: UnitPoint(x: 0.35, y: 0.28), startRadius: 0, endRadius: 140))
    }
}

/// Where each list was scrolled: tabs are rebuilt on every switch, so coming back would otherwise start at the top.
@MainActor enum ScrollMemory { static var offsets: [String: CGFloat] = [:] }

private struct RememberScroll: ViewModifier {
    let key: String
    @Binding var position: ScrollPosition
    let onOffset: (CGFloat) -> Void
    /// Read when the screen is built: the fresh scroll view reports 0 first and would overwrite it.
    @State private var target: CGFloat?
    @State private var restored = false

    init(key: String, position: Binding<ScrollPosition>, onOffset: @escaping (CGFloat) -> Void) {
        self.key = key
        _position = position
        self.onOffset = onOffset
        _target = State(initialValue: ScrollMemory.offsets[key])
    }

    func body(content: Content) -> some View {
        content
            .scrollPosition($position)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in
                onOffset(y)
                if restored { ScrollMemory.offsets[key] = y }
            }
            .task {
                defer { restored = true }
                guard let y = target, y > 1 else { return }
                try? await Task.sleep(for: .milliseconds(80)) // lazy content needs a pass to lay out first
                position.scrollTo(y: y)
                try? await Task.sleep(for: .milliseconds(80))
            }
    }
}

extension View {
    func rememberScroll(_ key: String, position: Binding<ScrollPosition>, onOffset: @escaping (CGFloat) -> Void = { _ in }) -> some View {
        modifier(RememberScroll(key: key, position: position, onOffset: onOffset))
    }

    /// One readable column, centred, when the window is stretched wide.
    func readableWidth(_ width: CGFloat = 620) -> some View { frame(maxWidth: width).frame(maxWidth: .infinity) }
}


/// Small empty state for a list: the fox, a line and a hint what to do.
struct MiniEmpty: View {
    @Environment(\.kitsuneTheme) private var theme
    let title: LocalizedStringKey
    let hint: LocalizedStringKey
    var body: some View {
        HStack(spacing: 14) {
            FoxMark(color: theme.soft.opacity(0.7)).frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(hint).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

extension ButtonTheme {
    /// The theme for a colour picked on the Design pane.
    static func custom(_ color: Color) -> ButtonTheme {
        #if os(macOS)
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .orange
        let pack = { (v: CGFloat) in UInt32((min(max(v, 0), 1) * 255).rounded()) }
        return .custom(pack(c.redComponent) << 16 | pack(c.greenComponent) << 8 | pack(c.blueComponent))
        #else
        return .copper
        #endif
    }
}
