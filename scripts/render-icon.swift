// Renders the 1024×1024 app icon from the same fox geometry as FoxMark.swift (keep them in sync).
// Run: swift scripts/render-icon.swift Kitsune/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import AppKit
import SwiftUI

struct FoxHead: Shape {
    func path(in r: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + r.width * x, y: r.minY + r.height * y) }
        return Path { p in
            p.move(to: pt(0.10, 0.10)); p.addLine(to: pt(0.38, 0.36)); p.addLine(to: pt(0.62, 0.36))
            p.addLine(to: pt(0.90, 0.10)); p.addLine(to: pt(0.90, 0.52)); p.addLine(to: pt(0.50, 0.92))
            p.addLine(to: pt(0.10, 0.52)); p.closeSubpath()
        }
    }
}

/// Flat white fox on the brand orange — nothing else.
struct Icon: View {
    var body: some View {
        ZStack {
            Color(red: 0.91, green: 0.39, blue: 0.16)
            FoxHead().fill(.white).frame(width: 560, height: 560).offset(y: 10)
        }
        .frame(width: 1024, height: 1024)
    }
}

@MainActor func render() throws {
    let renderer = ImageRenderer(content: Icon())
    renderer.scale = 1
    guard let image = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
    // App icons must be opaque: redraw without alpha.
    let ctx = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}

try MainActor.assumeIsolated { try render() }
