import SwiftUI

/// Brand background. Flat orange at rest, redder on error; while connecting and connected it melts into a slowly
/// breathing edge-light glow on a near-black base.
struct KitsuneBackground: View {
    enum Mood { case idle, connecting, connected, error }

    var mood: Mood = .idle
    /// False on tabs that aren't on screen: their glow stops animating (and costing GPU) until they are shown.
    var active = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Always dark; only the edge light changes: dim and still at rest, alive when the tunnel is busy or up, red on error.
        FlowingGradient(animated: !reduceMotion && mood != .error,
                        paused: !active,
                        intensity: intensity,
                        alarm: mood == .error)
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 1.1), value: mood)
    }

    private var intensity: Double {
        switch mood {
        case .idle: 0
        case .connecting: 0.6
        case .connected: 1
        case .error: 0.7
        }
    }
}

/// Almost flat near-black with a faint top light. No colour blobs (they read as "AI wallpaper"): the only colour is
/// one restrained copper glow behind the connect button that appears with the tunnel and breathes slowly.
private struct FlowingGradient: View {
    let animated: Bool
    let paused: Bool
    var intensity = 1.0
    var alarm = false

    private var tint: Color { alarm ? Color(red: 0.75, green: 0.16, blue: 0.16) : Color(red: 0.85, green: 0.42, blue: 0.18) }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !animated || paused)) { context in
            let breathe = animated ? 0.5 + 0.5 * sin(context.date.timeIntervalSinceReferenceDate * 0.9) : 0.5
            GeometryReader { proxy in
                let h = proxy.size.height
                ZStack {
                    Color(red: 0.028, green: 0.026, blue: 0.030)
                    RadialGradient(colors: [.white.opacity(0.05), .clear], center: UnitPoint(x: 0.5, y: 0), startRadius: 0, endRadius: h * 0.6)
                    RadialGradient(colors: [tint.opacity(0.30 * intensity * (0.8 + 0.2 * breathe)), tint.opacity(0.08 * intensity), .clear],
                                   center: UnitPoint(x: 0.5, y: 0.40), startRadius: 0, endRadius: h * 0.42)
                }
            }
        }
    }
}
