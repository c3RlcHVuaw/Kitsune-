import SwiftUI

/// Kitsune mark: one flat fox-head silhouette, seven straight lines, no gradients or details.
/// Same geometry as the app icon (scripts/render-icon.swift).
struct FoxMark: View {
    var color: Color = .brand

    var body: some View {
        FoxHead()
            .fill(color)
            .aspectRatio(1, contentMode: .fit)
            .accessibilityHidden(true)
    }
}

struct FoxHead: Shape {
    func path(in r: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + r.width * x, y: r.minY + r.height * y) }
        return Path { p in
            p.move(to: pt(0.10, 0.10))  // left ear tip
            p.addLine(to: pt(0.38, 0.36))
            p.addLine(to: pt(0.62, 0.36))
            p.addLine(to: pt(0.90, 0.10)) // right ear tip
            p.addLine(to: pt(0.90, 0.52))
            p.addLine(to: pt(0.50, 0.92)) // muzzle
            p.addLine(to: pt(0.10, 0.52))
            p.closeSubpath()
        }
    }
}
