import SwiftUI

/// Kitsune mark: one flat fox-head silhouette, seven straight lines, no gradients or details.
/// Same geometry as the app icon (scripts/render-icon.swift).
struct FoxMark: View {
    var color: Color = .brand
    /// 0...1: ears fall outward and down (error). `sway` -1...1: both ears lean sideways (the happy wiggle on connect).
    var droop: CGFloat = 0
    var sway: CGFloat = 0
    /// 0...1: only the right ear flicks.
    var twitch: CGFloat = 0

    var body: some View {
        FoxHead(droop: droop, sway: sway, twitch: twitch)
            .fill(color)
            .aspectRatio(1, contentMode: .fit)
            .accessibilityHidden(true)
    }
}

struct FoxHead: Shape {
    var droop: CGFloat = 0
    var sway: CGFloat = 0
    var twitch: CGFloat = 0

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get { AnimatablePair(AnimatablePair(droop, sway), twitch) }
        set { droop = newValue.first.first; sway = newValue.first.second; twitch = newValue.second }
    }

    func path(in r: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + r.width * x, y: r.minY + r.height * y) }
        return Path { p in
            p.move(to: pt(0.10 - 0.06 * droop + 0.06 * sway, 0.10 + 0.18 * droop))  // left ear tip
            p.addLine(to: pt(0.38, 0.36))
            p.addLine(to: pt(0.62, 0.36))
            p.addLine(to: pt(0.90 + 0.06 * droop + 0.06 * sway + 0.05 * twitch, 0.10 + 0.18 * droop + 0.07 * twitch)) // right ear tip
            p.addLine(to: pt(0.90, 0.52))
            p.addLine(to: pt(0.50, 0.92)) // muzzle
            p.addLine(to: pt(0.10, 0.52))
            p.closeSubpath()
        }
    }
}

/// Fan of `count` tails behind the head: the rank shows in the silhouette (1…4, nine for «Ёкай»).
struct FoxTails: Shape {
    var count: Int
    /// 0...1: the fan opens from a single line to its full spread.
    var fan: CGFloat = 1
    var animatableData: CGFloat { get { fan } set { fan = newValue } }

    func path(in r: CGRect) -> Path {
        var path = Path()
        let n = max(count, 0)
        guard n > 0 else { return path }
        let pivot = CGPoint(x: r.midX, y: r.minY + r.height * 0.74)
        let length = r.height * 0.52, half = r.width * (n > 4 ? 0.045 : 0.07)
        for i in 0..<n {
            // one tail leans right like a fox's; more of them fan out symmetrically
            let t = n == 1 ? 0.78 : Double(i) / Double(n - 1)
            let spread = n > 4 ? 150.0 : 100.0
            let deg = n == 1 ? 38.0 * fan : (-spread / 2 + spread * t) * fan
            let a = deg * .pi / 180
            let dir = CGPoint(x: sin(a), y: -cos(a)), side = CGPoint(x: cos(a), y: sin(a))
            let tip = CGPoint(x: pivot.x + dir.x * length, y: pivot.y + dir.y * length)
            let mid = CGPoint(x: pivot.x + dir.x * length * 0.55, y: pivot.y + dir.y * length * 0.55)
            path.move(to: pivot)
            path.addQuadCurve(to: tip, control: CGPoint(x: mid.x + side.x * half * 2.2, y: mid.y + side.y * half * 2.2))
            path.addQuadCurve(to: pivot, control: CGPoint(x: mid.x - side.x * half * 2.2, y: mid.y - side.y * half * 2.2))
        }
        return path
    }
}

/// Head with its rank tails. Without tails it is just the plain `FoxMark`.
struct FoxWithTails: View {
    var tails: Int
    var color: Color = .brand
    var fan: CGFloat = 1
    var body: some View {
        if tails <= 0 {
            FoxMark(color: color)
        } else {
            ZStack {
                FoxTails(count: tails, fan: fan).fill(color.opacity(0.5))
                FoxMark(color: color).scaleEffect(0.64).offset(y: 0.0).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .aspectRatio(1, contentMode: .fit)
        }
    }
}
