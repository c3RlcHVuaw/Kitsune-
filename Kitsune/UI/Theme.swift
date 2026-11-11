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
            .glassEffect(.regular.interactive(), in: .capsule)
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
        glassEffect(interactive ? .clear.tint(.white.opacity(0.2)).interactive() : .clear.tint(.white.opacity(0.2)), in: shape)
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
            .glassEffect(.regular, in: .rect(cornerRadius: 20))
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
