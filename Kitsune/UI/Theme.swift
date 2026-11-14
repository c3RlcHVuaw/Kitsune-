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
    var title: LocalizedStringKey?
    var footer: LocalizedStringKey?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { Text(title).font(.footnote).foregroundStyle(.secondary).padding(.leading, 16) }
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
            if let footer { Text(footer).font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 16) }
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
enum ButtonTheme: String, CaseIterable {
    case copper, moon, neon

    var accent: Color {
        switch self {
        case .copper: Color(red: 1.0, green: 0.50, blue: 0.10)
        case .moon: Color(red: 0.55, green: 0.70, blue: 1.0)
        case .neon: Color(red: 0.12, green: 0.95, blue: 0.62)
        }
    }

    /// The idle fox and soft highlights.
    var soft: Color {
        switch self {
        case .copper: Color(red: 0.96, green: 0.80, blue: 0.62)
        case .moon: Color(red: 0.84, green: 0.90, blue: 1.0)
        case .neon: Color(red: 0.74, green: 1.0, blue: 0.90)
        }
    }

    /// Slightly deeper tone for the background glow.
    var glow: Color {
        switch self {
        case .copper: Color(red: 0.85, green: 0.42, blue: 0.18)
        case .moon: Color(red: 0.40, green: 0.52, blue: 0.92)
        case .neon: Color(red: 0.08, green: 0.75, blue: 0.50)
        }
    }

    /// System sounds for connecting and for a user-driven disconnect: each theme sounds a little different.
    var sounds: (connect: String, disconnect: String) {
        switch self {
        case .copper: ("Glass", "Pop")
        case .moon: ("Ping", "Tink")
        case .neon: ("Hero", "Bottle")
        }
    }

    var title: LocalizedStringKey {
        switch self { case .copper: "Медь"; case .moon: "Луна"; case .neon: "Неон" }
    }
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
